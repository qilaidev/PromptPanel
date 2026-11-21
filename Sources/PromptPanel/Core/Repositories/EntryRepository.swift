import Foundation
import GRDB

/// Data access layer for entries and their historical version snapshots.
final class EntryRepository: @unchecked Sendable {

    enum EditableFieldsUpdateResult: Equatable {
        case updated(Entry)
        case deletedOrMissing
    }

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
            arguments += [Date().timeIntervalSince1970] // pp_frecency's `now`, appended after the WHERE binds
            if let limit, limit > 0 {
                arguments += [limit]
            }
            return try Entry.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Fetch all non-deleted entries for management and all-projects views.
    func fetchAll(excludeArchivedProjects: Bool = true, limit: Int? = nil) throws -> [Entry] {
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
            var arguments: StatementArguments = [Date().timeIntervalSince1970]
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
            var arguments: StatementArguments = [
                currentProjectId,
                currentProjectId,
                defaultProjectId,
                Date().timeIntervalSince1970,
            ]
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
        tag: String? = nil,
        limit: Int? = nil
    ) throws -> [Entry] {
        let normalizedTag = Self.normalizedTag(tag)
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            guard let normalizedTag else {
                return try fetchMixed(
                    currentProjectId: currentProjectId,
                    defaultProjectId: defaultProjectId,
                    limit: limit
                )
            }
            return try dbQueue.read { db in
                let limitClause = (limit.map { $0 > 0 } == true) ? "\nLIMIT ?" : ""
                let sql = """
                    SELECT entries.*,
                           CASE WHEN entries.project_id = ? THEN 0 ELSE 1 END AS project_priority
                    FROM entries
                    WHERE entries.deleted_at IS NULL
                      AND entries.project_id IN (?, ?)
                      AND EXISTS (
                          SELECT 1 FROM entry_tags
                          WHERE entry_tags.entry_id = entries.id AND entry_tags.tag_lower = ?
                      )
                    \(EntryRanking.sqlOrderByClause(includeProjectPriority: true))\(limitClause)
                    """
                var arguments: StatementArguments = [
                    currentProjectId,
                    currentProjectId,
                    defaultProjectId,
                    normalizedTag.lowercased(),
                    Date().timeIntervalSince1970,
                ]
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

        return try search(
            query: query,
            projectIds: [currentProjectId, defaultProjectId],
            currentProjectId: currentProjectId,
            tag: normalizedTag,
            limit: limit
        )
    }

    /// Full-text search across title and content across all projects.
    func searchAll(
        query: String,
        tag: String? = nil,
        excludeArchivedProjects: Bool = true,
        limit: Int? = nil
    ) throws -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTag = Self.normalizedTag(tag)
        let archiveClause = excludeArchivedProjects
            ? "\n  AND entries.project_id IN (SELECT id FROM projects WHERE deleted_at IS NULL AND is_archived = 0)"
            : ""
        let limitClause = (limit.map { $0 > 0 } == true) ? "\nLIMIT ?" : ""

        guard !trimmed.isEmpty else {
            guard let normalizedTag else {
                return try fetchAll(excludeArchivedProjects: excludeArchivedProjects, limit: limit)
            }
            return try dbQueue.read { db in
                let sql = """
                    SELECT entries.*
                    FROM entries
                    WHERE entries.deleted_at IS NULL\(archiveClause)
                      AND EXISTS (
                          SELECT 1 FROM entry_tags
                          WHERE entry_tags.entry_id = entries.id AND entry_tags.tag_lower = ?
                      )
                    \(EntryRanking.sqlOrderByClause(includeProjectPriority: false))\(limitClause)
                    """
                var arguments: StatementArguments = [
                    normalizedTag.lowercased(),
                    Date().timeIntervalSince1970,
                ]
                if let limit, limit > 0 {
                    arguments += [limit]
                }
                return try Entry.fetchAll(db, sql: sql, arguments: arguments)
            }
        }

        return try dbQueue.read { db in
            let queryPredicate = Self.makeSearchPredicate(from: trimmed)
            let tagClause = normalizedTag != nil
                ? "\n  AND EXISTS (SELECT 1 FROM entry_tags WHERE entry_tags.entry_id = entries.id AND entry_tags.tag_lower = ?)"
                : ""
            let sql = """
                SELECT entries.*
                FROM entries
                WHERE entries.deleted_at IS NULL\(archiveClause)\(tagClause)
                  AND (\(queryPredicate.sql))
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: false))\(limitClause)
                """
            var arguments = StatementArguments()
            if let normalizedTag {
                arguments += [normalizedTag.lowercased()]
            }
            arguments += queryPredicate.arguments
            arguments += [Date().timeIntervalSince1970]
            if let limit, limit > 0 {
                arguments += [limit]
            }
            return try Entry.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Full-text search across title and content for arbitrary project IDs.
    func search(
        query: String,
        projectIds: [String],
        currentProjectId: String? = nil,
        tag: String? = nil,
        limit: Int? = nil
    ) throws -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = projectIds.uniqued()
        let normalizedTag = Self.normalizedTag(tag)
        let limitClause = (limit.map { $0 > 0 } == true) ? "\nLIMIT ?" : ""

        guard !ids.isEmpty else {
            return []
        }

        guard !trimmed.isEmpty else {
            guard let normalizedTag else {
                return try fetchByProjects(ids, limit: limit)
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
                      AND EXISTS (
                          SELECT 1 FROM entry_tags
                          WHERE entry_tags.entry_id = entries.id AND entry_tags.tag_lower = ?
                      )
                    \(EntryRanking.sqlOrderByClause(includeProjectPriority: currentProjectId != nil))\(limitClause)
                    """
                var arguments: StatementArguments = [currentProjectId, currentProjectId]
                arguments += StatementArguments(ids)
                arguments += [normalizedTag.lowercased(), Date().timeIntervalSince1970]
                if let limit, limit > 0 {
                    arguments += [limit]
                }
                return try Entry.fetchAll(db, sql: sql, arguments: arguments)
            }
        }

        return try dbQueue.read { db in
            let queryPredicate = Self.makeSearchPredicate(from: trimmed)
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let tagClause = normalizedTag != nil
                ? "\n  AND EXISTS (SELECT 1 FROM entry_tags WHERE entry_tags.entry_id = entries.id AND entry_tags.tag_lower = ?)"
                : ""
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
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: currentProjectId != nil))\(limitClause)
                """
            var arguments: StatementArguments = [currentProjectId, currentProjectId]
            arguments += StatementArguments(ids)
            if let normalizedTag {
                arguments += [normalizedTag.lowercased()]
            }
            arguments += queryPredicate.arguments
            arguments += [Date().timeIntervalSince1970] // pp_frecency's `now`
            if let limit, limit > 0 {
                arguments += [limit]
            }
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
    func entryCountByProject(excludeArchivedProjects: Bool = false) throws -> [String: Int] {
        try dbQueue.read { db in
            let archiveClause = excludeArchivedProjects
                ? " AND project_id IN (SELECT id FROM projects WHERE deleted_at IS NULL AND is_archived = 0)"
                : ""
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT project_id, COUNT(*) AS count FROM entries WHERE deleted_at IS NULL\(archiveClause) GROUP BY project_id"
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
            try Self.incrementLocalMutationSeq(in: db, now: now)
            return entry
        }
    }

    // MARK: - Write

    /// Create a new entry and record its initial v1 version snapshot.
    func create(_ entry: Entry, changeNote: String = "初始版本") throws {
        try dbQueue.write { db in
            var entryToSave = entry
            entryToSave.deletedAt = nil
            entryToSave.tags = Entry.normalizeTags(entry.tags)
            try entryToSave.save(db)
            try Self.syncTagsIndex(entryId: entryToSave.id, tags: entryToSave.tags, in: db)
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
            try Self.incrementLocalMutationSeq(in: db, now: entryToSave.updatedAt)
        }
        PPLogger.entry.debug("Entry created: \(entry.id)")
    }

    /// Update an existing entry. Automatically records a new `EntryVersion` if `recordVersion` is true and title or content changed.
    func update(_ entry: Entry, changeNote: String? = nil, recordVersion: Bool = true) throws {
        var updated = entry
        let now = Date()
        updated.updatedAt = now
        updated.tags = Entry.normalizeTags(entry.tags)
        try dbQueue.write { db in
            let previous = try Entry.fetchOne(db, key: entry.id)
            try updated.update(db)
            try Self.syncTagsIndex(entryId: updated.id, tags: updated.tags, in: db)
            try Self.incrementLocalMutationSeq(in: db, now: now)

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

    /// Atomically update only user-editable fields on the latest persisted row,
    /// preserving execution stats (`useCount`, `lastUsedAt`), `sortOrder`, `createdAt`, `deletedAt`, and `sourceEntryId`.
    /// Returns `.deletedOrMissing` if the row no longer exists or was soft-deleted (locally or via sync).
    func updateEditableFields(
        id: String,
        title: String,
        content: String,
        type: String,
        projectId: String,
        tags: [String],
        isPinned: Bool,
        isCompleted: Bool,
        changeNote: String? = nil,
        recordVersion: Bool = true
    ) throws -> EditableFieldsUpdateResult {
        try dbQueue.write { db in
            guard let previous = try Entry.fetchOne(db, key: id), previous.deletedAt == nil else {
                return .deletedOrMissing
            }
            if projectId != previous.projectId {
                guard let targetProject = try Project.fetchOne(db, key: projectId),
                      targetProject.deletedAt == nil else {
                    throw RepositoryError.notFound("Project \(projectId)")
                }
            }

            let now = Date()
            var updated = previous
            updated.title = title
            updated.content = content
            updated.type = Constants.EntryType.resolve(type).rawValue
            updated.projectId = projectId
            updated.tags = Entry.normalizeTags(tags)
            updated.isPinned = isPinned
            updated.isCompleted = isCompleted
            updated.updatedAt = now

            try updated.update(db)
            try Self.syncTagsIndex(entryId: updated.id, tags: updated.tags, in: db)
            try Self.incrementLocalMutationSeq(in: db, now: now)

            if recordVersion && (previous.title != updated.title || previous.content != updated.content) {
                let existingMaxVersion = try Int.fetchOne(
                    db,
                    sql: "SELECT MAX(version_number) FROM entry_versions WHERE entry_id = ?",
                    arguments: [updated.id]
                )
                if existingMaxVersion == nil {
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
                let nextVersionNumber = (existingMaxVersion ?? 1) + 1
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

            return .updated(updated)
        }
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
            try Self.syncTagsIndex(entryId: cloned.id, tags: cloned.tags, in: db)

            let initialVersion = EntryVersion(
                entryId: cloned.id,
                versionNumber: 1,
                title: cloned.title,
                content: cloned.content,
                changeNote: "克隆自「\(source.title)」",
                createdAt: now
            )
            try initialVersion.insert(db)
            try Self.incrementLocalMutationSeq(in: db, now: now)
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
            try Self.incrementLocalMutationSeq(in: db, now: now)
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
            if count > 0 {
                try Self.recordUserDeletes(count: count, in: db, now: now)
                try Self.incrementLocalMutationSeq(in: db, now: now)
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
            let count = db.changesCount
            if count > 0 {
                try Self.incrementLocalMutationSeq(in: db, now: now)
            }
            return count
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
            try Self.recordUserDeletes(count: 1, in: db, now: now)
            try Self.incrementLocalMutationSeq(in: db, now: now)
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
            try Self.markUsageDirty(in: db, now: now)
        }
        PPLogger.entry.debug("Execution recorded for entry: \(id)")
    }

    static func syncTagsIndex(entryId: String, tags: [String], in db: Database) throws {
        try db.execute(sql: "DELETE FROM entry_tags WHERE entry_id = ?", arguments: [entryId])
        var seen = Set<String>()
        for raw in tags {
            let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !lower.isEmpty, seen.insert(lower).inserted else { continue }
            try db.execute(
                sql: "INSERT OR IGNORE INTO entry_tags (entry_id, tag_lower) VALUES (?, ?)",
                arguments: [entryId, lower]
            )
        }
    }

    static func incrementLocalMutationSeq(in db: Database, now: Date = Date()) throws {
        let currentRaw = try String.fetchOne(
            db,
            sql: "SELECT value FROM sync_metadata WHERE key = 'local_mutation_seq'"
        )
        let current = currentRaw.flatMap(Int.init) ?? 0
        try db.execute(
            sql: "INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) VALUES ('local_mutation_seq', ?, ?)",
            arguments: [String(current + 1), now]
        )
    }

    static func markUsageDirty(in db: Database, now: Date = Date()) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) VALUES ('usage_dirty', '1', ?)",
            arguments: [now]
        )
    }

    private static func recordUserDeletes(count: Int, in db: Database, now: Date = Date()) throws {
        guard count > 0 else { return }
        let currentRaw = try String.fetchOne(
            db,
            sql: "SELECT value FROM sync_metadata WHERE key = 'pending_user_delete_count'"
        )
        let current = currentRaw.flatMap(Int.init) ?? 0
        let nextCount = current + count
        try db.execute(
            sql: "INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) VALUES ('pending_user_delete_count', ?, ?)",
            arguments: [String(nextCount), now]
        )
        if count >= 3 || nextCount >= 3 {
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) VALUES ('pending_allow_mass_delete', '1', ?)",
                arguments: [now]
            )
        }
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
