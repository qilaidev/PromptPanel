import AppKit
import CryptoKit
import Foundation
import GRDB
import LocalAuthentication
import Security

protocol CloudSyncSecretStoring: Sendable {
    func loadSecret() throws -> String?
    func saveSecret(_ secret: String) throws
    func deleteSecret() throws
}

enum CloudSyncSecretStoreError: LocalizedError {
    case keychainFailure(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainFailure(let status):
            return "访问系统钥匙串失败 (OSStatus \(status))"
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

    func loadSecret() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound, errSecInteractionNotAllowed:
            return nil
        default:
            throw CloudSyncSecretStoreError.keychainFailure(status)
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
        } else if Self.shouldUseSystemKeychain(forDatabasePath: dbQueue.path) {
            self.secretStore = KeychainCloudSyncSecretStore()
        } else {
            let normalizedScope = URL(fileURLWithPath: dbQueue.path).standardizedFileURL.path
            self.secretStore = IsolatedMemoryCloudSyncSecretStore(scopeKey: normalizedScope)
        }
    }

    private static func shouldUseSystemKeychain(forDatabasePath dbPath: String) -> Bool {
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

    func getCloudSyncApiKey() throws -> String {
        guard let stored = try get(Constants.SettingsKey.cloudSyncApiKey), !stored.isEmpty else {
            return ""
        }
        if stored == Self.keychainStoredMarker {
            return (try secretStore.loadSecret()) ?? ""
        }
        if stored.hasPrefix("enc:v2:") {
            let b64 = String(stored.dropFirst("enc:v2:".count))
            guard let combined = Data(base64Encoded: b64) else { return "" }
            let box = try AES.GCM.SealedBox(combined: combined)
            let opened = try AES.GCM.open(box, using: Self.legacyLocalSettingsKey, authenticating: Self.legacyApiKeyAAD)
            let decrypted = String(data: opened, encoding: .utf8) ?? ""
            if !decrypted.isEmpty {
                try? setCloudSyncApiKey(decrypted)
            }
            return decrypted
        }
        // Transparently migrate legacy plaintext API key to Keychain and scrub SQLite row
        try? setCloudSyncApiKey(stored)
        return stored
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
