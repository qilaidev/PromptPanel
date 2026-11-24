import AppKit
import CryptoKit
import Foundation
import GRDB
import IOKit
import LocalAuthentication
import Security

/// Distinguishes a genuinely absent sync token from one blocked by macOS Keychain ACLs
/// (for example after upgrading an ad-hoc signed build whose CDHash changed).
enum CloudSyncSecretLoadStatus: Equatable, Sendable {
    case loaded(String)
    case missing
    case accessDenied
}

protocol CloudSyncSecretStoring: Sendable {
    func loadSecret() throws -> String?
    func loadSecretStatus() throws -> CloudSyncSecretLoadStatus
    func saveSecret(_ secret: String) throws
    func deleteSecret() throws
}

extension CloudSyncSecretStoring {
    func loadSecretStatus() throws -> CloudSyncSecretLoadStatus {
        if let secret = try loadSecret(), !secret.isEmpty {
            return .loaded(secret)
        }
        return .missing
    }
}

enum CloudSyncSecretStoreError: LocalizedError {
    case keychainFailure(OSStatus)
    case fileEncryptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .keychainFailure(let status):
            return "访问系统钥匙串失败 (OSStatus \(status))"
        case .fileEncryptionFailed(let detail):
            return "读写本地加密凭据文件失败：\(detail)"
        }
    }
}

final class KeychainCloudSyncSecretStore: CloudSyncSecretStoring {
    private let service: String
    private let account: String

    init(
        service: String = "com.promptpanel.app.cloudsync",
        account: String = "cloud_sync_api_key"
    ) {
        self.service = service
        self.account = account
    }

    private func baseQuery(allowNonInteractiveContext: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if allowNonInteractiveContext {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }

    func loadSecretStatus() throws -> CloudSyncSecretLoadStatus {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let decoded = String(data: data, encoding: .utf8),
                  !decoded.isEmpty else {
                return .missing
            }
            return .loaded(decoded)
        case errSecItemNotFound:
            return .missing
        case errSecInteractionNotAllowed, errSecAuthFailed:
            return .accessDenied
        default:
            throw CloudSyncSecretStoreError.keychainFailure(status)
        }
    }

    func loadSecret() throws -> String? {
        switch try loadSecretStatus() {
        case .loaded(let secret):
            return secret
        case .missing, .accessDenied:
            return nil
        }
    }

    func saveSecret(_ secret: String) throws {
        let data = Data(secret.utf8)
        let query = baseQuery(allowNonInteractiveContext: false)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            _ = SecItemDelete(query as CFDictionary)
        }

        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        insertQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CloudSyncSecretStoreError.keychainFailure(addStatus)
        }
    }

    func deleteSecret() throws {
        let query = baseQuery(allowNonInteractiveContext: false)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CloudSyncSecretStoreError.keychainFailure(status)
        }
    }
}

/// Machine-bound AES-256-GCM encrypted credential file (POSIX 0600), stored outside SQLite so
/// database backups, JSON/Markdown exports, and diagnostics bundles never include sync tokens,
/// while surviving ad-hoc binary upgrades without macOS Keychain ACL prompts or silent drops.
final class EncryptedFileCloudSyncSecretStore: CloudSyncSecretStoring, @unchecked Sendable {
    static let defaultFileName = ".cloudsync.secret"
    private static let aad = Data("promptpanel-cloudsync-secret-file-v1".utf8)
    private static let hkdfSalt = Data("PromptPanel-LocalSecretFile-Salt-v1".utf8)
    private static let hkdfInfo = Data("promptpanel-secret-file-aes256gcm-key".utf8) + Data([0x01])

    private struct Envelope: Codable {
        let v: Int
        let cipher: String
        let data: String
    }

    private let fileURL: URL
    private let keyMaterial: String
    private let lock = NSLock()

    init(fileURL: URL, keyMaterial: String? = nil) {
        self.fileURL = fileURL
        self.keyMaterial = keyMaterial ?? Self.resolveMachineKeyMaterial()
    }

    static func defaultFileURL(forDatabasePath dbPath: String) -> URL {
        URL(fileURLWithPath: dbPath)
            .standardizedFileURL
            .deletingLastPathComponent()
            .appendingPathComponent(defaultFileName)
    }

