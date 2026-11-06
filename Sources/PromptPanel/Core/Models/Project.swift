import Foundation
import GRDB

/// Represents a workspace container that organizes entries by role:
/// - `.inbox`: Built-in quick capture for todos and temporary scratchpad notes ("速记与待办")
/// - `.category`: Long-lived reusable domain categories ("常用类型", e.g. 开发类, 视频制作)
/// - `.project`: Project-specific context ("具体项目"), which can be archived when completed
struct Project: Identifiable, Codable, Equatable {
    enum GroupKind: String, Codable, CaseIterable, Identifiable {
        case inbox = "inbox"
        case category = "category"
        case project = "project"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .inbox: return "速记与待办"
            case .category: return "常用类型"
            case .project: return "项目"
            }
        }

        var sectionTitle: String {
            switch self {
            case .inbox: return "速记与待办"
            case .category: return "常用类型"
            case .project: return "项目"
            }
        }

        var defaultIconName: String {
            switch self {
            case .inbox: return "tray.fill"
            case .category: return "square.grid.2x2"
            case .project: return "folder"
            }
        }

        static func resolve(_ rawValue: String?, isDefault: Bool = false) -> GroupKind {
            if let rawValue, let parsed = GroupKind(rawValue: rawValue) {
                return parsed
            }
            return isDefault ? .category : .project
        }
    }

    /// Unique identifier (UUID string).
    var id: String
    /// Display name of the project/category.
    var name: String
    /// Whether this is the built-in default project ("通用项目") that cannot be deleted.
    var isDefault: Bool
    /// Role marker distinguishing Inbox, Category (reusable type), and Project.
    var groupKind: GroupKind
    /// Whether this project is archived (hidden from quick panel switcher, kept in main library archive section).
    var isArchived: Bool
    /// Optional custom SF Symbol icon name.
    var iconName: String?
    /// Creation timestamp.
    var createdAt: Date
    /// Last update timestamp.
    var updatedAt: Date
    /// Soft-delete timestamp for cloud sync tombstones.
    var deletedAt: Date?

    /// Built-in system groups ("通用项目" and "速记与待办") cannot be deleted.
    var isSystemProtected: Bool {
        isDefault || groupKind == .inbox || id == Constants.inboxProjectId
    }

    var effectiveIconName: String {
        if let iconName, !iconName.isEmpty {
            return iconName
        }
        if isArchived {
            return "archivebox"
        }
        if isDefault {
            return "square.stack"
        }
        return groupKind.defaultIconName
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        isDefault: Bool = false,
        groupKind: GroupKind? = nil,
        isArchived: Bool = false,
        iconName: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.isDefault = isDefault
        self.groupKind = groupKind ?? (isDefault ? .category : .project)
        self.isArchived = isArchived
        self.iconName = iconName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isDefault = "is_default"
        case groupKind = "group_kind"
        case isArchived = "is_archived"
        case iconName = "icon_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    private enum CamelCodingKeys: String, CodingKey {
        case isDefault
        case groupKind
        case groupKindRaw
        case isArchived
        case iconName
        case createdAt
        case updatedAt
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let camelContainer = try decoder.container(keyedBy: CamelCodingKeys.self)
        let isDefault = (try? container.decodeIfPresent(Bool.self, forKey: .isDefault))
            ?? (try? camelContainer.decodeIfPresent(Bool.self, forKey: .isDefault))
            ?? false
        let rawKind = (try? container.decodeIfPresent(String.self, forKey: .groupKind))
            ?? (try? camelContainer.decodeIfPresent(String.self, forKey: .groupKindRaw))
            ?? (try? camelContainer.decodeIfPresent(String.self, forKey: .groupKind))
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.isDefault = isDefault
        self.groupKind = GroupKind.resolve(rawKind, isDefault: isDefault)
        self.isArchived = (try? container.decodeIfPresent(Bool.self, forKey: .isArchived))
            ?? (try? camelContainer.decodeIfPresent(Bool.self, forKey: .isArchived))
            ?? false
        self.iconName = (try? container.decodeIfPresent(String.self, forKey: .iconName))
            ?? (try? camelContainer.decodeIfPresent(String.self, forKey: .iconName))
        if let createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt) {
            self.createdAt = createdAt
        } else {
            self.createdAt = try camelContainer.decode(Date.self, forKey: .createdAt)
        }
        if let updatedAt = try? container.decodeIfPresent(Date.self, forKey: .updatedAt) {
            self.updatedAt = updatedAt
        } else {
            self.updatedAt = try camelContainer.decode(Date.self, forKey: .updatedAt)
        }
        self.deletedAt = (try? container.decodeIfPresent(Date.self, forKey: .deletedAt))
            ?? (try? camelContainer.decodeIfPresent(Date.self, forKey: .deletedAt))
    }
}

// MARK: - GRDB Conformance

extension Project: FetchableRecord, PersistableRecord {
    static let databaseTableName = "projects"

    enum Columns: String, ColumnExpression {
        case id
        case name
        case isDefault = "is_default"
        case groupKind = "group_kind"
        case isArchived = "is_archived"
        case iconName = "icon_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
    }

    init(row: Row) throws {
        let isDefault: Bool = row["is_default"] ?? false
        let rawKind: String? = row["group_kind"]
        self.id = row["id"]
        self.name = row["name"]
        self.isDefault = isDefault
        self.groupKind = GroupKind.resolve(rawKind, isDefault: isDefault)
        self.isArchived = row["is_archived"] ?? false
        self.iconName = row["icon_name"]
        self.createdAt = row["created_at"]
        self.updatedAt = row["updated_at"]
        self.deletedAt = row["deleted_at"]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["name"] = name
        container["is_default"] = isDefault
        container["group_kind"] = groupKind.rawValue
        container["is_archived"] = isArchived
        container["icon_name"] = iconName
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
        container["deleted_at"] = deletedAt
    }
}
