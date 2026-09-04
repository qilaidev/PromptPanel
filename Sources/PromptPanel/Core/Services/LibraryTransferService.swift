import Foundation
import GRDB

struct LibraryTransferSummary: Equatable {
    var backupURL: URL?
    var projectsCreated: Int = 0
    var projectsUpdated: Int = 0
    var entriesCreated: Int = 0
    var entriesUpdated: Int = 0

    var totalProjectsChanged: Int {
        projectsCreated + projectsUpdated
    }

    var totalEntriesChanged: Int {
        entriesCreated + entriesUpdated
    }
}

struct PromptPanelLibraryExport: Codable, Equatable {
    static let currentFormatVersion = 1

    var formatVersion: Int
    var exportedAt: Date
    var projects: [Project]
    var entries: [Entry]

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case exportedAt = "exported_at"
        case projects
        case entries
    }
}

final class LibraryTransferService: @unchecked Sendable {
    enum TransferError: LocalizedError {
        case unsupportedFormatVersion(Int)
        case noImportableMarkdownEntries

        var errorDescription: String? {
            switch self {
            case .unsupportedFormatVersion(let version):
                return "不支持的词库格式版本：\(version)。"
            case .noImportableMarkdownEntries:
                return "没有在 Markdown 中找到可导入的词条。"
            }
        }
    }

    private let projectRepository: ProjectRepository
    private let entryRepository: EntryRepository
    private let storageMaintenanceService: StorageMaintenanceService

    init(
        projectRepository: ProjectRepository,
        entryRepository: EntryRepository,
        storageMaintenanceService: StorageMaintenanceService
    ) {
        self.projectRepository = projectRepository
        self.entryRepository = entryRepository
        self.storageMaintenanceService = storageMaintenanceService
    }