    static func resolveMachineKeyMaterial() -> String {
        let hardwareUUID = readHardwarePlatformUUID() ?? "unknown-platform"
        return "PromptPanel-SecretFile|\(hardwareUUID)|\(NSUserName())"
    }

    private static func readHardwarePlatformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func deriveSymmetricKey() -> SymmetricKey {
        let ikm = Data(keyMaterial.utf8)
        let prk = Data(HMAC<SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: Self.hkdfSalt)))
        let okm = Data(HMAC<SHA256>.authenticationCode(for: Self.hkdfInfo, using: SymmetricKey(data: prk)))
        return SymmetricKey(data: okm)
    }

    func loadSecretStatus() throws -> CloudSyncSecretLoadStatus {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return .missing
        }
        let raw = try Data(contentsOf: fileURL)
        guard !raw.isEmpty else {
            return .missing
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: raw)
        guard envelope.v == 1,
              envelope.cipher == "aes-256-gcm",
              let combined = Data(base64Encoded: envelope.data) else {
            throw CloudSyncSecretStoreError.fileEncryptionFailed("凭据文件格式无效")
        }
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(sealedBox, using: deriveSymmetricKey(), authenticating: Self.aad)
        guard let secret = String(data: plaintext, encoding: .utf8), !secret.isEmpty else {
            return .missing
        }
        return .loaded(secret)
    }

    func loadSecret() throws -> String? {
        switch try loadSecretStatus() {
        case .loaded(let secret):
            return secret
        case .missing, .accessDenied:
            return nil
        }
    }

    func saveSecret(_ secret: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: Constants.secureDirectoryPermissions]
            )
        }
        let sealed = try AES.GCM.seal(Data(secret.utf8), using: deriveSymmetricKey(), authenticating: Self.aad)
        guard let combined = sealed.combined else {
            throw CloudSyncSecretStoreError.fileEncryptionFailed("AES-256-GCM 封装失败")
        }
        let payload = Envelope(v: 1, cipher: "aes-256-gcm", data: combined.base64EncodedString())
        let encoded = try JSONEncoder().encode(payload)

        let tempURL = dir.appendingPathComponent(".cloudsync.secret.tmp-\(UUID().uuidString)")
        do {
            try encoded.write(to: tempURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: Constants.secureFilePermissions], ofItemAtPath: tempURL.path)
            if fm.fileExists(atPath: fileURL.path) {
                _ = try fm.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try fm.moveItem(at: tempURL, to: fileURL)
            }
            try fm.setAttributes([.posixPermissions: Constants.secureFilePermissions], ofItemAtPath: fileURL.path)
        } catch {
            try? fm.removeItem(at: tempURL)
            throw error
        }
    }

    func deleteSecret() throws {
        lock.lock()
        defer { lock.unlock() }
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try fm.removeItem(at: fileURL)
        }
    }
}

/// Selects the optimal credential store based on code-signing identity:
/// - Developer ID / Team-signed builds use macOS Keychain first (stable designated requirement).
/// - Ad-hoc / open-source self-built binaries use the machine-bound 0600 encrypted secret file
///   so upgrades never break Keychain ACLs or trigger password dialogs, while transparently
///   migrating any readable legacy Keychain item and surfacing `.accessDenied` instead of wiping.
final class CodeSignAwareCloudSyncSecretStore: CloudSyncSecretStoring, @unchecked Sendable {
    private let prefersKeychain: Bool
    private let keychainStore: CloudSyncSecretStoring
    private let fileStore: CloudSyncSecretStoring

    init(
        prefersKeychain: Bool = CodeSignAwareCloudSyncSecretStore.currentBinaryHasStableTeamSignature(),
        keychainStore: CloudSyncSecretStoring = KeychainCloudSyncSecretStore(),
        fileStore: CloudSyncSecretStoring
    ) {
        self.prefersKeychain = prefersKeychain
        self.keychainStore = keychainStore
        self.fileStore = fileStore
    }

