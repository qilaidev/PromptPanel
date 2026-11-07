import Foundation
import GRDB

/// Data access layer for projects / categories / inbox groups.
final class ProjectRepository: @unchecked Sendable {

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func writeInTransaction<T>(_ updates: (Database) throws -> T) throws -> T {
        try dbQueue.write(updates)
    }

    // MARK: - Read

    /// Fetch all non-deleted projects, ordered by:
    /// 1. Built-in Inbox ("速记与待办")
    /// 2. Built-in Default ("通用项目")
    /// 3. Reusable Categories (`group_kind = 'category'`)
    /// 4. Active Projects (`is_archived = 0`)
    /// 5. Archived Projects (`is_archived = 1`)
    /// 6. Name ascending
    func fetchAll(includeArchived: Bool = true) throws -> [Project] {
        try dbQueue.read { db in
            let archiveClause = includeArchived ? "" : "AND is_archived = 0"
            let sql = """
                SELECT *
                FROM projects
                WHERE deleted_at IS NULL
                \(archiveClause)
                ORDER BY
                    CASE
                        WHEN group_kind = 'inbox' THEN 0
                        WHEN is_default = 1 THEN 1
                        WHEN group_kind = 'category' THEN 2
                        ELSE 3
                    END ASC,
                    is_archived ASC,
                    name COLLATE NOCASE ASC
                """
            return try Project.fetchAll(db, sql: sql)
        }
    }

    /// Fetch a project by ID (ignoring soft-deleted ones).
    func fetchById(_ id: String) throws -> Project? {
        try dbQueue.read { db in
            try Project
                .filter(Project.Columns.id == id && Project.Columns.deletedAt == nil)
                .fetchOne(db)
        }
    }

    /// Fetch the default project ("通用项目").
    func fetchDefault() throws -> Project? {
        try dbQueue.read { db in
            try Project
                .filter(Project.Columns.isDefault == true && Project.Columns.deletedAt == nil)
                .fetchOne(db)
        }
    }

    /// Fetch the built-in Inbox group ("速记与待办").
    func fetchInbox() throws -> Project? {
        try dbQueue.read { db in
            try Project
                .filter(Project.Columns.groupKind == Project.GroupKind.inbox.rawValue && Project.Columns.deletedAt == nil)
                .fetchOne(db)
        }
    }

    /// Count active entries belonging to a project.
    func entryCount(forProjectId projectId: String) throws -> Int {
        try dbQueue.read { db in
            try Entry
                .filter(Entry.Columns.projectId == projectId && Entry.Columns.deletedAt == nil)
                .fetchCount(db)
        }
    }

    // MARK: - Write

    /// Create a new project or category.
    func create(_ project: Project) throws {
        try dbQueue.write { db in
            var projectToSave = project
            projectToSave.deletedAt = nil
            try projectToSave.save(db)
        }
        PPLogger.project.info("Project created: \(project.id) kind=\(project.groupKind.rawValue)")
    }

    /// Update an existing project.
    func update(_ project: Project) throws {
        var updated = project
        updated.updatedAt = Date()
        try dbQueue.write { db in
            try updated.update(db)
        }
        PPLogger.project.info("Project updated: \(project.id)")
    }

    /// Rename a project and optionally update its groupKind.
    func rename(id: String, newName: String, groupKind: Project.GroupKind? = nil) throws {
        try dbQueue.write { db in
            guard var project = try Project.fetchOne(db, key: id), project.deletedAt == nil else {
                throw RepositoryError.notFound("Project \(id)")
            }
            project.name = newName
            if let groupKind, !project.isSystemProtected {
                project.groupKind = groupKind
            }
            project.updatedAt = Date()
            try project.update(db)
        }
        PPLogger.project.info("Project renamed: \(id)")
    }