    @discardableResult
    func exportJSON(to destinationURL: URL) throws -> URL {
        let payload = try exportPayload()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    @discardableResult
    func exportMarkdown(to destinationURL: URL) throws -> URL {
        let payload = try exportPayload()
        let markdown = renderMarkdown(payload)
        try markdown.write(to: destinationURL, atomically: true, encoding: .utf8)
        return destinationURL
    }

    func importJSON(from sourceURL: URL) throws -> LibraryTransferSummary {
        let data = try Data(contentsOf: sourceURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(PromptPanelLibraryExport.self, from: data)
        return try importPayload(payload)
    }

    func importMarkdown(from sourceURL: URL) throws -> LibraryTransferSummary {
        let markdown = try String(contentsOf: sourceURL, encoding: .utf8)
        let payload = try parseMarkdown(markdown)
        return try importPayload(payload)
    }

    private func exportPayload() throws -> PromptPanelLibraryExport {
        PromptPanelLibraryExport(
            formatVersion: PromptPanelLibraryExport.currentFormatVersion,
            exportedAt: Date(),
            projects: try projectRepository.fetchAll(),
            entries: try entryRepository.fetchAll()
        )
    }

    private func importPayload(_ payload: PromptPanelLibraryExport) throws -> LibraryTransferSummary {
        guard payload.formatVersion == PromptPanelLibraryExport.currentFormatVersion else {
            throw TransferError.unsupportedFormatVersion(payload.formatVersion)
        }

        // Not `createManualBackup()`: that class is never pruned by design, and an
        // import snapshot is machine-made, so routing them together made every import
        // leave a permanent full-database copy behind.
        let backupURL = try storageMaintenanceService.createImportSafetyBackup()
        var summary = LibraryTransferSummary(backupURL: backupURL)
        try projectRepository.writeInTransaction { db in
            let localProjects = try Project
                .order(Project.Columns.isDefault.desc, Project.Columns.name.asc)
                .fetchAll(db)
            let localDefaultProject = localProjects.first(where: \.isDefault)
            var projectById = Dictionary(uniqueKeysWithValues: localProjects.map { ($0.id, $0) })
            var projectIdMap: [String: String] = [:]

            for importedProject in payload.projects {
                let name = normalizedName(importedProject.name, fallback: Constants.defaultProjectName)
                if importedProject.isDefault, let localDefaultProject {
                    projectIdMap[importedProject.id] = localDefaultProject.id
                    continue
                }

                if let existing = projectById[importedProject.id] {
                    projectIdMap[importedProject.id] = existing.id
                    guard !existing.isDefault else {
                        continue
                    }
                    var updated = importedProject
                    updated.name = name
                    updated.isDefault = false
                    updated.updatedAt = Date()
                    try updated.update(db)
                    projectById[updated.id] = updated
                    summary.projectsUpdated += 1
                } else {
                    var created = importedProject
                    created.name = name
                    created.isDefault = false
                    try created.insert(db)
                    projectById[created.id] = created
                    projectIdMap[importedProject.id] = created.id
                    summary.projectsCreated += 1
                }
            }

            let fallbackProjectId = localDefaultProject?.id ?? projectById.values.sorted { $0.name < $1.name }.first?.id
            for importedEntry in payload.entries {
                guard let targetProjectId = projectIdMap[importedEntry.projectId] ?? projectById[importedEntry.projectId]?.id ?? fallbackProjectId else {
                    continue
                }

                var entry = importedEntry
                entry.projectId = targetProjectId
                entry.title = normalizedName(entry.title, fallback: "Untitled Prompt")
                entry.tags = Entry.normalizeTags(entry.tags)

                if try Entry.fetchOne(db, key: entry.id) != nil {
                    entry.updatedAt = Date()
                    try entry.update(db)
                    summary.entriesUpdated += 1
                } else {
                    try entry.insert(db)
                    summary.entriesCreated += 1
                }
            }
        }

        return summary
    }

    private func renderMarkdown(_ payload: PromptPanelLibraryExport) -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = [
            "# PromptPanel Library Export",
            "",
            "Exported At: \(formatter.string(from: payload.exportedAt))",
            "Format: promptpanel-markdown-v1",
            ""
        ]

        let entriesByProject = Dictionary(grouping: payload.entries, by: \.projectId)
        for project in payload.projects {
            lines.append("## Project: \(project.name)")
            lines.append("Project ID: \(project.id)")
            lines.append("Default: \(project.isDefault ? "true" : "false")")
            lines.append("")

            for entry in entriesByProject[project.id, default: []] {
                lines.append("### Entry: \(entry.title)")
                lines.append("Entry ID: \(entry.id)")
                lines.append("Type: \(entry.type)")
                lines.append("Tags: \(entry.tags.joined(separator: ", "))")
                lines.append("Pinned: \(entry.isPinned ? "true" : "false")")
                lines.append("Sort Order: \(entry.sortOrder)")
                lines.append("Use Count: \(entry.useCount)")
                if let lastUsedAt = entry.lastUsedAt {
                    lines.append("Last Used At: \(formatter.string(from: lastUsedAt))")
                }
                lines.append("")
                let fence = markdownFence(for: entry.content)
                lines.append("\(fence)promptpanel")
                lines.append(entry.content)
                lines.append(fence)
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func parseMarkdown(_ markdown: String) throws -> PromptPanelLibraryExport {
        let parsed = MarkdownLibraryParser(markdown: markdown).parse()
        if !parsed.entries.isEmpty {
            return PromptPanelLibraryExport(
                formatVersion: PromptPanelLibraryExport.currentFormatVersion,
                exportedAt: Date(),
                projects: parsed.projects,
                entries: parsed.entries
            )
        }

        let fallback = parseGenericMarkdown(markdown)
        guard !fallback.entries.isEmpty else {
            throw TransferError.noImportableMarkdownEntries
        }
        return fallback
    }

    private func parseGenericMarkdown(_ markdown: String) -> PromptPanelLibraryExport {
        let project = Project(name: "Markdown Import")
        let lines = markdown.components(separatedBy: .newlines)
        var entries: [Entry] = []
        var currentTitle: String?
        var currentContent: [String] = []

        func flush() {
            guard let title = currentTitle else { return }
            let content = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }
            entries.append(Entry(projectId: project.id, title: normalizedName(title, fallback: "Markdown Prompt"), content: content))
        }

        for line in lines {
            if line.hasPrefix("## ") || line.hasPrefix("### ") {
                flush()
                currentTitle = line.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                currentContent = []
            } else if currentTitle != nil {
                currentContent.append(line)
            }
        }
        flush()

        return PromptPanelLibraryExport(
            formatVersion: PromptPanelLibraryExport.currentFormatVersion,
            exportedAt: Date(),
            projects: [project],
            entries: entries
        )
    }

    private func normalizedName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func markdownFence(for content: String) -> String {
        let longestFence = content
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("```") }
            .map { line in line.prefix { $0 == "`" }.count }
            .max() ?? 2
        return String(repeating: "`", count: max(3, longestFence + 1))
    }
}

private struct ParsedMarkdownLibrary {
    var projects: [Project]
    var entries: [Entry]
}

private struct MarkdownLibraryParser {
    private let lines: [String]

    init(markdown: String) {
        self.lines = markdown.components(separatedBy: .newlines)
    }

    func parse() -> ParsedMarkdownLibrary {
        var projects: [Project] = []
        var entries: [Entry] = []
        var currentProject = Project(name: "Markdown Import")
        var pendingProject = false
        var entryBuilder: EntryBuilder?
        var contentLines: [String] = []
        var inPromptFence = false
        var fenceMarker = "```"

        func flushEntry() {
            guard let builder = entryBuilder else { return }
            let content = contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }
            entries.append(builder.makeEntry(projectId: currentProject.id, content: content))
        }

        func flushProjectIfNeeded() {
            guard pendingProject else { return }
            projects.append(currentProject)
            pendingProject = false
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if inPromptFence {
                if line == fenceMarker {
                    inPromptFence = false
                } else {
                    contentLines.append(rawLine)
                }
                continue
            }

            if rawLine.hasPrefix("## Project: ") {
                flushEntry()
                flushProjectIfNeeded()
                entryBuilder = nil
                contentLines = []
                currentProject = Project(name: String(rawLine.dropFirst("## Project: ".count)))
                pendingProject = true
                continue
            }

            if rawLine.hasPrefix("Project ID: ") {
                currentProject.id = String(rawLine.dropFirst("Project ID: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if rawLine.hasPrefix("Default: ") {
                currentProject.isDefault = line.hasSuffix("true")
                continue
            }

            if rawLine.hasPrefix("### Entry: ") {
                flushEntry()
                flushProjectIfNeeded()
                entryBuilder = EntryBuilder(title: String(rawLine.dropFirst("### Entry: ".count)))
                contentLines = []
                continue
            }

            guard var builder = entryBuilder else {
                continue
            }

            if rawLine.hasPrefix("Entry ID: ") {
                builder.id = String(rawLine.dropFirst("Entry ID: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if rawLine.hasPrefix("Type: ") {
                builder.type = String(rawLine.dropFirst("Type: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if rawLine.hasPrefix("Tags: ") {
                let rawTags = String(rawLine.dropFirst("Tags: ".count))
                builder.tags = rawTags
                    .components(separatedBy: CharacterSet(charactersIn: ",，、"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            } else if rawLine.hasPrefix("Pinned: ") {
                builder.isPinned = line.hasSuffix("true")
            } else if rawLine.hasPrefix("Sort Order: ") {
                builder.sortOrder = Int(line.dropFirst("Sort Order: ".count)) ?? 0
            } else if rawLine.hasPrefix("Use Count: ") {
                builder.useCount = Int(line.dropFirst("Use Count: ".count)) ?? 0
            } else if rawLine.hasPrefix("Last Used At: ") {
                let rawDate = String(rawLine.dropFirst("Last Used At: ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                builder.lastUsedAt = ISO8601DateFormatter().date(from: rawDate)
            } else if line.hasPrefix("```") {
                fenceMarker = String(line.prefix { $0 == "`" })
                inPromptFence = true
            }
            entryBuilder = builder
        }

        flushEntry()
        flushProjectIfNeeded()
        return ParsedMarkdownLibrary(projects: projects, entries: entries)
    }

    private struct EntryBuilder {
        var id: String = UUID().uuidString
        var title: String
        var type: String = Constants.EntryType.prompt.rawValue
        var tags: [String] = []
        var isPinned: Bool = false
        var sortOrder: Int = 0
        var useCount: Int = 0
        var lastUsedAt: Date?

        func makeEntry(projectId: String, content: String) -> Entry {
            Entry(
                id: id.isEmpty ? UUID().uuidString : id,
                projectId: projectId,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Prompt" : title,
                content: content,
                type: type.isEmpty ? Constants.EntryType.prompt.rawValue : type,
                isPinned: isPinned,
                sortOrder: sortOrder,
                useCount: useCount,
                lastUsedAt: lastUsedAt,
                tags: tags
            )
        }
    }
}
