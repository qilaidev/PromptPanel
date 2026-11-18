import Foundation
import GRDB

/// Data access layer for entries and their historical version snapshots.
final class EntryRepository: @unchecked Sendable {

    static let hasTagDatabaseFunction = DatabaseFunction("pp_has_tag", argumentCount: 2, pure: true) { dbValues in
        guard let rawTags = String.fromDatabaseValue(dbValues[0]),
              !rawTags.isEmpty,
              rawTags != "[]",
              let rawTarget = String.fromDatabaseValue(dbValues[1]) else {
            return false
        }
        let target = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else {
            return true
        }
        let decoded = EntryTagsCodec.decode(rawTags)
        return decoded.contains { $0.caseInsensitiveCompare(target) == .orderedSame }
    }

    static let icontainsDatabaseFunction = DatabaseFunction("pp_icontains", argumentCount: 2, pure: true) { dbValues in
        guard let haystack = String.fromDatabaseValue(dbValues[0]),
              let needle = String.fromDatabaseValue(dbValues[1]) else {
            return false
        }
        if needle.isEmpty {
            return true
        }
        return haystack.localizedStandardContains(needle)
    }

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Read

    /// Fetch entries for a given project, respecting PRD sort order.
    func fetchByProject(_ projectId: String) throws -> [Entry] {
        try fetchByProjects([projectId])
    }

