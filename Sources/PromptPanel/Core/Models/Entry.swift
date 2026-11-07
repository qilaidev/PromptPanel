import Foundation
import GRDB

/// Represents an entry (prompt, snippet, todo, or scratchpad note) that can be quickly executed via the panel.
struct Entry: Identifiable, Codable, Equatable {
    var id: String
    var projectId: String
    var title: String
    var content: String {
        didSet {
            if content != oldValue {
                previewLine = Entry.makePreviewLine(from: content)
            }
        }
    }
    var type: String
    var isPinned: Bool
    var isCompleted: Bool
    var sortOrder: Int
    var useCount: Int
    var lastUsedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?
    var sourceEntryId: String?
    /// Free-form short labels. Stored as JSON array of strings in the `tags` column.
    var tags: [String]
    /// Cached single-line preview of `content` for list rows (O(1) read during SwiftUI diffing/scrolling).
    private(set) var previewLine: String

    init(
        id: String = UUID().uuidString,
        projectId: String,
        title: String,
        content: String,
        type: String = Constants.EntryType.prompt.rawValue,
        isPinned: Bool = false,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        useCount: Int = 0,
        lastUsedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        sourceEntryId: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.content = content
        self.type = type
        self.isPinned = isPinned
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.useCount = useCount
        self.lastUsedAt = lastUsedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.sourceEntryId = sourceEntryId
        self.tags = Entry.normalizeTags(tags)
        self.previewLine = Entry.makePreviewLine(from: content)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case title
        case content
        case type
        case isPinned = "is_pinned"
        case isCompleted = "is_completed"
        case sortOrder = "sort_order"
        case useCount = "use_count"
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case sourceEntryId = "source_entry_id"
        case tags
    }

    private enum CamelCodingKeys: String, CodingKey {
        case projectId
        case isPinned
        case isCompleted
        case sortOrder
        case useCount
        case lastUsedAt
        case createdAt
        case updatedAt
        case deletedAt
        case sourceEntryId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let camelContainer = try decoder.container(keyedBy: CamelCodingKeys.self)
        let decodedContent = try container.decode(String.self, forKey: .content)
        self.id = try container.decode(String.self, forKey: .id)
        if let pid = try? container.decodeIfPresent(String.self, forKey: .projectId) {
            self.projectId = pid
        } else {
            self.projectId = try camelContainer.decode(String.self, forKey: .projectId)
        }
        self.title = try container.decode(String.self, forKey: .title)
        self.content = decodedContent
        self.type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? Constants.EntryType.prompt.rawValue
        self.isPinned = (try? container.decodeIfPresent(Bool.self, forKey: .isPinned))
            ?? (try? camelContainer.decodeIfPresent(Bool.self, forKey: .isPinned))
            ?? false
        self.isCompleted = (try? container.decodeIfPresent(Bool.self, forKey: .isCompleted))
            ?? (try? camelContainer.decodeIfPresent(Bool.self, forKey: .isCompleted))
            ?? false
        self.sortOrder = (try? container.decodeIfPresent(Int.self, forKey: .sortOrder))
            ?? (try? camelContainer.decodeIfPresent(Int.self, forKey: .sortOrder))
            ?? 0
        self.useCount = (try? container.decodeIfPresent(Int.self, forKey: .useCount))
            ?? (try? camelContainer.decodeIfPresent(Int.self, forKey: .useCount))
            ?? 0
        self.lastUsedAt = (try? container.decodeIfPresent(Date.self, forKey: .lastUsedAt))
            ?? (try? camelContainer.decodeIfPresent(Date.self, forKey: .lastUsedAt))
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
        self.sourceEntryId = (try? container.decodeIfPresent(String.self, forKey: .sourceEntryId))
            ?? (try? camelContainer.decodeIfPresent(String.self, forKey: .sourceEntryId))
        self.tags = Entry.normalizeTags((try? container.decode([String].self, forKey: .tags)) ?? [])
        self.previewLine = Entry.makePreviewLine(from: decodedContent)
    }

    /// How much of `content` a one-line preview is allowed to look at.
    /// Well past what fits in a single truncated row at any panel width.
    static let previewScanLimit = 240

    static func makePreviewLine(from content: String) -> String {
        var out = ""
        out.reserveCapacity(min(content.count, Entry.previewScanLimit))
        var pendingSpace = false
        for character in content.prefix(Entry.previewScanLimit) {
            if character.isWhitespace || character.isNewline {
                pendingSpace = !out.isEmpty
                continue
            }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(character)
        }
        return out
    }

    static func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in tags {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed.lowercased()).inserted {
                out.append(trimmed)
            }
        }
        return out
    }
}

// MARK: - GRDB Conformance (custom encoding so [String] <-> JSON in SQLite)

extension Entry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "entries"

    enum Columns: String, ColumnExpression {
        case id
        case projectId = "project_id"
        case title
        case content
        case type
        case isPinned = "is_pinned"
        case isCompleted = "is_completed"
        case sortOrder = "sort_order"
        case useCount = "use_count"
        case lastUsedAt = "last_used_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case deletedAt = "deleted_at"
        case sourceEntryId = "source_entry_id"
        case tags
    }

    init(row: Row) throws {
        let rowContent: String = row["content"]
        self.id = row["id"]
        self.projectId = row["project_id"]
        self.title = row["title"]
        self.content = rowContent
        self.type = row["type"]
        self.isPinned = row["is_pinned"]
        self.isCompleted = row["is_completed"] ?? false
        self.sortOrder = row["sort_order"]
        self.useCount = row["use_count"]
        self.lastUsedAt = row["last_used_at"]
        self.createdAt = row["created_at"]
        self.updatedAt = row["updated_at"]
        self.deletedAt = row["deleted_at"]
        self.sourceEntryId = row["source_entry_id"]
        self.tags = EntryTagsCodec.decode(row["tags"])
        self.previewLine = Entry.makePreviewLine(from: rowContent)
    }

    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["project_id"] = projectId
        container["title"] = title
        container["content"] = content
        container["type"] = type
        container["is_pinned"] = isPinned
        container["is_completed"] = isCompleted
        container["sort_order"] = sortOrder
        container["use_count"] = useCount
        container["last_used_at"] = lastUsedAt
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
        container["deleted_at"] = deletedAt
        container["source_entry_id"] = sourceEntryId
        container["tags"] = EntryTagsCodec.encode(tags)
    }
}

/// JSON <-> `[String]` codec for the `entries.tags` column.
/// Malformed JSON falls back to an empty list so a single bad row cannot crash the app.
enum EntryTagsCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    private static let lock = NSLock()

    static func encode(_ tags: [String]) -> String {
        let normalized = Entry.normalizeTags(tags)
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? encoder.encode(normalized),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    static func decode(_ raw: String?) -> [String] {
        guard let raw else {
            return []
        }
        if raw.isEmpty || raw == "[]" {
            return []
        }
        guard let data = raw.data(using: .utf8) else {
            return []
        }
        lock.lock()
        let decoded = try? decoder.decode([String].self, from: data)
        lock.unlock()
        guard let decoded else {
            return []
        }
        return Entry.normalizeTags(decoded)
    }
}
