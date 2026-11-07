import Foundation
import GRDB

struct CloudSyncEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let deviceId: String
    let exportedAt: Date
    let projects: [Project]
    let entries: [Entry]
    let versions: [EntryVersion]

    init(
        schemaVersion: Int = CloudSyncEnvelope.currentSchemaVersion,
        deviceId: String,
        exportedAt: Date = Date(),
        projects: [Project],
        entries: [Entry],
        versions: [EntryVersion]
    ) {
        self.schemaVersion = schemaVersion
        self.deviceId = deviceId
        self.exportedAt = exportedAt
        self.projects = projects
        self.entries = entries
        self.versions = versions
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case deviceId
        case exportedAt
        case projects
        case entries
        case versions
    }

    private enum SnakeCodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case deviceId = "device_id"
        case exportedAt = "exported_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let snakeContainer = try decoder.container(keyedBy: SnakeCodingKeys.self)
        self.schemaVersion = (try? container.decodeIfPresent(Int.self, forKey: .schemaVersion))
            ?? (try? snakeContainer.decodeIfPresent(Int.self, forKey: .schemaVersion))
            ?? CloudSyncEnvelope.currentSchemaVersion
        self.deviceId = (try? container.decodeIfPresent(String.self, forKey: .deviceId))
            ?? (try? snakeContainer.decodeIfPresent(String.self, forKey: .deviceId))
            ?? "remote-client"
        if let exportedAt = try? container.decodeIfPresent(Date.self, forKey: .exportedAt) {
            self.exportedAt = exportedAt
        } else if let exportedAt = try? snakeContainer.decodeIfPresent(Date.self, forKey: .exportedAt) {
            self.exportedAt = exportedAt
        } else {
            self.exportedAt = Date()
        }
        self.projects = (try? container.decodeIfPresent([Project].self, forKey: .projects)) ?? []
        self.entries = (try? container.decodeIfPresent([Entry].self, forKey: .entries)) ?? []
        self.versions = (try? container.decodeIfPresent([EntryVersion].self, forKey: .versions)) ?? []
    }
}

struct CloudSyncSummary: Equatable, Sendable {
    let projectsCreated: Int
    let projectsUpdated: Int
    let entriesCreated: Int
    let entriesUpdated: Int
    let conflictsPreservedInVersions: Int
    let syncedAt: Date
}

struct CloudSyncHealthReport: Equatable, Sendable {
    let isReachable: Bool
    let authenticated: Bool
    let latencyMs: Int
    let namespace: String?
    let projectCount: Int
    let entryCount: Int
    let versionCount: Int
    let summaryText: String
}

enum CloudSyncError: LocalizedError, Equatable {
    case endpointNotConfigured
    case invalidEndpoint(String)
    case networkFailure(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .endpointNotConfigured:
            return "尚未配置云端同步地址（支持 HTTPS 同步接口或 iCloud/网盘同步文件路径）。"
        case .invalidEndpoint(let raw):
            return "无效的同步地址：\(raw)"
        case .networkFailure(let detail):
            return "云端同步请求失败：\(detail)"
        case .invalidPayload(let detail):
            return "同步数据格式无效：\(detail)"
        }
    }
}