    /// Fetch entries across one or more projects with the standard ordering.
    func fetchByProjects(_ projectIds: [String], limit: Int? = nil) throws -> [Entry] {
        let ids = projectIds.uniqued()
        guard !ids.isEmpty else {
            return []
        }

        return try dbQueue.read { db in
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let limitClause = (limit.map { $0 > 0 } == true) ? "\nLIMIT ?" : ""
            let sql = """
                SELECT entries.*
                FROM entries
                WHERE entries.deleted_at IS NULL
                  AND entries.project_id IN (\(placeholders))
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: false))\(limitClause)
                """
            var arguments = StatementArguments(ids)
            arguments += [Date()] // pp_frecency's `now`, appended after the WHERE binds
            if let limit, limit > 0 {
                arguments += [limit]
            }
            return try Entry.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Fetch all non-deleted entries for management and all-projects views.
    func fetchAll(excludeArchivedProjects: Bool = false, limit: Int? = nil) throws -> [Entry] {
        try dbQueue.read { db in
            let archiveClause = excludeArchivedProjects
                ? "\n  AND entries.project_id IN (SELECT id FROM projects WHERE deleted_at IS NULL AND is_archived = 0)"
                : ""
            let limitClause = (limit.map { $0 > 0 } == true) ? "\nLIMIT ?" : ""
            let sql = """
                SELECT entries.*
                FROM entries
                WHERE entries.deleted_at IS NULL\(archiveClause)
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: false))\(limitClause)
                """
            var arguments: StatementArguments = [Date()]
            if let limit, limit > 0 {
                arguments += [limit]
            }
            return try Entry.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Fetch entries for the current project + default project, mixed and sorted per PRD.
    /// Current project entries rank above default project entries when all other sort keys are equal.
    func fetchMixed(currentProjectId: String, defaultProjectId: String, limit: Int? = nil) throws -> [Entry] {
        try dbQueue.read { db in
            let limitClause = (limit.map { $0 > 0 } == true) ? "\nLIMIT ?" : ""
            let sql = """
                SELECT entries.*,
                       CASE WHEN entries.project_id = ? THEN 0 ELSE 1 END AS project_priority
                FROM entries
                WHERE entries.deleted_at IS NULL
                  AND entries.project_id IN (?, ?)
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: true))\(limitClause)
                """
            var arguments: StatementArguments = [currentProjectId, currentProjectId, defaultProjectId, Date()]
            if let limit, limit > 0 {
                arguments += [limit]
            }
            return try Entry.fetchAll(
                db,
                sql: sql,
                arguments: arguments
            )
        }
    }

    /// Full-text search across title and content, limited to specific projects.
    func search(
        query: String,
        currentProjectId: String,
        defaultProjectId: String,
        tag: String? = nil
    ) throws -> [Entry] {
        let normalizedTag = Self.normalizedTag(tag)
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            guard let normalizedTag else {
                return try fetchMixed(currentProjectId: currentProjectId, defaultProjectId: defaultProjectId)
            }
            return try dbQueue.read { db in
                let sql = """
                    SELECT entries.*,
                           CASE WHEN entries.project_id = ? THEN 0 ELSE 1 END AS project_priority
                    FROM entries
                    WHERE entries.deleted_at IS NULL
                      AND entries.project_id IN (?, ?)
                      AND pp_has_tag(entries.tags, ?)
                    \(EntryRanking.sqlOrderByClause(includeProjectPriority: true))
                    """
                return try Entry.fetchAll(
                    db,
                    sql: sql,
                    arguments: [currentProjectId, currentProjectId, defaultProjectId, normalizedTag, Date()]
                )
            }
        }

        return try search(
            query: query,
            projectIds: [currentProjectId, defaultProjectId],
            currentProjectId: currentProjectId,
            tag: normalizedTag
        )
    }

    /// Full-text search across title and content across all projects.
    func searchAll(query: String, tag: String? = nil, excludeArchivedProjects: Bool = false) throws -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTag = Self.normalizedTag(tag)
        let archiveClause = excludeArchivedProjects
            ? "\n  AND entries.project_id IN (SELECT id FROM projects WHERE deleted_at IS NULL AND is_archived = 0)"
            : ""

        guard !trimmed.isEmpty else {
            guard let normalizedTag else {
                return try fetchAll(excludeArchivedProjects: excludeArchivedProjects)
            }
            return try dbQueue.read { db in
                let sql = """
                    SELECT entries.*
                    FROM entries
                    WHERE entries.deleted_at IS NULL\(archiveClause)
                      AND pp_has_tag(entries.tags, ?)
                    \(EntryRanking.sqlOrderByClause(includeProjectPriority: false))
                    """
                return try Entry.fetchAll(db, sql: sql, arguments: [normalizedTag, Date()])
            }
        }

        return try dbQueue.read { db in
            db.add(function: Self.icontainsDatabaseFunction)
            let queryPredicate = Self.makeSearchPredicate(from: trimmed)
            let tagClause = normalizedTag != nil ? "\n  AND pp_has_tag(entries.tags, ?)" : ""
            let sql = """
                SELECT entries.*
                FROM entries
                WHERE entries.deleted_at IS NULL\(archiveClause)\(tagClause)
                  AND (\(queryPredicate.sql))
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: false))
                LIMIT 100
                """
            var arguments = StatementArguments()
            if let normalizedTag {
                arguments += [normalizedTag]
            }
            arguments += queryPredicate.arguments
            arguments += [Date()]
            return try Entry.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Full-text search across title and content for arbitrary project IDs.
    func search(
        query: String,
        projectIds: [String],
        currentProjectId: String? = nil,
        tag: String? = nil
    ) throws -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = projectIds.uniqued()
        let normalizedTag = Self.normalizedTag(tag)

        guard !ids.isEmpty else {
            return []
        }

        guard !trimmed.isEmpty else {
            guard let normalizedTag else {
                return try fetchByProjects(ids)
            }
            return try dbQueue.read { db in
                let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
                let sql = """
                    SELECT entries.*,
                           CASE
                               WHEN ? IS NOT NULL AND entries.project_id = ? THEN 0
                               ELSE 1
                           END AS project_priority
                    FROM entries
                    WHERE entries.deleted_at IS NULL
                      AND entries.project_id IN (\(placeholders))
                      AND pp_has_tag(entries.tags, ?)
                    \(EntryRanking.sqlOrderByClause(includeProjectPriority: currentProjectId != nil))
                    """
                var arguments: StatementArguments = [currentProjectId, currentProjectId]
                arguments += StatementArguments(ids)
                arguments += [normalizedTag, Date()]
                return try Entry.fetchAll(db, sql: sql, arguments: arguments)
            }
        }

        return try dbQueue.read { db in
            db.add(function: Self.icontainsDatabaseFunction)
            let queryPredicate = Self.makeSearchPredicate(from: trimmed)
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let tagClause = normalizedTag != nil ? "\n  AND pp_has_tag(entries.tags, ?)" : ""
            let sql = """
                SELECT entries.*,
                       CASE
                           WHEN ? IS NOT NULL AND entries.project_id = ? THEN 0
                           ELSE 1
                       END AS project_priority
                FROM entries
                WHERE entries.deleted_at IS NULL
                  AND entries.project_id IN (\(placeholders))\(tagClause)
                  AND (\(queryPredicate.sql))
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: currentProjectId != nil))
                LIMIT 100
                """
            var arguments: StatementArguments = [currentProjectId, currentProjectId]
            arguments += StatementArguments(ids)
            if let normalizedTag {
                arguments += [normalizedTag]
            }
            arguments += queryPredicate.arguments
            arguments += [Date()] // pp_frecency's `now`
            return try Entry.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    private static func normalizedTag(_ tag: String?) -> String? {
        guard let trimmed = tag?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func searchTokens(from rawQuery: String) -> [String] {
        rawQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func makeTrigramFTS5Query(fromTokens tokens: [String]) -> String {
        tokens
            .map { token in
                let escapedToken = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escapedToken)\""
            }
            .joined(separator: " ")
    }

    private static func makeSearchPredicate(from rawQuery: String) -> (sql: String, arguments: StatementArguments) {
        let tokens = searchTokens(from: rawQuery)
        guard !tokens.isEmpty else {
            return ("0", StatementArguments())
        }

        let trigramTokens = tokens.filter { $0.unicodeScalars.count >= 3 }
        let shortTokens = tokens.filter { $0.unicodeScalars.count < 3 }

        var clauses: [String] = []
        var arguments = StatementArguments()

        if !trigramTokens.isEmpty {
            clauses.append(
                "entries.rowid IN (SELECT rowid FROM entries_fts WHERE entries_fts MATCH ?)"
            )
            arguments += [makeTrigramFTS5Query(fromTokens: trigramTokens)]
        }

        if !shortTokens.isEmpty {
            let shortClauses = Array(
                repeating: "(pp_icontains(entries.title, ?) OR pp_icontains(entries.content, ?) OR pp_icontains(entries.tags, ?))",
                count: shortTokens.count
            ).joined(separator: " AND ")
            clauses.append("(\(shortClauses))")
            for token in shortTokens {
                arguments += [token, token, token]
            }
        }

        return (clauses.joined(separator: " AND "), arguments)
    }

    /// Fetch a single entry by ID.
    func fetchById(_ id: String) throws -> Entry? {
        try dbQueue.read { db in
            try Entry
                .filter(Entry.Columns.id == id && Entry.Columns.deletedAt == nil)
                .fetchOne(db)
        }
    }

    /// Total active entry count per project.
    func entryCountByProject() throws -> [String: Int] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT project_id, COUNT(*) AS count FROM entries WHERE deleted_at IS NULL GROUP BY project_id"
            )
            var result: [String: Int] = [:]
            for row in rows {
                let projectId: String = row["project_id"]
                let count: Int = row["count"]
                result[projectId] = count
            }
            return result
        }
    }

    // MARK: - Version History Read & Restore

    /// Fetch all historical versions of an entry, ordered from newest (`version_number DESC`) to oldest.
    func fetchVersions(forEntryId entryId: String) throws -> [EntryVersion] {
        try dbQueue.read { db in
            try EntryVersion
                .filter(EntryVersion.Columns.entryId == entryId)
                .order(EntryVersion.Columns.versionNumber.desc)
                .fetchAll(db)
        }
    }

    /// Restore an entry's title and content to a historical version snapshot, recording a new version entry.
    @discardableResult
    func restoreVersion(versionId: String) throws -> Entry {
        try dbQueue.write { db in
            guard let targetVersion = try EntryVersion.fetchOne(db, key: versionId) else {
                throw RepositoryError.notFound("EntryVersion \(versionId)")
            }
            guard var entry = try Entry.fetchOne(db, key: targetVersion.entryId), entry.deletedAt == nil else {
                throw RepositoryError.notFound("Entry \(targetVersion.entryId)")
            }

            let now = Date()
            entry.title = targetVersion.title
            entry.content = targetVersion.content
            entry.updatedAt = now
            try entry.update(db)

            let currentMaxVersion = try Int.fetchOne(
                db,
                sql: "SELECT MAX(version_number) FROM entry_versions WHERE entry_id = ?",
                arguments: [entry.id]
            ) ?? 1
            let restoredSnapshot = EntryVersion(
                entryId: entry.id,
                versionNumber: currentMaxVersion + 1,
                title: entry.title,
                content: entry.content,
                changeNote: "恢复自 v\(targetVersion.versionNumber)",
                createdAt: now
            )
            try restoredSnapshot.insert(db)
            return entry
        }
    }

    // MARK: - Write

    /// Create a new entry and record its initial v1 version snapshot.
    func create(_ entry: Entry, changeNote: String = "初始版本") throws {
        try dbQueue.write { db in
            var entryToSave = entry
            entryToSave.deletedAt = nil
            try entryToSave.save(db)
            let existingMaxVersion = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(version_number), 0) FROM entry_versions WHERE entry_id = ?",
                arguments: [entryToSave.id]
            ) ?? 0
            let initialVersion = EntryVersion(
                entryId: entryToSave.id,
                versionNumber: existingMaxVersion + 1,
                title: entryToSave.title,
                content: entryToSave.content,
                changeNote: changeNote,
                createdAt: entryToSave.createdAt
            )
            try initialVersion.insert(db)
        }
        PPLogger.entry.debug("Entry created: \(entry.id)")
    }

    /// Update an existing entry. Automatically records a new `EntryVersion` if `recordVersion` is true and title or content changed.
    func update(_ entry: Entry, changeNote: String? = nil, recordVersion: Bool = true) throws {
        var updated = entry
        let now = Date()
        updated.updatedAt = now
        try dbQueue.write { db in
            let previous = try Entry.fetchOne(db, key: entry.id)
            try updated.update(db)

            guard recordVersion else { return }

            let contentChanged = previous.map { $0.title != updated.title || $0.content != updated.content } ?? true
            if contentChanged {
                let existingMaxVersion = try Int.fetchOne(
                    db,
                    sql: "SELECT MAX(version_number) FROM entry_versions WHERE entry_id = ?",
                    arguments: [updated.id]
                )
                if existingMaxVersion == nil, let previous {
                    // Backfill v1 for an entry that pre-dated version tracking
                    let baseline = EntryVersion(
                        entryId: previous.id,
                        versionNumber: 1,
                        title: previous.title,
                        content: previous.content,
                        changeNote: "初始版本",
                        createdAt: previous.createdAt
                    )
                    try baseline.insert(db)
                }
                let nextVersionNumber = ((existingMaxVersion ?? (previous != nil ? 1 : 0)) + 1)
                let snapshot = EntryVersion(
                    entryId: updated.id,
                    versionNumber: nextVersionNumber,
                    title: updated.title,
                    content: updated.content,
                    changeNote: changeNote ?? "编辑保存",
                    createdAt: now
                )
                try snapshot.insert(db)
            }
        }
        PPLogger.entry.debug("Entry updated: \(entry.id)")
    }

    /// Clone an existing entry (e.g. from a reusable Category) into a target Project as an independent copy.
    @discardableResult
    func cloneEntry(
        id: String,
        toProjectId targetProjectId: String,
        titleOverride: String? = nil
    ) throws -> Entry {
        try dbQueue.write { db in
            guard let source = try Entry.fetchOne(db, key: id), source.deletedAt == nil else {
                throw RepositoryError.notFound("Entry \(id)")
            }
            guard let targetProject = try Project.fetchOne(db, key: targetProjectId), targetProject.deletedAt == nil else {
                throw RepositoryError.notFound("Project \(targetProjectId)")
            }

            let now = Date()
            let cloned = Entry(
                projectId: targetProject.id,
                title: titleOverride ?? source.title,
                content: source.content,
                type: source.type,
                isPinned: false,
                isCompleted: false,
                sortOrder: 0,
                useCount: 0,
                lastUsedAt: nil,
                createdAt: now,
                updatedAt: now,
                sourceEntryId: source.id,
                tags: source.tags
            )
            try cloned.insert(db)

            let initialVersion = EntryVersion(
                entryId: cloned.id,
                versionNumber: 1,
                title: cloned.title,
                content: cloned.content,
                changeNote: "克隆自「\(source.title)」",
                createdAt: now
            )
            try initialVersion.insert(db)
            return cloned
        }
    }

    /// Toggle or set completion state for a Todo / Scratchpad entry.
    func setCompleted(id: String, isCompleted: Bool) throws {
        try dbQueue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    UPDATE entries
                    SET is_completed = ?,
                        updated_at = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [isCompleted, now, id]
            )
            try Self.requireChangedRow(in: db, entity: "Entry \(id)")
        }
        PPLogger.entry.debug("Completion state updated for entry: \(id) completed=\(isCompleted)")
    }

    /// Soft-delete all active completed entries (optionally scoped to a specific project or excluding archived projects), returning the count of updated rows.
    @discardableResult
    func deleteCompleted(projectId: String? = nil, excludeArchivedProjects: Bool = false) throws -> Int {
        let deletedCount = try dbQueue.write { db -> Int in
            let now = Date()
            if let projectId {
                try db.execute(
                    sql: """
                        UPDATE entries
                        SET deleted_at = ?,
                            updated_at = ?
                        WHERE deleted_at IS NULL
                          AND is_completed = 1
                          AND project_id = ?
                        """,
                    arguments: [now, now, projectId]
                )
            } else if excludeArchivedProjects {
                try db.execute(
                    sql: """
                        UPDATE entries
                        SET deleted_at = ?,
                            updated_at = ?
                        WHERE deleted_at IS NULL
                          AND is_completed = 1
                          AND project_id IN (
                              SELECT id FROM projects WHERE deleted_at IS NULL AND is_archived = 0
                          )
                        """,
                    arguments: [now, now]
                )
            } else {
                try db.execute(
                    sql: """
                        UPDATE entries
                        SET deleted_at = ?,
                            updated_at = ?
                        WHERE deleted_at IS NULL
                          AND is_completed = 1
                        """,
                    arguments: [now, now]
                )
            }
            let count = db.changesCount
            if count >= 3 {
                try db.execute(
                    sql: "INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) VALUES ('pending_allow_mass_delete', '1', ?)",
                    arguments: [now]
                )
            }
            return count
        }
        PPLogger.entry.debug("Soft-deleted \(deletedCount) completed entries (projectId=\(projectId ?? "all"), excludeArchived=\(excludeArchivedProjects))")
        return deletedCount
    }

    /// Batch-move multiple entries to a target project in a single atomic transaction.
    @discardableResult
    func moveEntries(ids: [String], toProjectId targetProjectId: String) throws -> Int {
        let uniqueIds = ids.uniqued()
        guard !uniqueIds.isEmpty else { return 0 }
        let movedCount = try dbQueue.write { db -> Int in
            guard let targetProject = try Project.fetchOne(db, key: targetProjectId),
                  targetProject.deletedAt == nil else {
                throw RepositoryError.notFound("Project \(targetProjectId)")
            }
            let now = Date()
            let placeholders = uniqueIds.map { _ in "?" }.joined(separator: ", ")
            var arguments: StatementArguments = [targetProject.id, now, targetProject.id]
            arguments += StatementArguments(uniqueIds)
            try db.execute(
                sql: """
                    UPDATE entries
                    SET project_id = ?,
                        updated_at = ?
                    WHERE deleted_at IS NULL
                      AND project_id != ?
                      AND id IN (\(placeholders))
                    """,
                arguments: arguments
            )
            return db.changesCount
        }
        PPLogger.entry.debug("Batch-moved \(movedCount) entries to project: \(targetProjectId)")
        return movedCount
    }

    /// Soft-delete an entry by ID so cloud sync propagates a tombstone instead of resurrecting it.
    func delete(id: String) throws {
        try dbQueue.write { db in
            guard var entry = try Entry.fetchOne(db, key: id), entry.deletedAt == nil else {
                throw RepositoryError.notFound("Entry \(id)")
            }
            let now = Date()
            entry.deletedAt = now
            entry.updatedAt = now
            try entry.update(db)
        }
        PPLogger.entry.debug("Entry soft-deleted: \(id)")
    }

    /// Record an execution: increment use_count and set last_used_at without bumping updated_at,
    /// so routine usage/pasting never overwrites newer remote content edits during LWW cloud sync.
    func recordExecution(id: String) throws {
        try dbQueue.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    UPDATE entries
                    SET use_count = use_count + 1,
                        last_used_at = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [now, id]
            )
            try Self.requireChangedRow(in: db, entity: "Entry \(id)")
        }
        PPLogger.entry.debug("Execution recorded for entry: \(id)")
    }

    private static func requireChangedRow(in db: Database, entity: String) throws {
        guard db.changesCount > 0 else {
            throw RepositoryError.notFound(entity)
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
