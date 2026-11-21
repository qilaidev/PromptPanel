import CryptoKit
import Foundation
import GRDB
import zlib

enum CloudSyncCrypto {
    private static let hkdfSalt = Data("PromptPanel-HKDF-Salt-v2".utf8)
    private static let hkdfInfo = Data("promptpanel-v2-aes256gcm-key".utf8) + Data([0x01])
    private static let wireAAD = Data("promptpanel-aead-v2".utf8)
    private static let maxDecompressedBytes = 16 * 1024 * 1024

    private struct EncryptedWireWrapper: Codable {
        let cipher: String
        let v: Int?
        let data: String
    }

    static func deriveSymmetricKey(from token: String) -> SymmetricKey {
        let ikm = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let prk = Data(HMAC<SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: hkdfSalt)))
        let okm = Data(HMAC<SHA256>.authenticationCode(for: hkdfInfo, using: SymmetricKey(data: prk)))
        return SymmetricKey(data: okm)
    }

    static func sealEnvelopeData(_ plaintextJSON: Data, apiKey: String) throws -> Data {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.count >= 12 else {
            return plaintextJSON
        }
        let key = deriveSymmetricKey(from: trimmedKey)
        let compressed = try gzipCompress(plaintextJSON)
        let sealedBox = try AES.GCM.seal(compressed, using: key, authenticating: wireAAD)
        guard let combined = sealedBox.combined else {
            throw CloudSyncError.invalidPayload("AES-256-GCM 封装失败")
        }
        let wrapper = EncryptedWireWrapper(
            cipher: "aes-256-gcm+gzip",
            v: 2,
            data: combined.base64EncodedString()
        )
        return try JSONEncoder().encode(wrapper)
    }

    static func openEnvelopeData(_ rawData: Data, apiKey: String) throws -> Data {
        guard let wrapper = try? JSONDecoder().decode(EncryptedWireWrapper.self, from: rawData),
              wrapper.cipher.hasPrefix("aes-256-gcm") else {
            return rawData
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedKey.count >= 12 else {
            throw CloudSyncError.invalidPayload("收到加密同步包，但本地未配置有效 Token 密钥")
        }
        guard let combined = Data(base64Encoded: wrapper.data), combined.count >= 28 else {
            throw CloudSyncError.invalidPayload("加密同步包 Base64 数据损坏")
        }
        let key = deriveSymmetricKey(from: trimmedKey)
        let sealedBox: AES.GCM.SealedBox
        do {
            sealedBox = try AES.GCM.SealedBox(combined: combined)
        } catch {
            throw CloudSyncError.invalidPayload("AES-256-GCM 密文结构无效")
        }
        let decrypted: Data
        do {
            decrypted = try AES.GCM.open(sealedBox, using: key, authenticating: wireAAD)
        } catch {
            throw CloudSyncError.invalidPayload("AES-256-GCM 签名校验或解密失败，请确认两端 Token 一致")
        }
        if wrapper.cipher == "aes-256-gcm+gzip" || (decrypted.count >= 2 && decrypted[decrypted.startIndex] == 0x1f && decrypted[decrypted.startIndex + 1] == 0x8b) {
            return try gzipDecompress(decrypted)
        }
        return decrypted
    }

    static func gzipCompress(_ input: Data) throws -> Data {
        if input.isEmpty { return Data() }
        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            MAX_WBITS + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw CloudSyncError.invalidPayload("Gzip 压缩初始化失败")
        }
        defer { deflateEnd(&stream) }

        let chunkSize = 32_768
        var output = Data(capacity: max(256, input.count / 2))
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        try input.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = uInt(input.count)

            repeat {
                try chunk.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    let ret = deflate(&stream, Z_FINISH)
                    guard ret != Z_STREAM_ERROR else {
                        throw CloudSyncError.invalidPayload("Gzip 压缩流错误")
                    }
                    let produced = chunkSize - Int(stream.avail_out)
                    if produced > 0, let base = outBuf.baseAddress {
                        output.append(base, count: produced)
                    }
                }
            } while stream.avail_out == 0
        }
        return output
    }

    static func gzipDecompress(_ input: Data) throws -> Data {
        if input.isEmpty { return Data() }
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream,
            MAX_WBITS + 32,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard initStatus == Z_OK else {
            throw CloudSyncError.invalidPayload("Gzip 解压初始化失败")
        }
        defer { inflateEnd(&stream) }

        let chunkSize = 65_536
        var output = Data(capacity: min(maxDecompressedBytes, input.count * 3))
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        try input.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return }
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = uInt(input.count)

            var status: Int32 = Z_OK
            repeat {
                try chunk.withUnsafeMutableBufferPointer { outBuf in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(chunkSize)
                    status = inflate(&stream, Z_NO_FLUSH)
                    guard status == Z_OK || status == Z_STREAM_END else {
                        throw CloudSyncError.invalidPayload("Gzip 解压校验失败")
                    }
                    let produced = chunkSize - Int(stream.avail_out)
                    if produced > 0, let base = outBuf.baseAddress {
                        output.append(base, count: produced)
                        if output.count > maxDecompressedBytes {
                            throw CloudSyncError.invalidPayload("解压体积超出安全上限")
                        }
                    }
                }
            } while status != Z_STREAM_END && stream.avail_out == 0
        }
        return output
    }
}

struct CloudSyncEnvelope: Codable, Equatable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let deviceId: String
    let exportedAt: Date
    let projects: [Project]
    let entries: [Entry]
    let versions: [EntryVersion]
    let revision: Int?
    let serverRevision: Int?
    let serverTime: Date?
    let unchanged: Bool?
    let allowMassDelete: Bool?
    let expectedRevision: Int?
    let strictConflict: Bool?
    let forceOverwrite: Bool?
    let conflict: Bool?
    let rebased: Bool?

    init(
        schemaVersion: Int = CloudSyncEnvelope.currentSchemaVersion,
        deviceId: String,
        exportedAt: Date = Date(),
        projects: [Project],
        entries: [Entry],
        versions: [EntryVersion],
        revision: Int? = nil,
        serverRevision: Int? = nil,
        serverTime: Date? = nil,
        unchanged: Bool? = nil,
        allowMassDelete: Bool? = nil,
        expectedRevision: Int? = nil,
        strictConflict: Bool? = nil,
        forceOverwrite: Bool? = nil,
        conflict: Bool? = nil,
        rebased: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.deviceId = deviceId
        self.exportedAt = exportedAt
        self.projects = projects
        self.entries = entries
        self.versions = versions
        self.revision = revision
        self.serverRevision = serverRevision
        self.serverTime = serverTime
        self.unchanged = unchanged
        self.allowMassDelete = allowMassDelete
        self.expectedRevision = expectedRevision
        self.strictConflict = strictConflict
        self.forceOverwrite = forceOverwrite
        self.conflict = conflict
        self.rebased = rebased
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case deviceId
        case exportedAt
        case projects
        case entries
        case versions
        case revision
        case serverRevision
        case serverTime
        case unchanged
        case allowMassDelete
        case expectedRevision
        case strictConflict
        case forceOverwrite
        case conflict
        case rebased
    }

    private enum SnakeCodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case deviceId = "device_id"
        case exportedAt = "exported_at"
        case serverRevision = "server_revision"
        case serverTime = "server_time"
        case allowMassDelete = "allow_mass_delete"
        case expectedRevision = "expected_revision"
        case strictConflict = "strict_conflict"
        case forceOverwrite = "force_overwrite"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let snakeContainer = try decoder.container(keyedBy: SnakeCodingKeys.self)
        let hasRecognizedEnvelopeKey = container.contains(.schemaVersion)
            || snakeContainer.contains(.schemaVersion)
            || container.contains(.deviceId)
            || snakeContainer.contains(.deviceId)
            || container.contains(.exportedAt)
            || snakeContainer.contains(.exportedAt)
            || container.contains(.projects)
            || container.contains(.entries)
            || container.contains(.versions)
            || container.contains(.revision)
            || container.contains(.serverRevision)
            || container.contains(.unchanged)
            || container.contains(.conflict)
        guard hasRecognizedEnvelopeKey else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "JSON payload is not a valid PromptPanel sync envelope"
                )
            )
        }
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
        self.projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        self.entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        self.versions = try container.decodeIfPresent([EntryVersion].self, forKey: .versions) ?? []
        self.revision = try? container.decodeIfPresent(Int.self, forKey: .revision)
        self.serverRevision = (try? container.decodeIfPresent(Int.self, forKey: .serverRevision))
            ?? (try? snakeContainer.decodeIfPresent(Int.self, forKey: .serverRevision))
        self.serverTime = (try? container.decodeIfPresent(Date.self, forKey: .serverTime))
            ?? (try? snakeContainer.decodeIfPresent(Date.self, forKey: .serverTime))
        self.unchanged = try? container.decodeIfPresent(Bool.self, forKey: .unchanged)
        self.allowMassDelete = (try? container.decodeIfPresent(Bool.self, forKey: .allowMassDelete))
            ?? (try? snakeContainer.decodeIfPresent(Bool.self, forKey: .allowMassDelete))
        self.expectedRevision = (try? container.decodeIfPresent(Int.self, forKey: .expectedRevision))
            ?? (try? snakeContainer.decodeIfPresent(Int.self, forKey: .expectedRevision))
        self.strictConflict = (try? container.decodeIfPresent(Bool.self, forKey: .strictConflict))
            ?? (try? snakeContainer.decodeIfPresent(Bool.self, forKey: .strictConflict))
        self.forceOverwrite = (try? container.decodeIfPresent(Bool.self, forKey: .forceOverwrite))
            ?? (try? snakeContainer.decodeIfPresent(Bool.self, forKey: .forceOverwrite))
        self.conflict = try? container.decodeIfPresent(Bool.self, forKey: .conflict)
        self.rebased = try? container.decodeIfPresent(Bool.self, forKey: .rebased)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(deviceId, forKey: .deviceId)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(projects, forKey: .projects)
        try container.encode(entries, forKey: .entries)
        try container.encode(versions, forKey: .versions)
        if allowMassDelete == true {
            try container.encode(true, forKey: .allowMassDelete)
        }
        if let expectedRevision {
            try container.encode(expectedRevision, forKey: .expectedRevision)
        }
        if strictConflict == true {
            try container.encode(true, forKey: .strictConflict)
        }
        if forceOverwrite == true {
            try container.encode(true, forKey: .forceOverwrite)
        }
    }
}

struct CloudSyncSummary: Equatable, Sendable {
    let projectsCreated: Int
    let projectsUpdated: Int
    let entriesCreated: Int
    let entriesUpdated: Int
    let entriesDeleted: Int
    let mergedUsageUpdates: Int
    let mergedVersions: Int
    let conflictsPreservedInVersions: Int
    let orphansMigrated: Int
    let protectedEntriesCount: Int
    let protectedProjectsCount: Int
    let pushedChangesCount: Int
    let remoteRevision: Int?
    let actionMode: CloudSyncActionMode
    let direction: CloudSyncDirection
    let report: CloudSyncReport?
    let syncedAt: Date