final class CloudSyncService: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Device & Sync Metadata

    func deviceId() throws -> String {
        try dbQueue.write { db in
            if let existing = try String.fetchOne(
                db,
                sql: "SELECT value FROM sync_metadata WHERE key = 'device_id'"
            ), !existing.isEmpty {
                return existing
            }
            let generated = "mac-\(UUID().uuidString.prefix(8).lowercased())"
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) VALUES ('device_id', ?, ?)",
                arguments: [generated, Date()]
            )
            return generated
        }
    }

    func lastSyncStatus() throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM sync_metadata WHERE key = 'last_sync_summary'"
            )
        }
    }

    // MARK: - Envelope Export & Merge

    func buildLocalEnvelope(exportedAt: Date = Date()) throws -> CloudSyncEnvelope {
        let currentDeviceId = try deviceId()
        return try dbQueue.read { db in
            let projects = try Project
                .order(Project.Columns.createdAt.asc)
                .fetchAll(db)
            let entries = try Entry
                .order(Entry.Columns.createdAt.asc)
                .fetchAll(db)
            let versions = try EntryVersion
                .order(EntryVersion.Columns.createdAt.asc, EntryVersion.Columns.versionNumber.asc)
                .fetchAll(db)
            return CloudSyncEnvelope(
                deviceId: currentDeviceId,
                exportedAt: exportedAt,
                projects: projects,
                entries: entries,
                versions: versions
            )
        }
    }

    /// Merges a remote sync envelope into the local database using Last-Write-Wins on `updatedAt`,
    /// while automatically archiving any overwritten local entry content into `entry_versions`
    /// so concurrent edits on mobile and macOS never lose text.
    @discardableResult
    func mergeRemoteEnvelope(_ envelope: CloudSyncEnvelope, syncedAt: Date = Date()) throws -> CloudSyncSummary {
        var projectsCreated = 0
        var projectsUpdated = 0
        var entriesCreated = 0
        var entriesUpdated = 0
        var conflictsPreserved = 0

        try dbQueue.write { db in
            var remappedProjectIds: [String: String] = [:]
            let localDefaultProject = try Project
                .filter(Project.Columns.isDefault == true)
                .fetchOne(db)

            // 1. Merge Projects
            for remoteProject in envelope.projects {
                if let localProject = try Project.fetchOne(db, key: remoteProject.id) {
                    if remoteProject.updatedAt > localProject.updatedAt {
                        var merged = remoteProject
                        if localProject.isSystemProtected {
                            merged.isDefault = localProject.isDefault
                            merged.groupKind = localProject.groupKind
                            merged.isArchived = false
                            merged.deletedAt = nil
                        }
                        try merged.update(db)
                        projectsUpdated += 1
                    }
                } else if remoteProject.isDefault, let localDefault = localDefaultProject {
                    remappedProjectIds[remoteProject.id] = localDefault.id
                } else {
                    try remoteProject.insert(db)
                    if remoteProject.deletedAt == nil {
                        projectsCreated += 1
                    }
                }
            }

            // Ensure every remote entry's project exists (active entries fall back to default project if target was deleted)
            let allProjectIds = Set(try String.fetchAll(db, sql: "SELECT id FROM projects"))
            let activeProjectIds = Set(try String.fetchAll(db, sql: "SELECT id FROM projects WHERE deleted_at IS NULL"))
            let fallbackProjectId = localDefaultProject?.id ?? Constants.inboxProjectId

            // 2. Merge Entries with Conflict-to-Version-History protection
            for var remoteEntry in envelope.entries {
                if let mappedId = remappedProjectIds[remoteEntry.projectId] {
                    remoteEntry.projectId = mappedId
                } else if remoteEntry.deletedAt == nil && !activeProjectIds.contains(remoteEntry.projectId) {
                    remoteEntry.projectId = fallbackProjectId
                } else if !allProjectIds.contains(remoteEntry.projectId) {
                    remoteEntry.projectId = fallbackProjectId
                }

                if let localEntry = try Entry.fetchOne(db, key: remoteEntry.id) {
                    if remoteEntry.updatedAt > localEntry.updatedAt {
                        let isRemoteDeletion = localEntry.deletedAt == nil && remoteEntry.deletedAt != nil
                        let hasContentConflict = localEntry.content != remoteEntry.content
                            || localEntry.title != remoteEntry.title

                        if hasContentConflict || isRemoteDeletion {
                            let maxVer = try Int.fetchOne(
                                db,
                                sql: "SELECT COALESCE(MAX(version_number), 0) FROM entry_versions WHERE entry_id = ?",
                                arguments: [localEntry.id]
                            ) ?? 0

                            // Ensure local state is snapshotted before applying remote overwrite or deletion
                            let latestLocalSnapshot = try EntryVersion
                                .filter(EntryVersion.Columns.entryId == localEntry.id)
                                .order(EntryVersion.Columns.versionNumber.desc)
                                .fetchOne(db)

                            var nextVersion = maxVer
                            if latestLocalSnapshot?.content != localEntry.content || latestLocalSnapshot?.title != localEntry.title {
                                nextVersion += 1
                                let localBackup = EntryVersion(
                                    entryId: localEntry.id,
                                    versionNumber: nextVersion,
                                    title: localEntry.title,
                                    content: localEntry.content,
                                    changeNote: isRemoteDeletion ? "云端同步删除前本地版本自动留存" : "云端同步前本地版本自动留存",
                                    createdAt: localEntry.updatedAt
                                )
                                try localBackup.insert(db)
                                conflictsPreserved += 1
                            }

                            if hasContentConflict && remoteEntry.deletedAt == nil {
                                nextVersion += 1
                                let remoteSnapshot = EntryVersion(
                                    entryId: remoteEntry.id,
                                    versionNumber: nextVersion,
                                    title: remoteEntry.title,
                                    content: remoteEntry.content,
                                    changeNote: "云端同步更新 (\(envelope.deviceId))",
                                    createdAt: remoteEntry.updatedAt
                                )
                                try remoteSnapshot.insert(db)
                            }
                        }

                        // Keep the higher usage count and more recent lastUsedAt across devices
                        remoteEntry.useCount = max(localEntry.useCount, remoteEntry.useCount)
                        if let localUsed = localEntry.lastUsedAt {
                            if let remoteUsed = remoteEntry.lastUsedAt {
                                remoteEntry.lastUsedAt = max(localUsed, remoteUsed)
                            } else {
                                remoteEntry.lastUsedAt = localUsed
                            }
                        }
                        try remoteEntry.update(db)
                        entriesUpdated += 1
                    } else if remoteEntry.updatedAt < localEntry.updatedAt {
                        let hasContentConflict = localEntry.content != remoteEntry.content
                            || localEntry.title != remoteEntry.title
                        if hasContentConflict {
                            let existingVersions = try EntryVersion
                                .filter(EntryVersion.Columns.entryId == localEntry.id)
                                .fetchAll(db)
                            let alreadyRecorded = existingVersions.contains {
                                $0.content == remoteEntry.content && $0.title == remoteEntry.title
                            }
                            if !alreadyRecorded {
                                let maxVer = existingVersions.map(\.versionNumber).max() ?? 0
                                let remoteHistoricalSnapshot = EntryVersion(
                                    entryId: localEntry.id,
                                    versionNumber: maxVer + 1,
                                    title: remoteEntry.title,
                                    content: remoteEntry.content,
                                    changeNote: "云端并发历史版本自动留存 (\(envelope.deviceId))",
                                    createdAt: remoteEntry.updatedAt
                                )
                                try remoteHistoricalSnapshot.insert(db)
                                conflictsPreserved += 1
                            }
                        }

                        var updatedLocal = localEntry
                        var didUpdateUsage = false
                        if remoteEntry.useCount > updatedLocal.useCount {
                            updatedLocal.useCount = remoteEntry.useCount
                            didUpdateUsage = true
                        }
                        if let remoteUsed = remoteEntry.lastUsedAt {
                            if let localUsed = updatedLocal.lastUsedAt {
                                if remoteUsed > localUsed {
                                    updatedLocal.lastUsedAt = remoteUsed
                                    didUpdateUsage = true
                                }
                            } else {
                                updatedLocal.lastUsedAt = remoteUsed
                                didUpdateUsage = true
                            }
                        }
                        if didUpdateUsage {
                            try updatedLocal.update(db)
                        }
                    }
                } else {
                    try remoteEntry.insert(db)
                    if remoteEntry.deletedAt == nil {
                        entriesCreated += 1

                        let existingVerCount = try EntryVersion
                            .filter(EntryVersion.Columns.entryId == remoteEntry.id)
                            .fetchCount(db)
                        if existingVerCount == 0 {
                            let initialSnapshot = EntryVersion(
                                entryId: remoteEntry.id,
                                versionNumber: 1,
                                title: remoteEntry.title,
                                content: remoteEntry.content,
                                changeNote: "从云端同步拉取 (\(envelope.deviceId))",
                                createdAt: remoteEntry.createdAt
                            )
                            try initialSnapshot.insert(db)
                        }
                    }
                }
            }

            // 3. Merge Explicit Remote Version History
            for remoteVersion in envelope.versions {
                guard try Entry.fetchOne(db, key: remoteVersion.entryId) != nil else { continue }
                let existsById = try EntryVersion.fetchOne(db, key: remoteVersion.id) != nil
                if !existsById {
                    let existingVersions = try EntryVersion
                        .filter(EntryVersion.Columns.entryId == remoteVersion.entryId)
                        .fetchAll(db)
                    let existsByNumber = existingVersions.contains { $0.versionNumber == remoteVersion.versionNumber }
                    if !existsByNumber {
                        try remoteVersion.insert(db)
                    } else {
                        let alreadyHasSameText = existingVersions.contains {
                            $0.content == remoteVersion.content && $0.title == remoteVersion.title
                        }
                        if !alreadyHasSameText {
                            let maxVer = existingVersions.map(\.versionNumber).max() ?? 0
                            var renumbered = remoteVersion
                            renumbered.versionNumber = maxVer + 1
                            try renumbered.insert(db)
                        }
                    }
                }
            }

            let summaryText = "上次同步：\(Self.summaryFormatter.string(from: syncedAt))（项目 +\(projectsCreated)/更\(projectsUpdated)，词条 +\(entriesCreated)/更\(entriesUpdated)，冲突版本保护 \(conflictsPreserved)）"
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) VALUES ('last_sync_summary', ?, ?)",
                arguments: [summaryText, syncedAt]
            )
        }

        return CloudSyncSummary(
            projectsCreated: projectsCreated,
            projectsUpdated: projectsUpdated,
            entriesCreated: entriesCreated,
            entriesUpdated: entriesUpdated,
            conflictsPreservedInVersions: conflictsPreserved,
            syncedAt: syncedAt
        )
    }

    // MARK: - Sync Execution (File / Cloud Drive or HTTPS Endpoint)

    /// Resolves the health check path while preserving any reverse-proxy subpath prefix.
    static func resolvedHealthPath(from rawPath: String) -> String {
        var path = rawPath
        while path.count > 1 && path.hasSuffix("/") {
            path.removeLast()
        }
        if path.isEmpty || path == "/" {
            return "/v1/health"
        }
        if path.hasSuffix("/v1/health") || path.hasSuffix("/health") {
            return path
        }
        for syncSuffix in ["/v1/sync", "/v1/promptpanel", "/sync"] {
            if path.hasSuffix(syncSuffix) {
                let prefix = String(path.dropLast(syncSuffix.count))
                return prefix + "/v1/health"
            }
        }
        return path + "/v1/health"
    }

    func testConnection(endpoint: String, apiKey: String) throws -> CloudSyncHealthReport {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudSyncError.endpointNotConfigured
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard var components = URLComponents(string: trimmed) else {
                throw CloudSyncError.invalidEndpoint(trimmed)
            }
            components.path = Self.resolvedHealthPath(from: components.path)
            components.query = nil
            guard let healthURL = components.url else {
                throw CloudSyncError.invalidEndpoint(trimmed)
            }

            var request = URLRequest(url: healthURL, timeoutInterval: 10)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try performSynchronousRequest(request)
            let latencyMs = max(Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000), 1)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw CloudSyncError.networkFailure("HTTP \(code)")
            }

            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
            let authenticated = (json["authenticated"] as? Bool) ?? !apiKey.isEmpty
            let namespace = json["namespace"] as? String
            let pCount = (json["projectCount"] as? Int) ?? 0
            let eCount = (json["entryCount"] as? Int) ?? 0
            let vCount = (json["versionCount"] as? Int) ?? 0
            let nsLabel = namespace.map { "空间 \($0)" } ?? (authenticated ? "已鉴权" : "未提供 Token")
            let summary = "连接正常 · \(latencyMs) ms · \(nsLabel)（云端 \(pCount) 组 / \(eCount) 条 / \(vCount) 版）"

            return CloudSyncHealthReport(
                isReachable: true,
                authenticated: authenticated,
                latencyMs: latencyMs,
                namespace: namespace,
                projectCount: pCount,
                entryCount: eCount,
                versionCount: vCount,
                summaryText: summary
            )
        } else {
            let fileURL: URL
            if trimmed.hasPrefix("file://"), let parsed = URL(string: trimmed) {
                fileURL = parsed
            } else {
                let expanded = NSString(string: trimmed).expandingTildeInPath
                fileURL = URL(fileURLWithPath: expanded)
            }
            let parentDir = fileURL.deletingLastPathComponent()
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: parentDir.path, isDirectory: &isDir)
            guard exists && isDir.boolValue else {
                throw CloudSyncError.invalidEndpoint("目录不存在：\(parentDir.path)")
            }
            let latencyMs = max(Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000), 1)
            return CloudSyncHealthReport(
                isReachable: true,
                authenticated: true,
                latencyMs: latencyMs,
                namespace: "local-file",
                projectCount: 0,
                entryCount: 0,
                versionCount: 0,
                summaryText: "本地/网盘同步文件可用 · \(fileURL.lastPathComponent)"
            )
        }
    }

    func syncNow(endpoint: String, apiKey: String) throws -> CloudSyncSummary {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudSyncError.endpointNotConfigured
        }

        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            guard var components = URLComponents(string: trimmed) else {
                throw CloudSyncError.invalidEndpoint(trimmed)
            }
            if components.path.isEmpty || components.path == "/" {
                components.path = "/v1/sync"
            }
            guard let url = components.url else {
                throw CloudSyncError.invalidEndpoint(trimmed)
            }
            return try syncViaHTTP(url: url, apiKey: apiKey)
        } else {
            let fileURL: URL
            if trimmed.hasPrefix("file://"), let parsed = URL(string: trimmed) {
                fileURL = parsed
            } else {
                let expanded = NSString(string: trimmed).expandingTildeInPath
                fileURL = URL(fileURLWithPath: expanded)
            }
            return try syncViaFile(fileURL: fileURL)
        }
    }

    private func syncViaFile(fileURL: URL) throws -> CloudSyncSummary {
        let encoder = Self.makeEncoder()
        let decoder = Self.makeDecoder()
        let summary: CloudSyncSummary

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            if !data.isEmpty {
                let remoteEnvelope = try decoder.decode(CloudSyncEnvelope.self, from: data)
                summary = try mergeRemoteEnvelope(remoteEnvelope)
            } else {
                summary = try mergeRemoteEnvelope(buildLocalEnvelope())
            }
        } else {
            let parentDir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            summary = try mergeRemoteEnvelope(buildLocalEnvelope())
        }

        let mergedEnvelope = try buildLocalEnvelope()
        let encoded = try encoder.encode(mergedEnvelope)
        try encoded.write(to: fileURL, options: .atomic)
        return summary
    }

    private func syncViaHTTP(url: URL, apiKey: String) throws -> CloudSyncSummary {
        let encoder = Self.makeEncoder()
        let decoder = Self.makeDecoder()

        // 1. Pull remote envelope (GET)
        var getRequest = URLRequest(url: url, timeoutInterval: 15)
        getRequest.httpMethod = "GET"
        getRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            getRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let (getData, getResponse) = try performSynchronousRequest(getRequest)
        if let httpResponse = getResponse as? HTTPURLResponse,
           httpResponse.statusCode == 401 {
            throw CloudSyncError.networkFailure("Token 鉴权未通过 (HTTP 401)，请确认已填写不少于 12 位的专属 Token")
        }

        var summary: CloudSyncSummary
        if let httpResponse = getResponse as? HTTPURLResponse,
           (200..<300).contains(httpResponse.statusCode),
           !getData.isEmpty {
            do {
                let remoteEnvelope = try decoder.decode(CloudSyncEnvelope.self, from: getData)
                summary = try mergeRemoteEnvelope(remoteEnvelope)
            } catch {
                throw CloudSyncError.invalidPayload(error.localizedDescription)
            }
        } else {
            summary = try mergeRemoteEnvelope(buildLocalEnvelope())
        }

        // 2. Push merged envelope (POST) and reconcile any concurrent server-merged delta
        let mergedEnvelope = try buildLocalEnvelope()
        var postRequest = URLRequest(url: url, timeoutInterval: 15)
        postRequest.httpMethod = "POST"
        postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        postRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if !apiKey.isEmpty {
            postRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        postRequest.httpBody = try encoder.encode(mergedEnvelope)

        let (postData, postResponse) = try performSynchronousRequest(postRequest)
        if let httpResponse = postResponse as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw CloudSyncError.networkFailure("HTTP \(httpResponse.statusCode)")
        }
        if !postData.isEmpty {
            do {
                let serverMergedEnvelope = try decoder.decode(CloudSyncEnvelope.self, from: postData)
                let secondPass = try mergeRemoteEnvelope(serverMergedEnvelope)
                summary = CloudSyncSummary(
                    projectsCreated: summary.projectsCreated + secondPass.projectsCreated,
                    projectsUpdated: summary.projectsUpdated + secondPass.projectsUpdated,
                    entriesCreated: summary.entriesCreated + secondPass.entriesCreated,
                    entriesUpdated: summary.entriesUpdated + secondPass.entriesUpdated,
                    conflictsPreservedInVersions: summary.conflictsPreservedInVersions + secondPass.conflictsPreservedInVersions,
                    syncedAt: secondPass.syncedAt
                )
                try dbQueue.write { db in
                    let summaryText = "上次同步：\(Self.summaryFormatter.string(from: summary.syncedAt))（项目 +\(summary.projectsCreated)/更\(summary.projectsUpdated)，词条 +\(summary.entriesCreated)/更\(summary.entriesUpdated)，冲突版本保护 \(summary.conflictsPreservedInVersions)）"
                    try db.execute(
                        sql: "INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) VALUES ('last_sync_summary', ?, ?)",
                        arguments: [summaryText, summary.syncedAt]
                    )
                }
            } catch {
                throw CloudSyncError.invalidPayload(error.localizedDescription)
            }
        }

        return summary
    }

    private func performSynchronousRequest(_ request: URLRequest) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        var responseData = Data()
        var urlResponse: URLResponse?
        var requestError: Error?

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let data { responseData = data }
            urlResponse = response
            requestError = error
            semaphore.signal()
        }
        task.resume()
        semaphore.wait()

        if let requestError {
            throw CloudSyncError.networkFailure(requestError.localizedDescription)
        }
        guard let urlResponse else {
            throw CloudSyncError.networkFailure("无响应")
        }
        return (responseData, urlResponse)
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.iso8601WithFractionalSeconds.string(from: date))
        }
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = Self.iso8601WithFractionalSeconds.date(from: raw)
                ?? Self.iso8601Standard.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date string: \(raw)"
            )
        }
        return decoder
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let summaryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
