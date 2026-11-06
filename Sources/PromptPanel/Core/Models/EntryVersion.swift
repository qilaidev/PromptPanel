import Foundation
import GRDB

/// Represents an immutable historical snapshot of an `Entry` for version tracking and rollback.
struct EntryVersion: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var entryId: String
    var versionNumber: Int
    var title: String
    var content: String
    var changeNote: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        entryId: String,
        versionNumber: Int,
        title: String,
        content: String,
        changeNote: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.entryId = entryId
        self.versionNumber = versionNumber
        self.title = title
        self.content = content
        self.changeNote = changeNote
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case versionNumber = "version_number"
        case title
        case content
        case changeNote = "change_note"
        case createdAt = "created_at"
    }

    private enum CamelCodingKeys: String, CodingKey {
        case entryId
        case versionNumber
        case changeNote
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let camelContainer = try decoder.container(keyedBy: CamelCodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        if let eid = try? container.decodeIfPresent(String.self, forKey: .entryId) {
            self.entryId = eid
        } else {
            self.entryId = try camelContainer.decode(String.self, forKey: .entryId)
        }
        self.versionNumber = (try? container.decodeIfPresent(Int.self, forKey: .versionNumber))
            ?? (try? camelContainer.decodeIfPresent(Int.self, forKey: .versionNumber))
            ?? 1
        self.title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? ""
        self.content = (try? container.decodeIfPresent(String.self, forKey: .content)) ?? ""
        self.changeNote = (try? container.decodeIfPresent(String.self, forKey: .changeNote))
            ?? (try? camelContainer.decodeIfPresent(String.self, forKey: .changeNote))
        if let createdAt = try? container.decodeIfPresent(Date.self, forKey: .createdAt) {
            self.createdAt = createdAt
        } else {
            self.createdAt = try camelContainer.decode(Date.self, forKey: .createdAt)
        }
    }
}

// MARK: - GRDB Conformance

extension EntryVersion: FetchableRecord, PersistableRecord {
    static let databaseTableName = "entry_versions"

    enum Columns: String, ColumnExpression {
        case id
        case entryId = "entry_id"
        case versionNumber = "version_number"
        case title
        case content
        case changeNote = "change_note"
        case createdAt = "created_at"
    }
}