    init(
        projectsCreated: Int,
        projectsUpdated: Int,
        entriesCreated: Int,
        entriesUpdated: Int,
        entriesDeleted: Int = 0,
        mergedUsageUpdates: Int = 0,
        mergedVersions: Int = 0,
        conflictsPreservedInVersions: Int,
        orphansMigrated: Int = 0,
        protectedEntriesCount: Int = 0,
        protectedProjectsCount: Int = 0,
        pushedChangesCount: Int = 0,
        remoteRevision: Int? = nil,
        actionMode: CloudSyncActionMode = .smartBidirectional,
        direction: CloudSyncDirection = .bidirectional,
        report: CloudSyncReport? = nil,
        syncedAt: Date
    ) {
        self.projectsCreated = projectsCreated
        self.projectsUpdated = projectsUpdated
        self.entriesCreated = entriesCreated
        self.entriesUpdated = entriesUpdated
        self.entriesDeleted = entriesDeleted
        self.mergedUsageUpdates = mergedUsageUpdates
        self.mergedVersions = mergedVersions
        self.conflictsPreservedInVersions = conflictsPreservedInVersions
        self.orphansMigrated = orphansMigrated
        self.protectedEntriesCount = protectedEntriesCount
        self.protectedProjectsCount = protectedProjectsCount
        self.pushedChangesCount = pushedChangesCount
        self.remoteRevision = remoteRevision
        self.actionMode = actionMode
        self.direction = direction
        self.report = report
        self.syncedAt = syncedAt
    }

    var totalProtectedCount: Int {
        protectedEntriesCount + protectedProjectsCount
    }

    var hasAnyLocalMutation: Bool {
        projectsCreated > 0
            || projectsUpdated > 0
            || entriesCreated > 0
            || entriesUpdated > 0
            || entriesDeleted > 0
            || mergedUsageUpdates > 0
            || mergedVersions > 0
            || conflictsPreservedInVersions > 0
            || orphansMigrated > 0
            || totalProtectedCount > 0
    }
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
    case syncInProgress
    case networkFailure(String)
    case invalidPayload(String)

    var errorDescription: String? {
        switch self {
        case .endpointNotConfigured:
            return "尚未配置云端同步地址（支持 HTTPS 同步接口或 iCloud/网盘同步文件路径）。"
        case .invalidEndpoint(let raw):
            return "无效的同步地址：\(raw)"
        case .syncInProgress:
            return "云端同步正在进行中，请稍候重试。"
        case .networkFailure(let detail):
            return "云端同步请求失败：\(detail)"
        case .invalidPayload(let detail):
            return "同步数据格式无效：\(detail)"
        }
    }
}