    static func currentBinaryHasStableTeamSignature() -> Bool {
        var selfCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &selfCode) == errSecSuccess,
              let code = selfCode else {
            return false
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let resolvedStaticCode = staticCode else {
            return false
        }
        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(resolvedStaticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any],
              let teamId = info[kSecCodeInfoTeamIdentifier as String] as? String else {
            return false
        }
        let trimmed = teamId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 10 else { return false }
        return trimmed.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII }
    }

    func loadSecretStatus() throws -> CloudSyncSecretLoadStatus {
        if prefersKeychain {
            let primaryStatus = (try? keychainStore.loadSecretStatus()) ?? .missing
            switch primaryStatus {
            case .loaded:
                return primaryStatus
            case .accessDenied:
                if let fallback = try? fileStore.loadSecretStatus(), case .loaded = fallback {
                    return fallback
                }
                return .accessDenied
            case .missing:
                if let fallback = try? fileStore.loadSecretStatus(), case .loaded(let secret) = fallback {
                    try? keychainStore.saveSecret(secret)
                    return .loaded(secret)
                }
                return .missing
            }
        } else {
            let fileStatus = (try? fileStore.loadSecretStatus()) ?? .missing
            if case .loaded = fileStatus {
                return fileStatus
            }
            let legacyKeychainStatus = (try? keychainStore.loadSecretStatus()) ?? .missing
            switch legacyKeychainStatus {
            case .loaded(let secret):
                try? fileStore.saveSecret(secret)
                return .loaded(secret)
            case .accessDenied:
                return .accessDenied
            case .missing:
                return .missing
            }
        }
    }

    func loadSecret() throws -> String? {
        switch try loadSecretStatus() {
        case .loaded(let secret):
            return secret
        case .missing, .accessDenied:
            return nil
        }
    }

    func saveSecret(_ secret: String) throws {
        if prefersKeychain {
            try keychainStore.saveSecret(secret)
            try? fileStore.saveSecret(secret)
        } else {
            try fileStore.saveSecret(secret)
        }
    }

    func deleteSecret() throws {
        try? fileStore.deleteSecret()
        if prefersKeychain {
            try keychainStore.deleteSecret()
        } else {
            try? keychainStore.deleteSecret()
        }
    }
}

final class IsolatedMemoryCloudSyncSecretStore: CloudSyncSecretStoring, @unchecked Sendable {
    private static let lock = NSLock()
    private static var secretsByScope: [String: String] = [:]

    private let scopeKey: String

    init(scopeKey: String) {
        self.scopeKey = scopeKey
    }

    func loadSecret() throws -> String? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return Self.secretsByScope[scopeKey]
    }

    func saveSecret(_ secret: String) throws {
        Self.lock.lock()
        Self.secretsByScope[scopeKey] = secret
        Self.lock.unlock()
    }

    func deleteSecret() throws {
        Self.lock.lock()
        Self.secretsByScope.removeValue(forKey: scopeKey)
        Self.lock.unlock()
    }
}

/// Data access layer for app settings (key-value store).
final class SettingsRepository: @unchecked Sendable {
    static let keychainStoredMarker = "keychain:v1"

    private let dbQueue: DatabaseQueue
    private let secretStore: CloudSyncSecretStoring

    init(dbQueue: DatabaseQueue, secretStore: CloudSyncSecretStoring? = nil) {
        self.dbQueue = dbQueue
        if let secretStore {
            self.secretStore = secretStore
        } else if Self.shouldUseLiveSecretStore(forDatabasePath: dbQueue.path) {
            let fileURL = EncryptedFileCloudSyncSecretStore.defaultFileURL(forDatabasePath: dbQueue.path)
            self.secretStore = CodeSignAwareCloudSyncSecretStore(
                fileStore: EncryptedFileCloudSyncSecretStore(fileURL: fileURL)
            )
        } else {
            let normalizedScope = URL(fileURLWithPath: dbQueue.path).standardizedFileURL.path
            self.secretStore = IsolatedMemoryCloudSyncSecretStore(scopeKey: normalizedScope)
        }
    }

    private static func shouldUseLiveSecretStore(forDatabasePath dbPath: String) -> Bool {
        guard ProcessInfo.processInfo.environment["PROMPTPANEL_APP_SUPPORT_DIR"] == nil else {
            return false
        }
        guard !dbPath.isEmpty, dbPath != ":memory:" else {
            return false
        }
        let candidateURL = URL(fileURLWithPath: dbPath).standardizedFileURL
        let liveURL = Constants.databaseURL.standardizedFileURL
        return candidateURL.path == liveURL.path
    }

