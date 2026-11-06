import Foundation
import GRDB

/// Represents a project that organizes entries by work context.
struct Project: Identifiable, Codable, Equatable {
    /// Unique identifier (UUID string).
    var id: String
    /// Display name of the project.
    var name: String
    /// Whether this is the built-in default project ("通用项目") that cannot be deleted.
    var isDefault: Bool
    /// Creation timestamp.
    var createdAt: Date
    /// Last update timestamp.
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - GRDB Conformance

extension Project: FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"

    enum Columns: String, ColumnExpression {
        case id
        case name
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
