import Foundation
import GRDB

/// Data access layer for projects.
final class ProjectRepository: @unchecked Sendable {

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func writeInTransaction<T>(_ updates: (Database) throws -> T) throws -> T {
        try dbQueue.write(updates)
    }

    // MARK: - Read

    /// Fetch all projects, ordered by: default project first, then by name.
    func fetchAll() throws -> [Project] {
        try dbQueue.read { db in
            try Project
                .order(
                    Project.Columns.isDefault.desc,
                    Project.Columns.name.asc
                )
                .fetchAll(db)
        }
    }

    /// Fetch a project by ID.
    func fetchById(_ id: String) throws -> Project? {
        try dbQueue.read { db in
            try Project.fetchOne(db, key: id)
        }
    }

    /// Fetch the default project ("通用项目").
    func fetchDefault() throws -> Project? {
        try dbQueue.read { db in
            try Project.filter(Project.Columns.isDefault == true).fetchOne(db)
        }
    }

    /// Count entries belonging to a project.
    func entryCount(forProjectId projectId: String) throws -> Int {
        try dbQueue.read { db in
            try Entry.filter(Entry.Columns.projectId == projectId).fetchCount(db)
        }
    }

    // MARK: - Write

    /// Create a new project.
    func create(_ project: Project) throws {
        try dbQueue.write { db in
            try project.insert(db)
        }
        PPLogger.project.info("Project created: \(project.id)")
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

    /// Rename a project.
    func rename(id: String, newName: String) throws {
        try dbQueue.write { db in
            guard var project = try Project.fetchOne(db, key: id) else {
                throw RepositoryError.notFound("Project \(id)")
            }
            project.name = newName
            project.updatedAt = Date()
            try project.update(db)
        }
        PPLogger.project.info("Project renamed: \(id)")
    }

    /// Delete a project. Fails if the project is the default project or still has entries.
    func delete(id: String) throws {
        try dbQueue.write { db in
            guard let project = try Project.fetchOne(db, key: id) else {
                throw RepositoryError.notFound("Project \(id)")
            }
            guard !project.isDefault else {
                throw RepositoryError.cannotDeleteDefault
            }
            let count = try Entry.filter(Entry.Columns.projectId == id).fetchCount(db)
            guard count == 0 else {
                throw RepositoryError.projectNotEmpty(count: count)
            }
            try project.delete(db)
        }
        PPLogger.project.info("Project deleted: \(id)")
    }

    /// Migrate all entries from one project to another, then delete the source project.
    func migrateAndDelete(fromId: String, toId: String) throws {
        try dbQueue.write { db in
            guard fromId != toId else {
                throw RepositoryError.invalidMigrationTarget
            }
            guard let source = try Project.fetchOne(db, key: fromId) else {
                throw RepositoryError.notFound("Source project \(fromId)")
            }
            guard !source.isDefault else {
                throw RepositoryError.cannotDeleteDefault
            }
            guard try Project.fetchOne(db, key: toId) != nil else {
                throw RepositoryError.notFound("Target project \(toId)")
            }

            // Migrate entries
            let now = Date()
            try db.execute(
                sql: "UPDATE entries SET project_id = ?, updated_at = ? WHERE project_id = ?",
                arguments: [toId, now, fromId]
            )

            // Delete source project
            try source.delete(db)
        }
        PPLogger.project.info("Migrated entries from \(fromId) to \(toId) and deleted source project")
    }
}

// MARK: - Repository Errors

enum RepositoryError: LocalizedError {
    case notFound(String)
    case cannotDeleteDefault
    case projectNotEmpty(count: Int)
    case invalidMigrationTarget

    var errorDescription: String? {
        switch self {
        case .notFound(let entity):
            return "\(entity) not found"
        case .cannotDeleteDefault:
            return "Cannot delete the default project"
        case .projectNotEmpty(let count):
            return "Project still has \(count) entries. Migrate or delete them first."
        case .invalidMigrationTarget:
            return "Migration target must be different from the source project."
        }
    }
}
