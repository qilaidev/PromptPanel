import Foundation
import GRDB

/// Data access layer for entries.
final class EntryRepository: @unchecked Sendable {

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
    func fetchByProjects(_ projectIds: [String]) throws -> [Entry] {
        let ids = projectIds.uniqued()
        guard !ids.isEmpty else {
            return []
        }

        return try dbQueue.read { db in
            try Entry
                .filter(ids.contains(Entry.Columns.projectId))
                .order(
                    Entry.Columns.isPinned.desc,
                    Entry.Columns.sortOrder.desc,
                    Entry.Columns.lastUsedAt.desc,
                    Entry.Columns.useCount.desc,
                    Entry.Columns.updatedAt.desc,
                    Entry.Columns.id.asc
                )
                .fetchAll(db)
        }
    }

    /// Fetch all entries for management views.
    func fetchAll() throws -> [Entry] {
        try dbQueue.read { db in
            try Entry
                .order(
                    Entry.Columns.isPinned.desc,
                    Entry.Columns.sortOrder.desc,
                    Entry.Columns.lastUsedAt.desc,
                    Entry.Columns.useCount.desc,
                    Entry.Columns.updatedAt.desc,
                    Entry.Columns.id.asc
                )
                .fetchAll(db)
        }
    }

    /// Fetch entries for the current project + default project, mixed and sorted per PRD.
    /// Current project entries rank above default project entries when all other sort keys are equal.
    func fetchMixed(currentProjectId: String, defaultProjectId: String) throws -> [Entry] {
        try dbQueue.read { db in
            // Fetch both sets
            let sql = """
                SELECT entries.*,
                       CASE WHEN entries.project_id = ? THEN 0 ELSE 1 END AS project_priority
                FROM entries
                WHERE entries.project_id IN (?, ?)
                ORDER BY
                    entries.is_pinned DESC,
                    entries.sort_order DESC,
                    entries.last_used_at DESC,
                    entries.use_count DESC,
                    project_priority ASC,
                    entries.updated_at DESC,
                    entries.id ASC
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [currentProjectId, currentProjectId, defaultProjectId])
            return try rows.map { try Entry(row: $0) }
        }
    }

    /// Full-text search across title and content, limited to specific projects.
    func search(query: String, currentProjectId: String, defaultProjectId: String) throws -> [Entry] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return try fetchMixed(currentProjectId: currentProjectId, defaultProjectId: defaultProjectId)
        }

        return try search(query: query, projectIds: [currentProjectId, defaultProjectId], currentProjectId: currentProjectId)
    }

    /// Full-text search across title and content for arbitrary project IDs.
    func search(query: String, projectIds: [String], currentProjectId: String? = nil) throws -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = projectIds.uniqued()

        guard !trimmed.isEmpty else {
            return try fetchByProjects(ids)
        }

        guard !ids.isEmpty else {
            return []
        }

        return try dbQueue.read { db in
            let escapedQuery = Self.makeFTS5PrefixQuery(from: trimmed)

            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let orderByProjectPriority = currentProjectId == nil ? "" : ", project_priority ASC"
            let sql = """
                SELECT entries.*,
                       CASE
                           WHEN ? IS NOT NULL AND entries.project_id = ? THEN 0
                           ELSE 1
                       END AS project_priority
                FROM entries
                JOIN entries_fts ON entries_fts.rowid = entries.rowid
                WHERE entries_fts MATCH ?
                  AND entries.project_id IN (\(placeholders))
                ORDER BY
                    entries.is_pinned DESC,
                    entries.sort_order DESC,
                    entries.last_used_at DESC,
                    entries.use_count DESC\(orderByProjectPriority),
                    entries.updated_at DESC,
                    entries.id ASC
                LIMIT 100
                """
            let rawArguments: [Any] = [currentProjectId as Any, currentProjectId as Any, escapedQuery as Any] + ids.map { $0 as Any }
            let arguments = StatementArguments(rawArguments)!
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            return try rows.map { try Entry(row: $0) }
        }
    }

    private static func makeFTS5PrefixQuery(from rawQuery: String) -> String {
        rawQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { token in
                // FTS5 uses double quotes for phrase literals; escape embedded quotes so
                // searches like foo"bar do not fail the whole query.
                let escapedToken = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escapedToken)\"*"
            }
            .joined(separator: " ")
    }

    /// Fetch a single entry by ID.
    func fetchById(_ id: String) throws -> Entry? {
        try dbQueue.read { db in
            try Entry.fetchOne(db, key: id)
        }
    }

    /// Total entry count per project. Projects with zero entries are included as 0.
    func entryCountByProject() throws -> [String: Int] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT project_id, COUNT(*) AS count FROM entries GROUP BY project_id"
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

    // MARK: - Write

    /// Create a new entry.
    func create(_ entry: Entry) throws {
        try dbQueue.write { db in
            try entry.insert(db)
        }
        PPLogger.entry.info("Entry created: \(entry.id)")
    }

    /// Update an existing entry.
    func update(_ entry: Entry) throws {
        var updated = entry
        updated.updatedAt = Date()
        try dbQueue.write { db in
            try updated.update(db)
        }
        PPLogger.entry.info("Entry updated: \(entry.id)")
    }

    /// Delete an entry by ID.
    func delete(id: String) throws {
        try dbQueue.write { db in
            guard let entry = try Entry.fetchOne(db, key: id) else {
                throw RepositoryError.notFound("Entry \(id)")
            }
            try entry.delete(db)
        }
        PPLogger.entry.info("Entry deleted: \(id)")
    }

    /// Record an execution: increment use_count and set last_used_at.
    func recordExecution(id: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE entries
                    SET use_count = use_count + 1,
                        last_used_at = ?,
                        updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [Date(), Date(), id]
            )
            try Self.requireChangedRow(in: db, entity: "Entry \(id)")
        }
        PPLogger.entry.info("Execution recorded for entry: \(id)")
    }

    /// Update the sort order for an entry.
    func updateSortOrder(id: String, sortOrder: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE entries SET sort_order = ?, updated_at = ? WHERE id = ?",
                arguments: [sortOrder, Date(), id]
            )
            try Self.requireChangedRow(in: db, entity: "Entry \(id)")
        }
    }

    /// Toggle pin status.
    func togglePin(id: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE entries SET is_pinned = NOT is_pinned, updated_at = ? WHERE id = ?",
                arguments: [Date(), id]
            )
            try Self.requireChangedRow(in: db, entity: "Entry \(id)")
        }
    }

    /// Move an entry to a different project.
    func moveToProject(entryId: String, projectId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE entries SET project_id = ?, updated_at = ? WHERE id = ?",
                arguments: [projectId, Date(), entryId]
            )
            try Self.requireChangedRow(in: db, entity: "Entry \(entryId)")
        }
        PPLogger.entry.info("Entry \(entryId) moved to project \(projectId)")
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