    /// Get a setting value by key.
    func get(_ key: String) throws -> String? {
        try dbQueue.read { db in
            try AppSetting
                .filter(AppSetting.Columns.key == key)
                .fetchOne(db)?
                .value
        }
    }

    /// Set a setting value.
    func set(_ key: String, value: String?) throws {
        try dbQueue.write { db in
            try Self.persist(key, value: value, in: db)
        }
    }

    // MARK: - Convenience

    func getCurrentProjectId() throws -> String? {
        try get(Constants.SettingsKey.currentProjectId)
    }

    func setCurrentProjectId(_ id: String) throws {
        try set(Constants.SettingsKey.currentProjectId, value: id)
        PPLogger.project.debug("Current project set to: \(id)")
    }

    func getBool(_ key: String, default defaultValue: Bool = false) throws -> Bool {
        guard let rawValue = try get(key) else {
            return defaultValue
        }

        switch rawValue.lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return defaultValue
        }
    }

    func setBool(_ key: String, value: Bool) throws {
        try set(key, value: value ? "1" : "0")
    }

    func isPanelPinned() throws -> Bool {
        try getBool(Constants.SettingsKey.panelPinned)
    }

    func setPanelPinned(_ isPinned: Bool) throws {
        try setBool(Constants.SettingsKey.panelPinned, value: isPinned)
        PPLogger.panel.debug("Panel pinned set to: \(isPinned)")
    }

    func getPanelContentSize() throws -> NSSize {
        let width = Double(try get(Constants.SettingsKey.panelContentWidth) ?? "") ?? Constants.panelContentSize.width
        let height = Double(try get(Constants.SettingsKey.panelContentHeight) ?? "") ?? Constants.panelContentSize.height
        return normalizedPanelContentSize(NSSize(width: width, height: height))
    }

    func setPanelContentSize(_ size: NSSize) throws {
        let normalizedSize = normalizedPanelContentSize(size)
        try dbQueue.write { db in
            try Self.persist(Constants.SettingsKey.panelContentWidth, value: String(Int(normalizedSize.width.rounded())), in: db)
            try Self.persist(Constants.SettingsKey.panelContentHeight, value: String(Int(normalizedSize.height.rounded())), in: db)
        }
        PPLogger.panel.debug("Panel content size set to: \(Int(normalizedSize.width))x\(Int(normalizedSize.height))")
    }

    func getPanelWindowOrigin() throws -> NSPoint? {
        guard
            let rawX = try get(Constants.SettingsKey.panelWindowOriginX),
            let rawY = try get(Constants.SettingsKey.panelWindowOriginY),
            let x = Double(rawX),
            let y = Double(rawY)
        else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    func setPanelWindowOrigin(_ origin: NSPoint) throws {
        try dbQueue.write { db in
            try Self.persist(Constants.SettingsKey.panelWindowOriginX, value: String(Int(origin.x.rounded())), in: db)
            try Self.persist(Constants.SettingsKey.panelWindowOriginY, value: String(Int(origin.y.rounded())), in: db)
        }
        PPLogger.panel.debug("Panel window origin set to: \(Int(origin.x)),\(Int(origin.y))")
    }

    private static func persist(_ key: String, value: String?, in db: Database) throws {
        let setting = AppSetting(key: key, value: value)
        try setting.save(db)
    }

    private func normalizedPanelContentSize(_ size: NSSize) -> NSSize {
        NSSize(
            width: min(max(size.width, Constants.panelMinContentSize.width), Constants.panelMaxContentSize.width),
            height: min(max(size.height, Constants.panelMinContentSize.height), Constants.panelMaxContentSize.height)
        )
    }

    // MARK: - Panel preferences (design baseline)

    func isPanelFooterVisible() throws -> Bool {
        try getBool(Constants.SettingsKey.panelShowFooter, default: true)
    }

    func setPanelFooterVisible(_ isVisible: Bool) throws {
        try setBool(Constants.SettingsKey.panelShowFooter, value: isVisible)
        PPLogger.panel.debug("Panel footer visibility set to: \(isVisible)")
    }

    func isPanelCompactRows() throws -> Bool {
        try getBool(Constants.SettingsKey.panelCompactRows, default: false)
    }

    func setPanelCompactRows(_ isCompact: Bool) throws {
        try setBool(Constants.SettingsKey.panelCompactRows, value: isCompact)
        PPLogger.panel.debug("Panel compact rows set to: \(isCompact)")
    }

    // MARK: - Theme

    func getAppTheme() throws -> AppTheme {
        AppTheme.resolve(try get(Constants.SettingsKey.appTheme))
    }

    func setAppTheme(_ theme: AppTheme) throws {
        try set(Constants.SettingsKey.appTheme, value: theme.rawValue)
        PPLogger.app.info("App theme set to: \(theme.rawValue)")
    }

    // MARK: - Library

    func getEntrySortMode() throws -> String? {
        try get(Constants.SettingsKey.entrySortMode)
    }

    func setEntrySortMode(_ rawValue: String) throws {
        try set(Constants.SettingsKey.entrySortMode, value: rawValue)
        PPLogger.entry.debug("Entry sort mode set to: \(rawValue)")
    }

    // MARK: - Cloud Sync

    func isCloudSyncEnabled() throws -> Bool {
        try getBool(Constants.SettingsKey.cloudSyncEnabled, default: false)
    }

    func setCloudSyncEnabled(_ enabled: Bool) throws {
        try setBool(Constants.SettingsKey.cloudSyncEnabled, value: enabled)
    }

    func isAutoUpdateEnabled() throws -> Bool {
        try getBool(Constants.SettingsKey.autoUpdateEnabled, default: false)
    }

    func setAutoUpdateEnabled(_ enabled: Bool) throws {
        try setBool(Constants.SettingsKey.autoUpdateEnabled, value: enabled)
    }

    func getCloudSyncEndpoint() throws -> String {
        try get(Constants.SettingsKey.cloudSyncEndpoint) ?? ""
    }

    func setCloudSyncEndpoint(_ endpoint: String) throws {
        try set(Constants.SettingsKey.cloudSyncEndpoint, value: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func getCloudSyncApiKeyStatus() throws -> CloudSyncSecretLoadStatus {
        guard let stored = try get(Constants.SettingsKey.cloudSyncApiKey), !stored.isEmpty else {
            return .missing
        }
        if stored == Self.keychainStoredMarker {
            return try secretStore.loadSecretStatus()
        }
        if stored.hasPrefix("enc:v2:") {
            let b64 = String(stored.dropFirst("enc:v2:".count))
            guard let combined = Data(base64Encoded: b64) else { return .missing }
            let box = try AES.GCM.SealedBox(combined: combined)
            let opened = try AES.GCM.open(box, using: Self.legacyLocalSettingsKey, authenticating: Self.legacyApiKeyAAD)
            let decrypted = String(data: opened, encoding: .utf8) ?? ""
            guard !decrypted.isEmpty else { return .missing }
            try? setCloudSyncApiKey(decrypted)
            return .loaded(decrypted)
        }
        // Transparently migrate legacy plaintext API key to the secret store and scrub SQLite row
        try? setCloudSyncApiKey(stored)
        return .loaded(stored)
    }

    func getCloudSyncApiKey() throws -> String {
        switch try getCloudSyncApiKeyStatus() {
        case .loaded(let secret):
            return secret
        case .missing, .accessDenied:
            return ""
        }
    }

    func setCloudSyncApiKey(_ apiKey: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try secretStore.deleteSecret()
            try set(Constants.SettingsKey.cloudSyncApiKey, value: "")
            return
        }
        try secretStore.saveSecret(trimmed)
        try set(Constants.SettingsKey.cloudSyncApiKey, value: Self.keychainStoredMarker)
    }

    static func makeLegacyEncryptedApiKeyForMigrationTest(_ plaintext: String) throws -> String {
        let sealed = try AES.GCM.seal(
            Data(plaintext.utf8),
            using: legacyLocalSettingsKey,
            authenticating: legacyApiKeyAAD
        )
        return "enc:v2:" + (sealed.combined?.base64EncodedString() ?? "")
    }

    private static let legacyApiKeyAAD = Data("promptpanel-local-settings-apikey-v2".utf8)
    private static let legacyLocalSettingsKey: SymmetricKey = {
        let material = Data("PromptPanel-Local-Settings-\(NSUserName())".utf8)
        let prk = Data(HMAC<SHA256>.authenticationCode(for: material, using: SymmetricKey(data: Data("PromptPanel-Settings-Salt-v2".utf8))))
        return SymmetricKey(data: prk)
    }()
}