    /// Archive or unarchive a project.
    func setArchived(id: String, isArchived: Bool) throws {
        try dbQueue.write { db in
            guard var project = try Project.fetchOne(db, key: id), project.deletedAt == nil else {
                throw RepositoryError.notFound("Project \(id)")
            }
            guard !project.isSystemProtected else {
                throw RepositoryError.cannotArchiveSystemProject
            }
            project.isArchived = isArchived
            project.updatedAt = Date()
            try project.update(db)
        }
        PPLogger.project.info("Project archive state updated: \(id) archived=\(isArchived)")
    }

    /// Switch a group's role between `.category` ("常用类型") and `.project` ("具体项目").
    func setGroupKind(id: String, groupKind: Project.GroupKind) throws {
        try dbQueue.write { db in
            guard var project = try Project.fetchOne(db, key: id), project.deletedAt == nil else {
                throw RepositoryError.notFound("Project \(id)")
            }
            guard !project.isSystemProtected else {
                throw RepositoryError.cannotModifySystemProjectKind
            }
            project.groupKind = groupKind
            if groupKind == .category {
                project.isArchived = false
            }
            project.updatedAt = Date()
            try project.update(db)
        }
        PPLogger.project.info("Project group kind updated: \(id) kind=\(groupKind.rawValue)")
    }

    /// Soft-delete a project so cloud sync propagates a tombstone. Fails if the project is system-protected or still has active entries.
    func delete(id: String) throws {
        try dbQueue.write { db in
            guard var project = try Project.fetchOne(db, key: id), project.deletedAt == nil else {
                throw RepositoryError.notFound("Project \(id)")
            }
            guard !project.isSystemProtected else {
                throw RepositoryError.cannotDeleteDefault
            }
            let count = try Entry
                .filter(Entry.Columns.projectId == id && Entry.Columns.deletedAt == nil)
                .fetchCount(db)
            guard count == 0 else {
                throw RepositoryError.projectNotEmpty(count: count)
            }
            let now = Date()
            project.deletedAt = now
            project.updatedAt = now
            try project.update(db)
        }
        PPLogger.project.info("Project soft-deleted: \(id)")
    }

    /// Migrate all active entries from one project to another, then soft-delete the source project.
    func migrateAndDelete(fromId: String, toId: String) throws {
        try dbQueue.write { db in
            guard fromId != toId else {
                throw RepositoryError.invalidMigrationTarget
            }
            guard var source = try Project.fetchOne(db, key: fromId), source.deletedAt == nil else {
                throw RepositoryError.notFound("Source project \(fromId)")
            }
            guard !source.isSystemProtected else {
                throw RepositoryError.cannotDeleteDefault
            }
            guard let target = try Project.fetchOne(db, key: toId), target.deletedAt == nil else {
                throw RepositoryError.notFound("Target project \(toId)")
            }

            // Migrate active entries
            let now = Date()
            try db.execute(
                sql: "UPDATE entries SET project_id = ?, updated_at = ? WHERE project_id = ? AND deleted_at IS NULL",
                arguments: [target.id, now, fromId]
            )

            // Soft-delete source project so tombstones sync cleanly across devices
            source.deletedAt = now
            source.updatedAt = now
            try source.update(db)
        }
        PPLogger.project.info("Migrated entries from \(fromId) to \(toId) and soft-deleted source project")
    }
}

// MARK: - Repository Errors

enum RepositoryError: LocalizedError {
    case notFound(String)
    case cannotDeleteDefault
    case cannotArchiveSystemProject
    case cannotModifySystemProjectKind
    case projectNotEmpty(count: Int)
    case invalidMigrationTarget

    var errorDescription: String? {
        switch self {
        case .notFound(let entity):
            return "\(entity) not found"
        case .cannotDeleteDefault:
            return "Cannot delete a system-protected group"
        case .cannotArchiveSystemProject:
            return "System-protected groups cannot be archived"
        case .cannotModifySystemProjectKind:
            return "System-protected group kinds cannot be changed"
        case .projectNotEmpty(let count):
            return "Project still has \(count) entries. Migrate or delete them first."
        case .invalidMigrationTarget:
            return "Migration target must be different from the source project."
        }
    }
}
