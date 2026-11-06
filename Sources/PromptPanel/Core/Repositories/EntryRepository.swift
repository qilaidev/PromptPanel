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
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let sql = """
                SELECT entries.*
                FROM entries
                WHERE entries.project_id IN (\(placeholders))
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: false))
                """
            var arguments = StatementArguments(ids)
            arguments += [Date()] // pp_frecency's `now`, appended after the WHERE binds
            return try Entry.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    /// Fetch all entries for management views.
    func fetchAll() throws -> [Entry] {
        try dbQueue.read { db in
            let sql = """
                SELECT entries.*
                FROM entries
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: false))
                """
            return try Entry.fetchAll(db, sql: sql, arguments: [Date()])
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
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: true))
                """
            let rows = try Row.fetchAll(
                db,
                sql: sql,
                arguments: [currentProjectId, currentProjectId, defaultProjectId, Date()]
            )
            return try rows.map { try Entry(row: $0) }
        }
    }

    /// Full-text search across title and content, limited to specific projects.
    func search(
        query: String,
        currentProjectId: String,
        defaultProjectId: String,
        tag: String? = nil
    ) throws -> [Entry] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            let entries = try fetchMixed(currentProjectId: currentProjectId, defaultProjectId: defaultProjectId)
            return Self.applyTagFilter(entries, tag: tag)
        }

        return try search(
            query: query,
            projectIds: [currentProjectId, defaultProjectId],
            currentProjectId: currentProjectId,
            tag: tag
        )
    }

    /// Full-text search across title and content across all projects.
    func searchAll(query: String, tag: String? = nil) throws -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let entries = try fetchAll()
            return Self.applyTagFilter(entries, tag: tag)
        }

        return try dbQueue.read { db in
            let tokens = Self.searchTokens(from: trimmed)
            let escapedQuery = Self.makeFTS5PrefixQuery(fromTokens: tokens)
            let substringClause = Self.makeSubstringWhereClause(tokenCount: tokens.count)
            let limitClause = tag == nil ? "\nLIMIT 100" : ""
            let sql = """
                SELECT entries.*
                FROM entries
                WHERE (
                    entries.rowid IN (
                        SELECT rowid FROM entries_fts WHERE entries_fts MATCH ?
                    )
                    OR (\(substringClause))
                )
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: false))\(limitClause)
                """
            var arguments: StatementArguments = [escapedQuery]
            for token in tokens {
                arguments += [token, token, token]
            }
            arguments += [Date()]
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            let entries = try rows.map { try Entry(row: $0) }
            if let tag {
                return Array(Self.applyTagFilter(entries, tag: tag).prefix(100))
            }
            return entries
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

        guard !trimmed.isEmpty else {
            let entries = try fetchByProjects(ids)
            return Self.applyTagFilter(entries, tag: tag)
        }

        guard !ids.isEmpty else {
            return []
        }

        return try dbQueue.read { db in
            let tokens = Self.searchTokens(from: trimmed)
            let escapedQuery = Self.makeFTS5PrefixQuery(fromTokens: tokens)
            let substringClause = Self.makeSubstringWhereClause(tokenCount: tokens.count)
            let placeholders = ids.map { _ in "?" }.joined(separator: ", ")
            let limitClause = tag == nil ? "\nLIMIT 100" : ""
            let sql = """
                SELECT entries.*,
                       CASE
                           WHEN ? IS NOT NULL AND entries.project_id = ? THEN 0
                           ELSE 1
                       END AS project_priority
                FROM entries
                WHERE entries.project_id IN (\(placeholders))
                  AND (
                      entries.rowid IN (
                          SELECT rowid FROM entries_fts WHERE entries_fts MATCH ?
                      )
                      OR (\(substringClause))
                  )
                \(EntryRanking.sqlOrderByClause(includeProjectPriority: currentProjectId != nil))\(limitClause)
                """
            var arguments: StatementArguments = [currentProjectId, currentProjectId]
            arguments += StatementArguments(ids)
            arguments += [escapedQuery]
            for token in tokens {
                arguments += [token, token, token]
            }
            arguments += [Date()] // pp_frecency's `now`
            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            let entries = try rows.map { try Entry(row: $0) }
            if let tag {
                return Array(Self.applyTagFilter(entries, tag: tag).prefix(100))
            }
            return entries
        }
    }

    private static func applyTagFilter(_ entries: [Entry], tag: String?) -> [Entry] {
        guard let tag, !tag.isEmpty else {
            return entries
        }
        return entries.filter { $0.tags.contains(tag) }
    }

    private static func searchTokens(from rawQuery: String) -> [String] {
        rawQuery
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func makeFTS5PrefixQuery(from rawQuery: String) -> String {
        makeFTS5PrefixQuery(fromTokens: searchTokens(from: rawQuery))
    }

    private static func makeFTS5PrefixQuery(fromTokens tokens: [String]) -> String {
        tokens
            .map { token in
                // FTS5 uses double quotes for phrase literals; escape embedded quotes so
                // searches like foo"bar do not fail the whole query.
                let escapedToken = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escapedToken)\"*"
            }
            .joined(separator: " ")
    }

    /// Builds a conjunction of case-insensitive substring checks across `title`, `content`,
    /// and `tags` so mid-token CJK substrings (which FTS5 `unicode61` prefix matching cannot
    /// split) and tag keywords are always recalled.
    private static func makeSubstringWhereClause(tokenCount: Int) -> String {
        guard tokenCount > 0 else {
            return "0"
        }
        return Array(
            repeating: "(INSTR(LOWER(entries.title), LOWER(?)) > 0 OR INSTR(LOWER(entries.content), LOWER(?)) > 0 OR INSTR(LOWER(entries.tags), LOWER(?)) > 0)",
            count: tokenCount
        ).joined(separator: " AND ")
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
        PPLogger.entry.debug("Entry created: \(entry.id)")
    }

    /// Update an existing entry.
    func update(_ entry: Entry) throws {
        var updated = entry
        updated.updatedAt = Date()
        try dbQueue.write { db in
            try updated.update(db)
        }
        PPLogger.entry.debug("Entry updated: \(entry.id)")
    }

    /// Delete an entry by ID.
    func delete(id: String) throws {
        try dbQueue.write { db in
            guard let entry = try Entry.fetchOne(db, key: id) else {
                throw RepositoryError.notFound("Entry \(id)")
            }
            try entry.delete(db)
        }
        PPLogger.entry.debug("Entry deleted: \(id)")
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