final class CloudSyncService: @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    private let storageMaintenanceService: StorageMaintenanceService?
    private let urlSession: URLSession
    private let syncLock = NSLock()
    private var isSyncOperationInFlight = false
    private var armedAllowMassDelete = false
    private var cachedDeviceId: String?

    init(
        dbQueue: DatabaseQueue,
        storageMaintenanceService: StorageMaintenanceService? = nil,
        urlSession: URLSession = .shared
    ) {
        self.dbQueue = dbQueue
        self.storageMaintenanceService = storageMaintenanceService
        self.urlSession = urlSession
    }

    func armAllowMassDeleteForNextSync() {
        syncLock.lock()
        armedAllowMassDelete = true
        syncLock.unlock()
    }

    private func consumeArmedAllowMassDelete() -> Bool {
        syncLock.lock()
        defer { syncLock.unlock() }
        let wasArmed = armedAllowMassDelete
        armedAllowMassDelete = false
        return wasArmed
    }

    private func acquireSyncSlot() throws {
        syncLock.lock()
        defer { syncLock.unlock() }
        guard !isSyncOperationInFlight else {
            throw CloudSyncError.syncInProgress
        }
        isSyncOperationInFlight = true
    }

    private func releaseSyncSlot() {
        syncLock.lock()
        isSyncOperationInFlight = false
        syncLock.unlock()
    }

    // MARK: - Device & Sync Metadata

    func deviceId() throws -> String {
        syncLock.lock()
        if let cached = cachedDeviceId, !cached.isEmpty {
            syncLock.unlock()
            return cached
        }
        syncLock.unlock()

        if let existing = try dbQueue.read({ db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM sync_metadata WHERE key = ?",
                arguments: [SyncMetadataKey.deviceId]
            )
        }), !existing.isEmpty {
            syncLock.lock()
            cachedDeviceId = existing
            syncLock.unlock()
            return existing
        }

        let resolved = try dbQueue.write { db -> String in
            if let existing = try String.fetchOne(
                db,
                sql: "SELECT value FROM sync_metadata WHERE key = ?",
                arguments: [SyncMetadataKey.deviceId]
            ), !existing.isEmpty {
                return existing
            }
            let generated = "mac-\(UUID().uuidString.prefix(8).lowercased())"
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) VALUES (?, ?, ?)",
                arguments: [SyncMetadataKey.deviceId, generated, Date()]
            )
            return generated
        }
        syncLock.lock()
        cachedDeviceId = resolved
        syncLock.unlock()
        return resolved
    }

    func lastSyncStatus() throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM sync_metadata WHERE key = ?",
                arguments: [SyncMetadataKey.lastSyncSummary]
            )
        }
    }

    func lastSyncReport() throws -> CloudSyncReport? {
        guard let rawJSON = try dbQueue.read({ db in
            try String.fetchOne(
                db,
                sql: "SELECT value FROM sync_metadata WHERE key = ?",
                arguments: [SyncMetadataKey.lastSyncReportJson]
            )
        }), let data = rawJSON.data(using: .utf8), !data.isEmpty else {
            return nil
        }
        return try? Self.makeDecoder().decode(CloudSyncReport.self, from: data)
    }

    func pendingSyncState() throws -> (
        hasPendingLocalChanges: Bool,
        hasUsageChanges: Bool,
        pendingDelta: Int,
        localSeq: Int,
        lastSyncedSeq: Int,
        lastSyncedRevision: Int?
    ) {
        try dbQueue.read { db in
            let localSeq = Self.fetchIntMeta(db, key: SyncMetadataKey.localMutationSeq) ?? 0
            let lastSyncedSeq = Self.fetchIntMeta(db, key: SyncMetadataKey.lastSyncedMutationSeq) ?? 0
            let lastRev = Self.fetchIntMeta(db, key: SyncMetadataKey.lastSyncedRevision)
            let lastContentFP = Self.fetchStringMeta(db, key: SyncMetadataKey.lastSyncedContentFingerprint)
            let currentContentFP = try Self.computeLocalContentFingerprint(in: db)
            let usageDirty = Self.fetchStringMeta(db, key: SyncMetadataKey.usageDirty) == "1"
            let seqDelta = max(0, localSeq - lastSyncedSeq)
            let hasContentChanges = seqDelta > 0
                || (lastContentFP != nil && lastContentFP != currentContentFP)
            return (
                hasPendingLocalChanges: hasContentChanges,
                hasUsageChanges: usageDirty,
                pendingDelta: max(seqDelta, hasContentChanges ? 1 : 0),
                localSeq: localSeq,
                lastSyncedSeq: lastSyncedSeq,
                lastSyncedRevision: lastRev
            )
        }
    }

    private static func fetchStringMeta(_ db: Database, key: String) -> String? {
        try? String.fetchOne(db, sql: "SELECT value FROM sync_metadata WHERE key = ?", arguments: [key])
    }

    private static func fetchIntMeta(_ db: Database, key: String) -> Int? {
        guard let raw = fetchStringMeta(db, key: key) else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func saveMeta(_ db: Database, key: String, value: String, date: Date) throws {
        try db.execute(
            sql: "INSERT OR REPLACE INTO sync_metadata (key, value, updated_at) VALUES (?, ?, ?)",
            arguments: [key, value, date]
        )
    }

    // MARK: - Envelope Export & Merge

    func buildLocalEnvelope(
        exportedAt: Date = Date(),
        allowMassDelete: Bool = false,
        expectedRevision: Int? = nil,
        strictConflict: Bool = false,
        forceOverwrite: Bool = false
    ) throws -> CloudSyncEnvelope {
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
                versions: versions,
                allowMassDelete: allowMassDelete ? true : nil,
                expectedRevision: expectedRevision,
                strictConflict: strictConflict ? true : nil,
                forceOverwrite: forceOverwrite ? true : nil
            )
        }
    }

    func computeLocalStateFingerprint() throws -> String {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT
                        (SELECT COUNT(*) FROM projects) AS p_count,
                        (SELECT COALESCE(MAX(updated_at), '') FROM projects) AS p_max_upd,
                        (SELECT COUNT(*) FROM entries) AS e_count,
                        (SELECT COALESCE(MAX(updated_at), '') FROM entries) AS e_max_upd,
                        (SELECT COALESCE(MAX(last_used_at), '') FROM entries) AS e_max_used,
                        (SELECT COALESCE(SUM(use_count), 0) FROM entries) AS e_sum_use,
                        (SELECT COUNT(*) FROM entry_versions) AS v_count,
                        (SELECT COALESCE(MAX(created_at), '') FROM entry_versions) AS v_max_created
                    """
            )
            guard let row else { return "empty" }
            let pCount: Int = row["p_count"]
            let pMaxUpd: String = row["p_max_upd"]
            let eCount: Int = row["e_count"]
            let eMaxUpd: String = row["e_max_upd"]
            let eMaxUsed: String = row["e_max_used"]
            let eSumUse: Int = row["e_sum_use"]
            let vCount: Int = row["v_count"]
            let vMaxCreated: String = row["v_max_created"]
            return "\(pCount)|\(pMaxUpd)|\(eCount)|\(eMaxUpd)|\(eMaxUsed)|\(eSumUse)|\(vCount)|\(vMaxCreated)"
        }
    }

    private static func computeLocalContentFingerprint(in db: Database) throws -> String {
        let row = try Row.fetchOne(
            db,
            sql: """
                SELECT
                    (SELECT COUNT(*) FROM projects) AS p_count,
                    (SELECT COALESCE(MAX(updated_at), '') FROM projects) AS p_max_upd,
                    (SELECT COUNT(*) FROM entries) AS e_count,
                    (SELECT COALESCE(MAX(updated_at), '') FROM entries) AS e_max_upd,
                    (SELECT COUNT(*) FROM entry_versions) AS v_count,
                    (SELECT COALESCE(MAX(created_at), '') FROM entry_versions) AS v_max_created
                """
        )
        guard let row else { return "empty" }
        let pCount: Int = row["p_count"]
        let pMaxUpd: String = row["p_max_upd"]
        let eCount: Int = row["e_count"]
        let eMaxUpd: String = row["e_max_upd"]
        let vCount: Int = row["v_count"]
        let vMaxCreated: String = row["v_max_created"]
        return "\(pCount)|\(pMaxUpd)|\(eCount)|\(eMaxUpd)|\(vCount)|\(vMaxCreated)"
    }

    func computeLocalContentFingerprint() throws -> String {
        try dbQueue.read { db in
            try Self.computeLocalContentFingerprint(in: db)
        }
    }

    /// Merges a remote sync envelope into the local database using Last-Write-Wins on `updatedAt`,
    /// while automatically archiving any overwritten local entry content into `entry_versions`,
    /// blocking abnormal mass-tombstone wipes via a high-water-mark circuit breaker, and
    /// migrating active entries whose parent project was soft-deleted remotely to the active default group.
    @discardableResult
    func mergeRemoteEnvelope(
        _ envelope: CloudSyncEnvelope,
        allowMassDeletions: Bool = false,
        syncedAt: Date = Date()
    ) throws -> CloudSyncSummary {
        let effectiveAllowMassDeletions = allowMassDeletions || (envelope.allowMassDelete == true)

        // Pre-flight inspection (read-only) to evaluate circuit breaker & throttled backup triggers
        let preflight = try dbQueue.read { db -> (
            localActiveEntries: Int,
            remoteDeletingEntries: Int,
            remoteDeletingProjects: Int,
            remoteHasMutatingChanges: Bool,
            highWaterEntries: Int
        ) in
            let localProjects = try Project.fetchAll(db)
            let localProjectsById = Dictionary(uniqueKeysWithValues: localProjects.map { ($0.id, $0) })
            let localEntries = try Entry.fetchAll(db)
            let localEntriesById = Dictionary(uniqueKeysWithValues: localEntries.map { ($0.id, $0) })

            // Exclude completed todos from mass-deletion breaker to match server semantics
            let localActiveEntries = localEntries.filter { $0.deletedAt == nil && !$0.isCompleted }.count
            let highWaterRaw = try String.fetchOne(
                db,
                sql: "SELECT value FROM sync_metadata WHERE key = ?",
                arguments: [SyncMetadataKey.highWaterActiveEntries]
            )
            let highWaterEntries = max(Int(highWaterRaw ?? "") ?? 0, localActiveEntries)

            var remoteDeletingEntries = 0
            var remoteDeletingProjects = 0
            var remoteHasMutatingChanges = false

            for remoteProject in envelope.projects {
                if let localProject = localProjectsById[remoteProject.id] {
                    if remoteProject.updatedAt > localProject.updatedAt {
                        remoteHasMutatingChanges = true
                        if localProject.deletedAt == nil && remoteProject.deletedAt != nil && !localProject.isSystemProtected {
                            remoteDeletingProjects += 1
                        }
                    }
                } else if !remoteProject.isDefault && remoteProject.deletedAt == nil {
                    remoteHasMutatingChanges = true
                }
            }

            for remoteEntry in envelope.entries {
                if let localEntry = localEntriesById[remoteEntry.id] {
                    if remoteEntry.updatedAt > localEntry.updatedAt {
                        remoteHasMutatingChanges = true
                        if localEntry.deletedAt == nil
                            && !localEntry.isCompleted
                            && remoteEntry.deletedAt != nil
                            && !remoteEntry.isCompleted {
                            remoteDeletingEntries += 1
                        }
                    }
                } else if remoteEntry.deletedAt == nil {
                    remoteHasMutatingChanges = true
                }
            }

            return (
                localActiveEntries: localActiveEntries,
                remoteDeletingEntries: remoteDeletingEntries,
                remoteDeletingProjects: remoteDeletingProjects,
                remoteHasMutatingChanges: remoteHasMutatingChanges,
                highWaterEntries: highWaterEntries
            )
        }

        let shouldBlockMassDeletions: Bool = {
            guard !effectiveAllowMassDeletions else { return false }
            let active = preflight.localActiveEntries
            let deleting = preflight.remoteDeletingEntries
            if deleting >= Constants.syncMassDeleteMinEntryCount,
               Double(deleting) / Double(max(active, 1)) >= Constants.syncMassDeleteRatioThreshold {
                return true
            }
            if active >= 2 && deleting == active {
                return true
            }
            if preflight.highWaterEntries >= Constants.syncMassDeleteMinEntryCount,
               deleting >= 2,
               (active - deleting) < Int(Double(preflight.highWaterEntries) * 0.5) {
                return true
            }
            return false
        }()

        let remoteActiveEntriesCount = envelope.entries.filter { $0.deletedAt == nil }.count
        let isGuardBackupTrigger = shouldBlockMassDeletions
            || preflight.remoteDeletingEntries > 0
            || preflight.remoteDeletingProjects > 0
            || (preflight.localActiveEntries >= Constants.syncMassDeleteMinEntryCount && remoteActiveEntriesCount == 0)

        if isGuardBackupTrigger {
            _ = try? storageMaintenanceService?.createSyncSafetyBackupIfNeeded(isGuardTrigger: true)
        } else if preflight.remoteHasMutatingChanges && preflight.localActiveEntries > 0 {
            _ = try? storageMaintenanceService?.createSyncSafetyBackupIfNeeded(isGuardTrigger: false)
        }

        var projectsCreated = 0
        var projectsUpdated = 0
        var entriesCreated = 0
        var entriesUpdated = 0
        var entriesDeleted = 0
        var mergedUsageUpdates = 0
        var mergedVersions = 0
        var conflictsPreserved = 0
        var orphansMigrated = 0
        var protectedEntriesCount = 0
        var protectedProjectsCount = 0

        try dbQueue.write { db in
            // One-shot preload to eliminate N+1 SQL queries inside merge loops
            var projectsById = Dictionary(uniqueKeysWithValues: try Project.fetchAll(db).map { ($0.id, $0) })
            var entriesById = Dictionary(uniqueKeysWithValues: try Entry.fetchAll(db).map { ($0.id, $0) })
            let allVersions = try EntryVersion.fetchAll(db)
            var versionsByEntryId: [String: [EntryVersion]] = Dictionary(grouping: allVersions, by: \.entryId)
            var versionIds = Set(allVersions.map(\.id))

            var remappedProjectIds: [String: String] = [:]
            let localDefaultProject = projectsById.values.first { $0.isDefault && $0.deletedAt == nil }
                ?? projectsById.values.first { $0.isDefault }
            let localInboxProject = projectsById.values.first { $0.groupKind == .inbox && $0.deletedAt == nil }
                ?? projectsById.values.first { $0.groupKind == .inbox }

            // 1. Merge Projects
            for remoteProject in envelope.projects {
                if let localProject = projectsById[remoteProject.id] {
                    if remoteProject.updatedAt > localProject.updatedAt {
                        var merged = remoteProject
                        if localProject.isSystemProtected {
                            merged.isDefault = localProject.isDefault
                            merged.groupKind = localProject.groupKind
                            merged.isArchived = false
                            merged.deletedAt = nil
                        } else if localProject.deletedAt == nil && remoteProject.deletedAt != nil && shouldBlockMassDeletions {
                            merged = localProject
                            merged.deletedAt = nil
                            merged.updatedAt = max(syncedAt, remoteProject.updatedAt.addingTimeInterval(1))
                            try merged.update(db)
                            projectsById[merged.id] = merged
                            protectedProjectsCount += 1
                            continue
                        }
                        try merged.update(db)
                        projectsById[merged.id] = merged
                        projectsUpdated += 1
                    }
                } else if remoteProject.isDefault, let localDefault = localDefaultProject {
                    remappedProjectIds[remoteProject.id] = localDefault.id
                } else if remoteProject.groupKind == .inbox, let localInbox = localInboxProject {
                    remappedProjectIds[remoteProject.id] = localInbox.id
                } else {
                    var toInsert = remoteProject
                    if toInsert.isSystemProtected && toInsert.deletedAt != nil {
                        toInsert.deletedAt = nil
                    }
                    try toInsert.insert(db)
                    projectsById[toInsert.id] = toInsert
                    if toInsert.deletedAt == nil {
                        projectsCreated += 1
                    }
                }
            }

            let activeDefault = projectsById.values.first { $0.isDefault && $0.deletedAt == nil }
                ?? projectsById.values.first { $0.deletedAt == nil }
            let fallbackProjectId = activeDefault?.id ?? localDefaultProject?.id ?? Constants.inboxProjectId

            func recordVersionInMemoryAndDB(_ version: EntryVersion) throws {
                try version.insert(db)
                versionIds.insert(version.id)
                versionsByEntryId[version.entryId, default: []].append(version)
            }

            // 2. Merge Entries with Conflict-to-Version-History & Mass-Deletion Circuit Breaker protection
            for var remoteEntry in envelope.entries {
                if let mappedId = remappedProjectIds[remoteEntry.projectId] {
                    remoteEntry.projectId = mappedId
                } else if projectsById[remoteEntry.projectId] == nil && remoteEntry.deletedAt == nil {
                    remoteEntry.projectId = fallbackProjectId
                    remoteEntry.updatedAt = max(syncedAt, remoteEntry.updatedAt.addingTimeInterval(0.001))
                }

                if let localEntry = entriesById[remoteEntry.id] {
                    if remoteEntry.updatedAt > localEntry.updatedAt {
                        let isRemoteDeletion = localEntry.deletedAt == nil && remoteEntry.deletedAt != nil
                        let hasContentConflict = localEntry.content != remoteEntry.content
                            || localEntry.title != remoteEntry.title

                        if hasContentConflict || isRemoteDeletion {
                            let existingVersions = versionsByEntryId[localEntry.id] ?? []
                            var nextVersion = existingVersions.map(\.versionNumber).max() ?? 0
                            let latestLocalSnapshot = existingVersions.max { $0.versionNumber < $1.versionNumber }

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
                                try recordVersionInMemoryAndDB(localBackup)
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
                                try recordVersionInMemoryAndDB(remoteSnapshot)
                            }
                        }

                        let mergedUseCount = max(localEntry.useCount, remoteEntry.useCount)
                        let mergedLastUsedAt: Date? = {
                            if let localUsed = localEntry.lastUsedAt {
                                if let remoteUsed = remoteEntry.lastUsedAt {
                                    return max(localUsed, remoteUsed)
                                }
                                return localUsed
                            }
                            return remoteEntry.lastUsedAt
                        }()

                        let isCompletedTodo = localEntry.isCompleted || remoteEntry.isCompleted
                        if isRemoteDeletion && shouldBlockMassDeletions && !isCompletedTodo {
                            var healedLocal = localEntry
                            healedLocal.deletedAt = nil
                            healedLocal.useCount = mergedUseCount
                            healedLocal.lastUsedAt = mergedLastUsedAt
                            healedLocal.updatedAt = max(syncedAt, remoteEntry.updatedAt.addingTimeInterval(1))
                            if let parent = projectsById[healedLocal.projectId], parent.deletedAt != nil, !parent.isSystemProtected {
                                healedLocal.projectId = fallbackProjectId
                            } else if projectsById[healedLocal.projectId] == nil {
                                healedLocal.projectId = fallbackProjectId
                            }
                            try healedLocal.update(db)
                            entriesById[healedLocal.id] = healedLocal
                            protectedEntriesCount += 1
                            continue
                        }

                        remoteEntry.useCount = mergedUseCount
                        remoteEntry.lastUsedAt = mergedLastUsedAt
                        try remoteEntry.update(db)
                        try EntryRepository.syncTagsIndex(
                            entryId: remoteEntry.id,
                            tags: remoteEntry.deletedAt == nil ? remoteEntry.tags : [],
                            in: db
                        )
                        entriesById[remoteEntry.id] = remoteEntry
                        entriesUpdated += 1
                        if isRemoteDeletion {
                            entriesDeleted += 1
                        }
                    } else {
                        let hasContentConflict = localEntry.content != remoteEntry.content
                            || localEntry.title != remoteEntry.title
                        if hasContentConflict {
                            let existingVersions = versionsByEntryId[localEntry.id] ?? []
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
                                try recordVersionInMemoryAndDB(remoteHistoricalSnapshot)
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
                            entriesById[updatedLocal.id] = updatedLocal
                            mergedUsageUpdates += 1
                        }
                    }
                } else {
                    try remoteEntry.insert(db)
                    entriesById[remoteEntry.id] = remoteEntry
                    if remoteEntry.deletedAt == nil {
                        try EntryRepository.syncTagsIndex(entryId: remoteEntry.id, tags: remoteEntry.tags, in: db)
                        entriesCreated += 1
                        if (versionsByEntryId[remoteEntry.id] ?? []).isEmpty {
                            let initialSnapshot = EntryVersion(
                                entryId: remoteEntry.id,
                                versionNumber: 1,
                                title: remoteEntry.title,
                                content: remoteEntry.content,
                                changeNote: "从云端同步拉取 (\(envelope.deviceId))",
                                createdAt: remoteEntry.createdAt
                            )
                            try recordVersionInMemoryAndDB(initialSnapshot)
                        }
                    }
                }
            }

            // 3. Reconcile active entries whose parent project is soft-deleted or missing:
            // System-protected groups heal; non-builtin soft-deleted groups stay deleted
            // and their orphaned active entries migrate to the active default group.
            for (entryId, var entry) in entriesById where entry.deletedAt == nil {
                if var project = projectsById[entry.projectId] {
                    if project.deletedAt != nil {
                        if project.isSystemProtected {
                            project.deletedAt = nil
                            project.updatedAt = max(syncedAt, project.updatedAt.addingTimeInterval(1))
                            try project.update(db)
                            projectsById[project.id] = project
                            protectedProjectsCount += 1
                        } else if fallbackProjectId != entry.projectId {
                            entry.projectId = fallbackProjectId
                            entry.updatedAt = max(syncedAt, entry.updatedAt.addingTimeInterval(0.001))
                            try entry.update(db)
                            entriesById[entryId] = entry
                            orphansMigrated += 1
                        }
                    }
                } else if fallbackProjectId != entry.projectId {
                    entry.projectId = fallbackProjectId
                    entry.updatedAt = max(syncedAt, entry.updatedAt.addingTimeInterval(0.001))
                    try entry.update(db)
                    entriesById[entryId] = entry
                    orphansMigrated += 1
                }
            }

            // 4. Merge Explicit Remote Version History (in-memory O(1) lookups)
            for remoteVersion in envelope.versions {
                guard entriesById[remoteVersion.entryId] != nil else { continue }
                guard !versionIds.contains(remoteVersion.id) else { continue }
                let existingVersions = versionsByEntryId[remoteVersion.entryId] ?? []
                let existsByNumber = existingVersions.contains { $0.versionNumber == remoteVersion.versionNumber }
                if !existsByNumber {
                    try recordVersionInMemoryAndDB(remoteVersion)
                    mergedVersions += 1
                } else {
                    let alreadyHasSameText = existingVersions.contains {
                        $0.content == remoteVersion.content && $0.title == remoteVersion.title
                    }
                    if !alreadyHasSameText {
                        let maxVer = existingVersions.map(\.versionNumber).max() ?? 0
                        var renumbered = remoteVersion
                        renumbered.versionNumber = maxVer + 1
                        try recordVersionInMemoryAndDB(renumbered)
                        mergedVersions += 1
                    }
                }
            }

            // 5. Persist High-Water Mark & Sync Metadata
            let currentActiveEntries = entriesById.values.filter { $0.deletedAt == nil }.count
            let currentActiveProjects = projectsById.values.filter { $0.deletedAt == nil }.count
            let updatedHighWater = max(preflight.highWaterEntries, currentActiveEntries)
            try Self.saveMeta(db, key: SyncMetadataKey.highWaterActiveEntries, value: String(updatedHighWater), date: syncedAt)
            try Self.saveMeta(db, key: SyncMetadataKey.lastSyncedActiveEntries, value: String(currentActiveEntries), date: syncedAt)
            try Self.saveMeta(db, key: SyncMetadataKey.lastSyncedActiveProjects, value: String(currentActiveProjects), date: syncedAt)

            let protectionSuffix = (protectedEntriesCount + protectedProjectsCount) > 0
                ? "，防丢拦截保护 \(protectedEntriesCount) 条/\(protectedProjectsCount) 组"
                : ""
            let summaryText = "上次同步：\(Self.summaryFormatter.string(from: syncedAt))（项目 +\(projectsCreated)/更\(projectsUpdated)，词条 +\(entriesCreated)/更\(entriesUpdated)，冲突版本保护 \(conflictsPreserved)\(protectionSuffix)）"
            try Self.saveMeta(db, key: SyncMetadataKey.lastSyncSummary, value: summaryText, date: syncedAt)
        }

        return CloudSyncSummary(
            projectsCreated: projectsCreated,
            projectsUpdated: projectsUpdated,
            entriesCreated: entriesCreated,
            entriesUpdated: entriesUpdated,
            entriesDeleted: entriesDeleted,
            mergedUsageUpdates: mergedUsageUpdates,
            mergedVersions: mergedVersions,
            conflictsPreservedInVersions: conflictsPreserved,
            orphansMigrated: orphansMigrated,
            protectedEntriesCount: protectedEntriesCount,
            protectedProjectsCount: protectedProjectsCount,
            remoteRevision: envelope.serverRevision ?? envelope.revision,
            syncedAt: syncedAt
        )
    }

    // MARK: - Trash (Recent 30 Days Soft-Deleted Entries) & Targeted Restore

    func fetchRecentSoftDeletedEntries(withinDays days: Int = 30) throws -> [SoftDeletedEntryItem] {
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(max(1, days) * 86_400))
        return try dbQueue.read { db in
            let projects = try Project.fetchAll(db)
            let projectNames = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
            let deletedEntries = try Entry
                .filter(Entry.Columns.deletedAt != nil && Entry.Columns.deletedAt >= cutoffDate)
                .order(Entry.Columns.deletedAt.desc)
                .fetchAll(db)

            return deletedEntries.compactMap { entry in
                guard let deletedAt = entry.deletedAt else { return nil }
                return SoftDeletedEntryItem(
                    id: entry.id,
                    title: entry.title,
                    previewLine: entry.previewLine,
                    projectId: entry.projectId,
                    projectName: projectNames[entry.projectId] ?? Constants.defaultProjectName,
                    type: entry.type,
                    deletedAt: deletedAt,
                    updatedAt: entry.updatedAt
                )
            }
        }
    }

    @discardableResult
    func restoreSoftDeletedEntries(ids: [String], restoredAt: Date = Date()) throws -> Int {
        let uniqueIds = Array(Set(ids)).filter { !$0.isEmpty }
        guard !uniqueIds.isEmpty else { return 0 }
        return try dbQueue.write { db in
            let activeProjects = try Project
                .filter(Project.Columns.deletedAt == nil)
                .fetchAll(db)
            let activeProjectIds = Set(activeProjects.map(\.id))
            let fallbackProjectId = activeProjects.first(where: \.isDefault)?.id
                ?? activeProjects.first?.id
                ?? Constants.inboxProjectId

            var restoredCount = 0
            for id in uniqueIds {
                guard var entry = try Entry.fetchOne(db, key: id), entry.deletedAt != nil else { continue }
                entry.deletedAt = nil
                entry.updatedAt = max(restoredAt, entry.updatedAt.addingTimeInterval(1))
                if !activeProjectIds.contains(entry.projectId) {
                    entry.projectId = fallbackProjectId
                }
                try entry.update(db)
                try EntryRepository.syncTagsIndex(entryId: entry.id, tags: entry.tags, in: db)
                restoredCount += 1
            }

            if restoredCount > 0 {
                let currentSeq = Self.fetchIntMeta(db, key: SyncMetadataKey.localMutationSeq) ?? 0
                try Self.saveMeta(db, key: SyncMetadataKey.localMutationSeq, value: String(currentSeq + 1), date: restoredAt)
            }
            return restoredCount
        }
    }

    // MARK: - Local Soft-Delete & History Self-Healing Recovery

    /// Restores any soft-deleted projects and entries in the local database (as well as any orphaned
    /// `entry_versions` snapshots whose parent entry row is missing) by clearing `deletedAt` and
    /// bumping `updatedAt`, so they become immediately visible and outrank stale remote tombstones.
    @discardableResult
    func recoverLocalSoftDeletedRecords(restoredAt: Date = Date()) throws -> (projectsRestored: Int, entriesRestored: Int) {
        _ = try? storageMaintenanceService?.createSyncSafetyBackupIfNeeded(isGuardTrigger: true)
        return try dbQueue.write { db in
            var projectsRestored = 0
            var entriesRestored = 0

            let deletedProjects = try Project
                .filter(Project.Columns.deletedAt != nil)
                .fetchAll(db)
            for var project in deletedProjects {
                let bumpDate = max(restoredAt, project.updatedAt.addingTimeInterval(1))
                project.deletedAt = nil
                project.updatedAt = bumpDate
                try project.update(db)
                projectsRestored += 1
            }

            let localDefaultProject = try Project
                .filter(Project.Columns.isDefault == true)
                .fetchOne(db)
            let fallbackProjectId = localDefaultProject?.id ?? Constants.inboxProjectId
            let activeProjectIds = Set(try String.fetchAll(db, sql: "SELECT id FROM projects WHERE deleted_at IS NULL"))

            let deletedEntries = try Entry
                .filter(Entry.Columns.deletedAt != nil)
                .fetchAll(db)
            for var entry in deletedEntries {
                let bumpDate = max(restoredAt, entry.updatedAt.addingTimeInterval(1))
                entry.deletedAt = nil
                entry.updatedAt = bumpDate
                if !activeProjectIds.contains(entry.projectId) {
                    entry.projectId = fallbackProjectId
                }
                try entry.update(db)
                try EntryRepository.syncTagsIndex(entryId: entry.id, tags: entry.tags, in: db)
                entriesRestored += 1
            }

            // Also reconstruct any entry whose versions still exist in entry_versions but whose entry row was missing
            let orphanedEntryIds = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT entry_id
                    FROM entry_versions
                    WHERE entry_id NOT IN (SELECT id FROM entries)
                    """
            )
            for orphanEntryId in orphanedEntryIds {
                if let latestVer = try EntryVersion
                    .filter(EntryVersion.Columns.entryId == orphanEntryId)
                    .order(EntryVersion.Columns.versionNumber.desc)
                    .fetchOne(db) {
                    let reconstructed = Entry(
                        id: orphanEntryId,
                        projectId: fallbackProjectId,
                        title: latestVer.title,
                        content: latestVer.content,
                        type: Constants.EntryType.prompt.rawValue,
                        createdAt: latestVer.createdAt,
                        updatedAt: restoredAt
                    )
                    try reconstructed.insert(db)
                    entriesRestored += 1
                }
            }

            return (projectsRestored: projectsRestored, entriesRestored: entriesRestored)
        }
    }

    /// Restores soft-deleted local records and, if a cloud sync endpoint is configured, pushes the
    /// healed local library back to the cloud.
    func recoverDeletedAndSync(
        endpoint: String,
        apiKey: String
    ) async throws -> (projectsRestored: Int, entriesRestored: Int, syncSummary: CloudSyncSummary?) {
        try acquireSyncSlot()
        defer { releaseSyncSlot() }
        let restored = try recoverLocalSoftDeletedRecords()
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return (restored.projectsRestored, restored.entriesRestored, nil)
        }
        let summary = try await syncNowUnlocked(endpoint: trimmed, apiKey: apiKey)
        return (restored.projectsRestored, restored.entriesRestored, summary)
    }

    // MARK: - Sync Execution (File / Cloud Drive or HTTPS Endpoint)

    static func isAllowedRemoteHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let rawHost = url.host?.lowercased(),
              !rawHost.isEmpty else {
            return false
        }
        if scheme == "https" {
            return true
        }
        if scheme == "http" {
            let normalizedHost = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return normalizedHost == "localhost"
                || normalizedHost == "127.0.0.1"
                || normalizedHost == "::1"
        }
        return false
    }

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

    func testConnection(endpoint: String, apiKey: String) async throws -> CloudSyncHealthReport {
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
            guard Self.isAllowedRemoteHTTPURL(healthURL) else {
                throw CloudSyncError.invalidEndpoint("为保护同步数据与 Token 安全，远程同步仅允许 https:// 地址（仅本机回环允许 http://localhost 或 http://127.0.0.1）")
            }

            var request = URLRequest(url: healthURL, timeoutInterval: 10)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if !apiKey.isEmpty {
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await performAsyncRequest(request)
            let latencyMs = max(Int((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000), 1)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw CloudSyncError.networkFailure(
                    Self.friendlyHTTPErrorMessage(statusCode: code, responseData: data)
                )
            }

            if !data.isEmpty, Self.looksLikeHTMLPayload(data) {
                throw CloudSyncError.invalidPayload("远端返回了网页而非健康检查 JSON（请检查同步地址或反向代理路径）")
            }
            let parsedObject = data.isEmpty ? [:] : (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            guard let json = parsedObject else {
                throw CloudSyncError.invalidPayload("远端未返回有效的 JSON 响应，请检查同步服务地址")
            }
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

    func syncNow(
        endpoint: String,
        apiKey: String,
        actionMode: CloudSyncActionMode = .smartBidirectional,
        allowMassDelete: Bool = false,
        forceFullSync: Bool = false,
        isAutoSync: Bool = false
    ) async throws -> CloudSyncSummary {
        try acquireSyncSlot()
        defer { releaseSyncSlot() }
        return try await syncNowUnlocked(
            endpoint: endpoint,
            apiKey: apiKey,
            actionMode: actionMode,
            allowMassDelete: allowMassDelete,
            forceFullSync: forceFullSync,
            isAutoSync: isAutoSync
        )
    }

    func syncWithReport(
        endpoint: String,
        apiKey: String,
        actionMode: CloudSyncActionMode = .smartBidirectional,
        allowMassDelete: Bool = false,
        forceFullSync: Bool = false,
        isAutoSync: Bool = false
    ) async throws -> CloudSyncReport {
        let summary = try await syncNow(
            endpoint: endpoint,
            apiKey: apiKey,
            actionMode: actionMode,
            allowMassDelete: allowMassDelete,
            forceFullSync: forceFullSync,
            isAutoSync: isAutoSync
        )
        if let report = summary.report {
            return report
        }
        if let stored = try lastSyncReport() {
            return stored
        }
        let devId = (try? deviceId()) ?? "mac-local"
        let pending = try? pendingSyncState()
        return CloudSyncReport(
            schemaVersion: CloudSyncEnvelope.currentSchemaVersion,
            isAutoSync: isAutoSync,
            modeLabel: isAutoSync ? "自动同步" : "手动模式",
            actionMode: actionMode,
            direction: summary.direction,
            channelKind: endpoint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("http") ? "https" : "local-file",
            deviceId: devId,
            remoteRevision: summary.remoteRevision,
            pulledProjectsCreated: summary.projectsCreated,
            pulledProjectsUpdated: summary.projectsUpdated,
            pulledEntriesCreated: summary.entriesCreated,
            pulledEntriesUpdated: summary.entriesUpdated,
            pulledDeletionsCount: summary.entriesDeleted,
            pushedChangesCount: summary.pushedChangesCount,
            skippedPushReason: nil,
            conflictsPreserved: summary.conflictsPreservedInVersions,
            orphansMigrated: summary.orphansMigrated,
            protectedEntriesCount: summary.protectedEntriesCount,
            protectedProjectsCount: summary.protectedProjectsCount,
            hasPendingLocalChanges: pending?.hasPendingLocalChanges ?? false,
            pendingLocalMutationDelta: pending?.pendingDelta ?? 0,
            syncedAt: summary.syncedAt,
            errorMessage: nil,
            summaryText: (try? lastSyncStatus()) ?? ""
        )
    }

    private func syncNowUnlocked(
        endpoint: String,
        apiKey: String,
        actionMode: CloudSyncActionMode = .smartBidirectional,
        allowMassDelete: Bool = false,
        forceFullSync: Bool = false,
        isAutoSync: Bool = false
    ) async throws -> CloudSyncSummary {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CloudSyncError.endpointNotConfigured
        }

        let armedMassDelete = consumeArmedAllowMassDelete()
        let pendingMassDelete = try hasPendingAllowMassDelete()
        let effectiveAllowMassDelete = allowMassDelete || armedMassDelete || pendingMassDelete || (actionMode == .forcePushLocal)

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
            guard Self.isAllowedRemoteHTTPURL(url) else {
                throw CloudSyncError.invalidEndpoint("为保护同步数据与 Token 安全，远程同步仅允许 https:// 地址（仅本机回环允许 http://localhost 或 http://127.0.0.1）")
            }
            return try await syncViaHTTP(
                url: url,
                apiKey: apiKey,
                actionMode: actionMode,
                allowMassDelete: effectiveAllowMassDelete,
                forceFullSync: forceFullSync,
                isAutoSync: isAutoSync
            )
        } else {
            let fileURL: URL
            if trimmed.hasPrefix("file://"), let parsed = URL(string: trimmed) {
                fileURL = parsed
            } else {
                let expanded = NSString(string: trimmed).expandingTildeInPath
                fileURL = URL(fileURLWithPath: expanded)
            }
            return try syncViaFile(
                fileURL: fileURL,
                apiKey: apiKey,
                actionMode: actionMode,
                allowMassDelete: effectiveAllowMassDelete,
                isAutoSync: isAutoSync
            )
        }
    }

    private func hasPendingAllowMassDelete() throws -> Bool {
        try dbQueue.read { db in
            let raw = try String.fetchOne(
                db,
                sql: "SELECT value FROM sync_metadata WHERE key = ?",
                arguments: [SyncMetadataKey.pendingAllowMassDelete]
            )
            return raw == "1"
        }
    }

    private static func syncTargetKey(url: URL, apiKey: String) -> String {
        let digest = SHA256.hash(data: Data("\(url.absoluteString)|\(apiKey)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileTargetKey(url: URL, apiKey: String) -> String {
        let digest = SHA256.hash(data: Data("file:\(url.standardizedFileURL.path)|\(apiKey)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct LocalSyncCursorState {
        let localSeq: Int
        let lastSyncedSeq: Int
        let lastSyncedRevision: Int?
        let lastSyncedTargetKey: String?
        let lastSyncedContentFP: String?
        let lastSyncedStateFP: String?
        let usageDirty: Bool
        let currentContentFP: String
        let currentStateFP: String
    }

    private func readLocalSyncCursorState() throws -> LocalSyncCursorState {
        try dbQueue.read { db in
            let localSeq = Self.fetchIntMeta(db, key: SyncMetadataKey.localMutationSeq) ?? 0
            let lastSyncedSeq = Self.fetchIntMeta(db, key: SyncMetadataKey.lastSyncedMutationSeq) ?? 0
            let lastRev = Self.fetchIntMeta(db, key: SyncMetadataKey.lastSyncedRevision)
            let lastTarget = Self.fetchStringMeta(db, key: SyncMetadataKey.lastSyncedTargetKey)
            let lastContentFP = Self.fetchStringMeta(db, key: SyncMetadataKey.lastSyncedContentFingerprint)
            let lastStateFP = Self.fetchStringMeta(db, key: SyncMetadataKey.lastSyncedFingerprint)
            let usageDirty = Self.fetchStringMeta(db, key: SyncMetadataKey.usageDirty) == "1"
            let currentContentFP = try Self.computeLocalContentFingerprint(in: db)
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT
                        (SELECT COUNT(*) FROM projects) AS p_count,
                        (SELECT COALESCE(MAX(updated_at), '') FROM projects) AS p_max_upd,
                        (SELECT COUNT(*) FROM entries) AS e_count,
                        (SELECT COALESCE(MAX(updated_at), '') FROM entries) AS e_max_upd,
                        (SELECT COALESCE(MAX(last_used_at), '') FROM entries) AS e_max_used,
                        (SELECT COALESCE(SUM(use_count), 0) FROM entries) AS e_sum_use,
                        (SELECT COUNT(*) FROM entry_versions) AS v_count,
                        (SELECT COALESCE(MAX(created_at), '') FROM entry_versions) AS v_max_created
                    """
            )
            let currentStateFP: String = {
                guard let row else { return "empty" }
                let pCount: Int = row["p_count"]
                let pMaxUpd: String = row["p_max_upd"]
                let eCount: Int = row["e_count"]
                let eMaxUpd: String = row["e_max_upd"]
                let eMaxUsed: String = row["e_max_used"]
                let eSumUse: Int = row["e_sum_use"]
                let vCount: Int = row["v_count"]
                let vMaxCreated: String = row["v_max_created"]
                return "\(pCount)|\(pMaxUpd)|\(eCount)|\(eMaxUpd)|\(eMaxUsed)|\(eSumUse)|\(vCount)|\(vMaxCreated)"
            }()
            return LocalSyncCursorState(
                localSeq: localSeq,
                lastSyncedSeq: lastSyncedSeq,
                lastSyncedRevision: lastRev,
                lastSyncedTargetKey: lastTarget,
                lastSyncedContentFP: lastContentFP,
                lastSyncedStateFP: lastStateFP,
                usageDirty: usageDirty,
                currentContentFP: currentContentFP,
                currentStateFP: currentStateFP
            )
        }
    }

    private func buildAndPersistReport(
        isAutoSync: Bool,
        actionMode: CloudSyncActionMode,
        direction: CloudSyncDirection,
        channelKind: String,
        deviceId: String,
        remoteRevision: Int?,
        summary: CloudSyncSummary,
        pushedChangesCount: Int,
        skippedPushReason: String?,
        targetKey: String,
        advanceSyncCursorToSeq: Int?,
        advanceSyncContentFP: String?,
        advanceSyncStateFP: String?,
        clearUsageDirty: Bool,
        clearPendingMassDelete: Bool,
        errorMessage: String? = nil
    ) throws -> CloudSyncReport {
        let encoder = Self.makeEncoder()
        return try dbQueue.write { db in
            if let seq = advanceSyncCursorToSeq {
                try Self.saveMeta(db, key: SyncMetadataKey.lastSyncedMutationSeq, value: String(seq), date: summary.syncedAt)
            }
            if let fp = advanceSyncContentFP {
                try Self.saveMeta(db, key: SyncMetadataKey.lastSyncedContentFingerprint, value: fp, date: summary.syncedAt)
            }
            if let sfp = advanceSyncStateFP {
                try Self.saveMeta(db, key: SyncMetadataKey.lastSyncedFingerprint, value: sfp, date: summary.syncedAt)
            }
            try Self.saveMeta(db, key: SyncMetadataKey.lastSyncedTargetKey, value: targetKey, date: summary.syncedAt)
            if let rev = remoteRevision {
                try Self.saveMeta(db, key: SyncMetadataKey.lastSyncedRevision, value: String(rev), date: summary.syncedAt)
            }
            if clearUsageDirty {
                try Self.saveMeta(db, key: SyncMetadataKey.usageDirty, value: "0", date: summary.syncedAt)
            }
            if clearPendingMassDelete {
                try db.execute(
                    sql: "DELETE FROM sync_metadata WHERE key IN (?, 'pending_user_delete_count')",
                    arguments: [SyncMetadataKey.pendingAllowMassDelete]
                )
            }

            let localSeqNow = Self.fetchIntMeta(db, key: SyncMetadataKey.localMutationSeq) ?? 0
            let syncedSeqNow = Self.fetchIntMeta(db, key: SyncMetadataKey.lastSyncedMutationSeq) ?? 0
            let lastContentFPNow = Self.fetchStringMeta(db, key: SyncMetadataKey.lastSyncedContentFingerprint)
            let currentContentFPNow = try Self.computeLocalContentFingerprint(in: db)
            let seqDelta = max(0, localSeqNow - syncedSeqNow)
            let hasPending = seqDelta > 0 || (lastContentFPNow != nil && lastContentFPNow != currentContentFPNow)

            let delSuffix = summary.entriesDeleted > 0 ? "/删\(summary.entriesDeleted)" : ""
            let protectionSuffix = summary.totalProtectedCount > 0
                ? "，防丢保护 \(summary.protectedEntriesCount) 条/\(summary.protectedProjectsCount) 组"
                : ""
            let orphanSuffix = summary.orphansMigrated > 0
                ? "，孤儿迁移 \(summary.orphansMigrated)"
                : ""
            let revSuffix = remoteRevision.map { "r\($0)" } ?? "--"
            let pushDesc = pushedChangesCount > 0
                ? "推送 \(pushedChangesCount) 项"
                : (skippedPushReason ?? "未推送")
            let summaryText: String
            if let errorMessage, !errorMessage.isEmpty {
                summaryText = "同步异常（\(Self.summaryFormatter.string(from: summary.syncedAt))）：\(errorMessage)"
            } else if direction == .alignedNoChange {
                summaryText = "上次同步：\(Self.summaryFormatter.string(from: summary.syncedAt))（\(direction.displayName) · \(revSuffix)）"
            } else {
                summaryText = "上次同步：\(Self.summaryFormatter.string(from: summary.syncedAt))（\(direction.displayName) · \(revSuffix) · 项目 +\(summary.projectsCreated)/更\(summary.projectsUpdated)，词条 +\(summary.entriesCreated)/更\(summary.entriesUpdated)\(delSuffix)，\(pushDesc)，冲突留存 \(summary.conflictsPreservedInVersions)\(protectionSuffix)\(orphanSuffix)）"
            }
            try Self.saveMeta(db, key: SyncMetadataKey.lastSyncSummary, value: summaryText, date: summary.syncedAt)

            let report = CloudSyncReport(
                schemaVersion: CloudSyncEnvelope.currentSchemaVersion,
                isAutoSync: isAutoSync,
                modeLabel: isAutoSync ? "自动同步" : "手动模式",
                actionMode: actionMode,
                direction: direction,
                channelKind: channelKind,
                deviceId: deviceId,
                remoteRevision: remoteRevision,
                pulledProjectsCreated: summary.projectsCreated,
                pulledProjectsUpdated: summary.projectsUpdated,
                pulledEntriesCreated: summary.entriesCreated,
                pulledEntriesUpdated: summary.entriesUpdated,
                pulledDeletionsCount: summary.entriesDeleted,
                pushedChangesCount: pushedChangesCount,
                skippedPushReason: skippedPushReason,
                conflictsPreserved: summary.conflictsPreservedInVersions,
                orphansMigrated: summary.orphansMigrated,
                protectedEntriesCount: summary.protectedEntriesCount,
                protectedProjectsCount: summary.protectedProjectsCount,
                hasPendingLocalChanges: hasPending,
                pendingLocalMutationDelta: max(seqDelta, hasPending ? 1 : 0),
                syncedAt: summary.syncedAt,
                errorMessage: errorMessage,
                summaryText: summaryText
            )
            if let reportData = try? encoder.encode(report),
               let reportJSON = String(data: reportData, encoding: .utf8) {
                try Self.saveMeta(db, key: SyncMetadataKey.lastSyncReportJson, value: reportJSON, date: summary.syncedAt)
            }
            return report
        }
    }

    private func coordinatedReadFile(at fileURL: URL) throws -> (data: Data?, modDate: Date?, sha256: String?) {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var readResult: Result<(Data?, Date?, String?), Error> = .success((nil, nil, nil))

        coordinator.coordinate(readingItemAt: fileURL, options: .withoutChanges, error: &coordError) { actualURL in
            do {
                guard FileManager.default.fileExists(atPath: actualURL.path) else {
                    readResult = .success((nil, nil, nil))
                    return
                }
                let data = try Data(contentsOf: actualURL)
                let attrs = try? FileManager.default.attributesOfItem(atPath: actualURL.path)
                let modDate = attrs?[.modificationDate] as? Date
                let hash = Self.sha256Hex(data)
                readResult = .success((data, modDate, hash))
            } catch {
                readResult = .failure(error)
            }
        }
        if let coordError {
            throw CloudSyncError.networkFailure(coordError.localizedDescription)
        }
        return try readResult.get()
    }

    private func syncViaFile(
        fileURL: URL,
        apiKey: String = "",
        actionMode: CloudSyncActionMode = .smartBidirectional,
        allowMassDelete: Bool = false,
        isAutoSync: Bool = false
    ) throws -> CloudSyncSummary {
        let encoder = Self.makeEncoder()
        let decoder = Self.makeDecoder()
        let devId = try deviceId()
        let targetKey = Self.fileTargetKey(url: fileURL, apiKey: apiKey)
        let preCursor = try readLocalSyncCursorState()
        let hasLocalChangesBeforeSync = (preCursor.localSeq != preCursor.lastSyncedSeq)
            || (preCursor.lastSyncedTargetKey != targetKey)
            || (preCursor.lastSyncedContentFP == nil)
            || (preCursor.currentContentFP != preCursor.lastSyncedContentFP)

        let parentDir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parentDir.path) {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }

        let initialRead = try coordinatedReadFile(at: fileURL)
        var baselineHash = initialRead.sha256
        var summary: CloudSyncSummary
        var remoteHadFewerActiveEntries = false
        let remoteWasMissingOrEmpty = (initialRead.data == nil || initialRead.data?.isEmpty == true)

        if actionMode == .forcePushLocal {
            summary = CloudSyncSummary(
                projectsCreated: 0,
                projectsUpdated: 0,
                entriesCreated: 0,
                entriesUpdated: 0,
                conflictsPreservedInVersions: 0,
                actionMode: actionMode,
                direction: .forcedLocalOverwrite,
                syncedAt: Date()
            )
        } else if let rawData = initialRead.data, !rawData.isEmpty {
            do {
                let openedData = try CloudSyncCrypto.openEnvelopeData(rawData, apiKey: apiKey)
                let remoteEnvelope = try decoder.decode(CloudSyncEnvelope.self, from: openedData)
                let localActiveCount = try dbQueue.read { db in
                    try Entry.filter(Entry.Columns.deletedAt == nil).fetchCount(db)
                }
                let remoteActiveCount = remoteEnvelope.entries.filter { $0.deletedAt == nil }.count
                remoteHadFewerActiveEntries = remoteActiveCount < localActiveCount
                summary = try mergeRemoteEnvelope(remoteEnvelope, allowMassDeletions: allowMassDelete)
            } catch let syncErr as CloudSyncError {
                throw syncErr
            } catch {
                throw CloudSyncError.invalidPayload(
                    Self.friendlyPayloadErrorMessage(for: rawData, underlyingError: error)
                )
            }
        } else {
            summary = try mergeRemoteEnvelope(buildLocalEnvelope(), allowMassDeletions: allowMassDelete)
        }

        let postMergeCursor = try readLocalSyncCursorState()
        let needsHealPush = (summary.totalProtectedCount > 0) || (summary.orphansMigrated > 0)
        let hadConcurrentEdit = (postMergeCursor.localSeq != preCursor.localSeq)
        let shouldWriteFile = actionMode != .pullOnly && (
            actionMode == .forcePushLocal
                || remoteWasMissingOrEmpty
                || remoteHadFewerActiveEntries
                || hasLocalChangesBeforeSync
                || hadConcurrentEdit
                || needsHealPush
                || allowMassDelete
                || (!isAutoSync && (preCursor.usageDirty || postMergeCursor.usageDirty))
                || (preCursor.lastSyncedStateFP != postMergeCursor.currentStateFP && !isAutoSync)
        )

        var pushedChangesCount = 0
        var skippedReason: String? = actionMode == .pullOnly ? "仅拉取模式" : nil

        if shouldWriteFile {
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordError: NSError?
            var writeResult: Result<Int, Error> = .success(0)

            coordinator.coordinate(
                readingItemAt: fileURL,
                options: .withoutChanges,
                writingItemAt: fileURL,
                options: .forReplacing,
                error: &coordError
            ) { readURL, writeURL in
                do {
                    if actionMode == .smartBidirectional,
                       FileManager.default.fileExists(atPath: readURL.path),
                       let diskData = try? Data(contentsOf: readURL),
                       !diskData.isEmpty {
                        let diskHash = Self.sha256Hex(diskData)
                        if diskHash != baselineHash {
                            let opened = try CloudSyncCrypto.openEnvelopeData(diskData, apiKey: apiKey)
                            let newerRemote = try decoder.decode(CloudSyncEnvelope.self, from: opened)
                            let remerge = try self.mergeRemoteEnvelope(newerRemote, allowMassDeletions: allowMassDelete)
                            summary = CloudSyncSummary(
                                projectsCreated: summary.projectsCreated + remerge.projectsCreated,
                                projectsUpdated: summary.projectsUpdated + remerge.projectsUpdated,
                                entriesCreated: summary.entriesCreated + remerge.entriesCreated,
                                entriesUpdated: summary.entriesUpdated + remerge.entriesUpdated,
                                entriesDeleted: summary.entriesDeleted + remerge.entriesDeleted,
                                mergedUsageUpdates: summary.mergedUsageUpdates + remerge.mergedUsageUpdates,
                                mergedVersions: summary.mergedVersions + remerge.mergedVersions,
                                conflictsPreservedInVersions: summary.conflictsPreservedInVersions + remerge.conflictsPreservedInVersions,
                                orphansMigrated: summary.orphansMigrated + remerge.orphansMigrated,
                                protectedEntriesCount: summary.protectedEntriesCount + remerge.protectedEntriesCount,
                                protectedProjectsCount: summary.protectedProjectsCount + remerge.protectedProjectsCount,
                                syncedAt: remerge.syncedAt
                            )
                            baselineHash = diskHash
                        }
                    }

                    let mergedEnvelope = try self.buildLocalEnvelope(
                        allowMassDelete: allowMassDelete,
                        forceOverwrite: actionMode == .forcePushLocal
                    )
                    let encoded = try encoder.encode(mergedEnvelope)
                    let sealed = try CloudSyncCrypto.sealEnvelopeData(encoded, apiKey: apiKey)
                    try sealed.write(to: writeURL, options: .atomic)
                    writeResult = .success(mergedEnvelope.entries.count + mergedEnvelope.projects.count)
                } catch {
                    writeResult = .failure(error)
                }
            }
            if let coordError {
                throw CloudSyncError.networkFailure(coordError.localizedDescription)
            }
            pushedChangesCount = try writeResult.get()
        } else if skippedReason == nil {
            skippedReason = "本地无新变更，未写入"
        }

        let afterWriteCursor = try readLocalSyncCursorState()
        let noConcurrentEditDuringWrite = (afterWriteCursor.localSeq == postMergeCursor.localSeq)
        let direction: CloudSyncDirection = {
            if actionMode == .forcePushLocal { return .forcedLocalOverwrite }
            if actionMode == .pullOnly { return .pulledOnly }
            if pushedChangesCount == 0 && !summary.hasAnyLocalMutation { return .alignedNoChange }
            if pushedChangesCount == 0 { return .pulledOnly }
            if !summary.hasAnyLocalMutation { return .pushedOnly }
            return .bidirectional
        }()

        let report = try buildAndPersistReport(
            isAutoSync: isAutoSync,
            actionMode: actionMode,
            direction: direction,
            channelKind: "local-file",
            deviceId: devId,
            remoteRevision: nil,
            summary: summary,
            pushedChangesCount: pushedChangesCount,
            skippedPushReason: skippedReason,
            targetKey: targetKey,
            advanceSyncCursorToSeq: (shouldWriteFile && noConcurrentEditDuringWrite) ? postMergeCursor.localSeq : (shouldWriteFile ? nil : postMergeCursor.localSeq),
            advanceSyncContentFP: (shouldWriteFile && noConcurrentEditDuringWrite) ? postMergeCursor.currentContentFP : (shouldWriteFile ? nil : postMergeCursor.currentContentFP),
            advanceSyncStateFP: (shouldWriteFile && noConcurrentEditDuringWrite) ? postMergeCursor.currentStateFP : nil,
            clearUsageDirty: shouldWriteFile && noConcurrentEditDuringWrite,
            clearPendingMassDelete: allowMassDelete && shouldWriteFile
        )

        return CloudSyncSummary(
            projectsCreated: summary.projectsCreated,
            projectsUpdated: summary.projectsUpdated,
            entriesCreated: summary.entriesCreated,
            entriesUpdated: summary.entriesUpdated,
            entriesDeleted: summary.entriesDeleted,
            mergedUsageUpdates: summary.mergedUsageUpdates,
            mergedVersions: summary.mergedVersions,
            conflictsPreservedInVersions: summary.conflictsPreservedInVersions,
            orphansMigrated: summary.orphansMigrated,
            protectedEntriesCount: summary.protectedEntriesCount,
            protectedProjectsCount: summary.protectedProjectsCount,
            pushedChangesCount: pushedChangesCount,
            remoteRevision: nil,
            actionMode: actionMode,
            direction: direction,
            report: report,
            syncedAt: summary.syncedAt
        )
    }

    private func syncViaHTTP(
        url: URL,
        apiKey: String,
        actionMode: CloudSyncActionMode = .smartBidirectional,
        allowMassDelete: Bool = false,
        forceFullSync: Bool = false,
        isAutoSync: Bool = false
    ) async throws -> CloudSyncSummary {
        let encoder = Self.makeEncoder()
        let decoder = Self.makeDecoder()
        let devId = try deviceId()
        let targetKey = Self.syncTargetKey(url: url, apiKey: apiKey)
        let preCursor = try readLocalSyncCursorState()
        let hasLocalChangesBeforeSync = (preCursor.localSeq != preCursor.lastSyncedSeq)
            || (preCursor.lastSyncedTargetKey != targetKey)
            || (preCursor.lastSyncedContentFP == nil)
            || (preCursor.currentContentFP != preCursor.lastSyncedContentFP)

        var summary = CloudSyncSummary(
            projectsCreated: 0,
            projectsUpdated: 0,
            entriesCreated: 0,
            entriesUpdated: 0,
            conflictsPreservedInVersions: 0,
            actionMode: actionMode,
            direction: .alignedNoChange,
            syncedAt: Date()
        )
        var remoteRevision: Int? = (preCursor.lastSyncedTargetKey == targetKey) ? preCursor.lastSyncedRevision : nil
        var remoteServerWasEmptyOr404 = false

        if actionMode != .forcePushLocal {
            let canUseFastPoll = !forceFullSync
                && !allowMassDelete
                && actionMode == .smartBidirectional
                && preCursor.lastSyncedTargetKey == targetKey
                && preCursor.lastSyncedRevision != nil
                && !hasLocalChangesBeforeSync

            let getURL: URL = {
                guard canUseFastPoll,
                      let rev = preCursor.lastSyncedRevision,
                      var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    return url
                }
                var items = comps.queryItems ?? []
                items.removeAll { $0.name == "since_revision" }
                items.append(URLQueryItem(name: "since_revision", value: String(rev)))
                comps.queryItems = items
                return comps.url ?? url
            }()

            // 1. Pull remote envelope (GET)
            var getRequest = URLRequest(url: getURL, timeoutInterval: 15)
            getRequest.httpMethod = "GET"
            getRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            if !apiKey.isEmpty {
                getRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                getRequest.setValue("aes-256-gcm+gzip", forHTTPHeaderField: "X-PromptPanel-Cipher")
            }

            let (getData, getResponse) = try await performAsyncRequest(getRequest)
            if let httpResponse = getResponse as? HTTPURLResponse {
                if httpResponse.statusCode == 401 {
                    throw CloudSyncError.networkFailure("Token 鉴权未通过 (HTTP 401)，请确认已填写不少于 12 位的专属 Token")
                }
                if !(200..<300).contains(httpResponse.statusCode) && httpResponse.statusCode != 404 {
                    throw CloudSyncError.networkFailure(
                        Self.friendlyHTTPErrorMessage(statusCode: httpResponse.statusCode, responseData: getData)
                    )
                }
            }

            if let httpResponse = getResponse as? HTTPURLResponse,
               (200..<300).contains(httpResponse.statusCode),
               !getData.isEmpty {
                do {
                    let openedGetData = try CloudSyncCrypto.openEnvelopeData(getData, apiKey: apiKey)
                    let remoteEnvelope = try decoder.decode(CloudSyncEnvelope.self, from: openedGetData)
                    remoteRevision = remoteEnvelope.serverRevision ?? remoteEnvelope.revision ?? remoteRevision
                    if canUseFastPoll && remoteEnvelope.unchanged == true {
                        let cursorNow = try readLocalSyncCursorState()
                        let editedDuringPoll = (cursorNow.localSeq != preCursor.localSeq) || (cursorNow.currentContentFP != preCursor.currentContentFP)
                        let shouldPushUsageNow = !isAutoSync && (preCursor.usageDirty || cursorNow.usageDirty)
                        if !editedDuringPoll && !shouldPushUsageNow {
                            let report = try buildAndPersistReport(
                                isAutoSync: isAutoSync,
                                actionMode: actionMode,
                                direction: .alignedNoChange,
                                channelKind: "https",
                                deviceId: devId,
                                remoteRevision: remoteRevision,
                                summary: summary,
                                pushedChangesCount: 0,
                                skippedPushReason: "云端与本地均无新变更",
                                targetKey: targetKey,
                                advanceSyncCursorToSeq: cursorNow.localSeq,
                                advanceSyncContentFP: cursorNow.currentContentFP,
                                advanceSyncStateFP: cursorNow.currentStateFP,
                                clearUsageDirty: false,
                                clearPendingMassDelete: false
                            )
                            return CloudSyncSummary(
                                projectsCreated: 0,
                                projectsUpdated: 0,
                                entriesCreated: 0,
                                entriesUpdated: 0,
                                conflictsPreservedInVersions: 0,
                                remoteRevision: remoteRevision,
                                actionMode: actionMode,
                                direction: .alignedNoChange,
                                report: report,
                                syncedAt: report.syncedAt
                            )
                        }
                    } else {
                        summary = try mergeRemoteEnvelope(remoteEnvelope, allowMassDeletions: allowMassDelete)
                    }
                } catch let syncErr as CloudSyncError {
                    throw syncErr
                } catch {
                    throw CloudSyncError.invalidPayload(
                        Self.friendlyPayloadErrorMessage(for: getData, underlyingError: error)
                    )
                }
            } else {
                remoteServerWasEmptyOr404 = true
                summary = try mergeRemoteEnvelope(buildLocalEnvelope(), allowMassDeletions: allowMassDelete)
            }
        }

        let postMergeCursor = try readLocalSyncCursorState()
        let needsHealPush = (summary.totalProtectedCount > 0) || (summary.orphansMigrated > 0)
        let hadConcurrentEditDuringGet = (postMergeCursor.localSeq != preCursor.localSeq)
        let shouldPush: Bool = {
            if actionMode == .pullOnly { return false }
            if actionMode == .forcePushLocal { return true }
            return hasLocalChangesBeforeSync
                || hadConcurrentEditDuringGet
                || needsHealPush
                || allowMassDelete
                || remoteServerWasEmptyOr404
                || remoteRevision == nil
                || (!isAutoSync && (preCursor.usageDirty || postMergeCursor.usageDirty))
        }()

        var pushedChangesCount = 0
        var skippedPushReason: String? = actionMode == .pullOnly ? "仅拉取模式，未推送本地" : nil
        var seqCapturedBeforePost = postMergeCursor.localSeq
        var contentFPCapturedBeforePost = postMergeCursor.currentContentFP
        var stateFPCapturedBeforePost = postMergeCursor.currentStateFP

        if shouldPush {
            // 2. Conditional Push (POST) with strictConflict + 409 Pull-Merge-Retry loop (max 2 retries)
            for attempt in 0..<3 {
                let beforePostCursor = try readLocalSyncCursorState()
                seqCapturedBeforePost = beforePostCursor.localSeq
                contentFPCapturedBeforePost = beforePostCursor.currentContentFP
                stateFPCapturedBeforePost = beforePostCursor.currentStateFP

                let mergedEnvelope = try buildLocalEnvelope(
                    allowMassDelete: allowMassDelete,
                    expectedRevision: remoteRevision,
                    strictConflict: actionMode == .smartBidirectional && remoteRevision != nil,
                    forceOverwrite: actionMode == .forcePushLocal
                )
                var postRequest = URLRequest(url: url, timeoutInterval: 15)
                postRequest.httpMethod = "POST"
                postRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                postRequest.setValue("application/json", forHTTPHeaderField: "Accept")
                if let rev = remoteRevision, actionMode == .smartBidirectional {
                    postRequest.setValue("\"rev-\(rev)\"", forHTTPHeaderField: "If-Match")
                }
                if !apiKey.isEmpty {
                    postRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    postRequest.setValue("aes-256-gcm+gzip", forHTTPHeaderField: "X-PromptPanel-Cipher")
                }
                let rawPostBody = try encoder.encode(mergedEnvelope)
                postRequest.httpBody = try CloudSyncCrypto.sealEnvelopeData(rawPostBody, apiKey: apiKey)

                let (postData, postResponse) = try await performAsyncRequest(postRequest)
                let statusCode = (postResponse as? HTTPURLResponse)?.statusCode ?? 0

                if statusCode == 409 && attempt < 2 && actionMode == .smartBidirectional {
                    if !postData.isEmpty {
                        let openedConflict = try CloudSyncCrypto.openEnvelopeData(postData, apiKey: apiKey)
                        let conflictEnv = try decoder.decode(CloudSyncEnvelope.self, from: openedConflict)
                        remoteRevision = conflictEnv.serverRevision ?? conflictEnv.revision ?? remoteRevision
                        let conflictPass = try mergeRemoteEnvelope(conflictEnv, allowMassDeletions: allowMassDelete)
                        summary = Self.combineSummaries(summary, conflictPass)
                    }
                    continue
                }

                guard (200..<300).contains(statusCode) else {
                    throw CloudSyncError.networkFailure(
                        Self.friendlyHTTPErrorMessage(statusCode: statusCode, responseData: postData)
                    )
                }

                pushedChangesCount = max(1, beforePostCursor.localSeq - beforePostCursor.lastSyncedSeq)
                if !postData.isEmpty {
                    do {
                        let openedPostData = try CloudSyncCrypto.openEnvelopeData(postData, apiKey: apiKey)
                        let serverMergedEnvelope = try decoder.decode(CloudSyncEnvelope.self, from: openedPostData)
                        if let rev = serverMergedEnvelope.serverRevision ?? serverMergedEnvelope.revision {
                            remoteRevision = rev
                        }
                        if actionMode != .forcePushLocal {
                            let secondPass = try mergeRemoteEnvelope(serverMergedEnvelope, allowMassDeletions: allowMassDelete)
                            summary = Self.combineSummaries(summary, secondPass)
                        }
                    } catch let syncErr as CloudSyncError {
                        throw syncErr
                    } catch {
                        throw CloudSyncError.invalidPayload(
                            Self.friendlyPayloadErrorMessage(for: postData, underlyingError: error)
                        )
                    }
                }
                break
            }
        } else if skippedPushReason == nil {
            skippedPushReason = "本地无新变更，未推送"
        }

        let afterSyncCursor = try readLocalSyncCursorState()
        let noConcurrentEditDuringPost = (afterSyncCursor.localSeq == seqCapturedBeforePost)
            && (afterSyncCursor.currentContentFP == contentFPCapturedBeforePost || !shouldPush)

        let advanceSeq: Int? = {
            if !shouldPush {
                return (actionMode == .pullOnly) ? nil : afterSyncCursor.localSeq
            }
            return noConcurrentEditDuringPost ? seqCapturedBeforePost : nil
        }()
        let advanceContentFP: String? = {
            if !shouldPush {
                return (actionMode == .pullOnly) ? nil : afterSyncCursor.currentContentFP
            }
            return noConcurrentEditDuringPost ? afterSyncCursor.currentContentFP : nil
        }()
        let advanceStateFP: String? = (shouldPush && noConcurrentEditDuringPost) ? afterSyncCursor.currentStateFP : (shouldPush ? nil : stateFPCapturedBeforePost)

        let direction: CloudSyncDirection = {
            if actionMode == .forcePushLocal { return .forcedLocalOverwrite }
            if actionMode == .pullOnly { return .pulledOnly }
            if pushedChangesCount == 0 && !summary.hasAnyLocalMutation { return .alignedNoChange }
            if pushedChangesCount == 0 { return .pulledOnly }
            if !summary.hasAnyLocalMutation { return .pushedOnly }
            return .bidirectional
        }()

        let report = try buildAndPersistReport(
            isAutoSync: isAutoSync,
            actionMode: actionMode,
            direction: direction,
            channelKind: "https",
            deviceId: devId,
            remoteRevision: remoteRevision,
            summary: summary,
            pushedChangesCount: pushedChangesCount,
            skippedPushReason: skippedPushReason,
            targetKey: targetKey,
            advanceSyncCursorToSeq: advanceSeq,
            advanceSyncContentFP: advanceContentFP,
            advanceSyncStateFP: advanceStateFP,
            clearUsageDirty: shouldPush && noConcurrentEditDuringPost,
            clearPendingMassDelete: allowMassDelete && shouldPush
        )

        return CloudSyncSummary(
            projectsCreated: summary.projectsCreated,
            projectsUpdated: summary.projectsUpdated,
            entriesCreated: summary.entriesCreated,
            entriesUpdated: summary.entriesUpdated,
            entriesDeleted: summary.entriesDeleted,
            mergedUsageUpdates: summary.mergedUsageUpdates,
            mergedVersions: summary.mergedVersions,
            conflictsPreservedInVersions: summary.conflictsPreservedInVersions,
            orphansMigrated: summary.orphansMigrated,
            protectedEntriesCount: summary.protectedEntriesCount,
            protectedProjectsCount: summary.protectedProjectsCount,
            pushedChangesCount: pushedChangesCount,
            remoteRevision: remoteRevision,
            actionMode: actionMode,
            direction: direction,
            report: report,
            syncedAt: summary.syncedAt
        )
    }

    private static func combineSummaries(_ lhs: CloudSyncSummary, _ rhs: CloudSyncSummary) -> CloudSyncSummary {
        CloudSyncSummary(
            projectsCreated: lhs.projectsCreated + rhs.projectsCreated,
            projectsUpdated: lhs.projectsUpdated + rhs.projectsUpdated,
            entriesCreated: lhs.entriesCreated + rhs.entriesCreated,
            entriesUpdated: lhs.entriesUpdated + rhs.entriesUpdated,
            entriesDeleted: lhs.entriesDeleted + rhs.entriesDeleted,
            mergedUsageUpdates: lhs.mergedUsageUpdates + rhs.mergedUsageUpdates,
            mergedVersions: lhs.mergedVersions + rhs.mergedVersions,
            conflictsPreservedInVersions: lhs.conflictsPreservedInVersions + rhs.conflictsPreservedInVersions,
            orphansMigrated: lhs.orphansMigrated + rhs.orphansMigrated,
            protectedEntriesCount: lhs.protectedEntriesCount + rhs.protectedEntriesCount,
            protectedProjectsCount: lhs.protectedProjectsCount + rhs.protectedProjectsCount,
            pushedChangesCount: max(lhs.pushedChangesCount, rhs.pushedChangesCount),
            remoteRevision: rhs.remoteRevision ?? lhs.remoteRevision,
            actionMode: lhs.actionMode,
            direction: lhs.direction,
            report: rhs.report ?? lhs.report,
            syncedAt: rhs.syncedAt
        )
    }

    private func performAsyncRequest(_ request: URLRequest, maxAttempts: Int = 2) async throws -> (Data, URLResponse) {
        let attempts = max(1, maxAttempts)
        var lastError: CloudSyncError = .networkFailure("服务器无响应，请稍后重试")

        for attempt in 1...attempts {
            try Task.checkCancellation()
            do {
                let (responseData, urlResponse) = try await urlSession.data(for: request)
                if let httpResponse = urlResponse as? HTTPURLResponse,
                   [429, 502, 503, 504].contains(httpResponse.statusCode),
                   attempt < attempts {
                    try await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }
                return (responseData, urlResponse)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue {
                    throw CancellationError()
                }
                lastError = .networkFailure(Self.friendlyNetworkErrorMessage(for: error))
                if attempt < attempts {
                    try await Task.sleep(nanoseconds: 250_000_000)
                    continue
                }
                throw lastError
            }
        }

        throw lastError
    }

    static func looksLikeHTMLPayload(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        let prefixData = data.prefix(512)
        guard let snippet = String(data: prefixData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return false
        }
        return snippet.hasPrefix("<!doctype html")
            || snippet.hasPrefix("<html")
            || snippet.contains("<head>")
            || snippet.contains("<body>")
            || snippet.contains("502 bad gateway")
            || snippet.contains("504 gateway time-out")
    }

    static func friendlyNetworkErrorMessage(for error: Error) -> String {
        if let syncErr = error as? CloudSyncError {
            return syncErr.localizedDescription
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: nsError.code) {
            case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff:
                return "当前网络未连接，请检查网络设置"
            case .timedOut:
                return "网络请求超时，请检查服务器或网络状态"
            case .cannotFindHost, .dnsLookupFailed:
                return "无法解析同步服务器域名，请检查地址是否正确"
            case .cannotConnectToHost:
                return "无法连接到同步服务器，请确认服务已启动且端口可达"
            case .networkConnectionLost:
                return "网络连接中断，请稍后重试"
            case .secureConnectionFailed,
                 .serverCertificateHasBadDate,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .clientCertificateRejected:
                return "HTTPS 安全连接或证书校验失败，请检查证书配置"
            case .badURL, .unsupportedURL:
                return "同步地址格式不正确"
            default:
                break
            }
        }
        return error.localizedDescription
    }

    static func friendlyHTTPErrorMessage(statusCode: Int, responseData: Data? = nil) -> String {
        var serverDetail: String?
        if let responseData, !responseData.isEmpty, !looksLikeHTMLPayload(responseData),
           let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            if let err = (json["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !err.isEmpty {
                serverDetail = String(err.prefix(80))
            } else if let msg = (json["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
                serverDetail = String(msg.prefix(80))
            }
        }

        let baseMessage: String
        switch statusCode {
        case 400:
            baseMessage = "同步请求参数或格式有误 (HTTP 400)"
        case 401:
            return "Token 鉴权未通过 (HTTP 401)，请确认已填写不少于 12 位的专属 Token"
        case 403:
            baseMessage = "访问被拒绝 (HTTP 403)，请检查 Token 权限或反向代理配置"
        case 404:
            baseMessage = "未找到同步接口 (HTTP 404)，请确认同步地址包含 /v1/sync"
        case 413:
            baseMessage = "同步数据体积超出服务器限制 (HTTP 413)"
        case 429:
            baseMessage = "同步请求过于频繁 (HTTP 429)，请稍后再试"
        case 500:
            baseMessage = "同步服务器内部错误 (HTTP 500)"
        case 502, 503, 504:
            baseMessage = "网关或同步服务暂时不可用 (HTTP \(statusCode))，请确认后端服务运行正常"
        default:
            baseMessage = "服务器返回异常状态 (HTTP \(statusCode))"
        }
        if let serverDetail {
            return "\(baseMessage)：\(serverDetail)"
        }
        return baseMessage
    }

    static func friendlyPayloadErrorMessage(for data: Data, underlyingError: Error) -> String {
        if let syncErr = underlyingError as? CloudSyncError {
            return syncErr.localizedDescription
        }
        if looksLikeHTMLPayload(data) {
            return "远端返回了网页而非同步数据（请检查同步地址或反向代理路径配置）"
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let errText = ((json["error"] as? String) ?? (json["message"] as? String))?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !errText.isEmpty {
                return "远端返回非同步数据：\(String(errText.prefix(80)))"
            }
            return "远端返回的 JSON 不是有效的 PromptPanel 同步包，请检查接口地址"
        }
        return "无法解析同步数据包（数据可能损坏或格式不兼容）"
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
