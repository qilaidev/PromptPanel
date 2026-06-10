import AppKit
import Foundation
import GRDB

/// Data access layer for app settings (key-value store).
final class SettingsRepository: @unchecked Sendable {

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
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
        PPLogger.project.info("Current project set to: \(id)")
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
        PPLogger.panel.info("Panel pinned set to: \(isPinned)")
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
        PPLogger.panel.info("Panel content size set to: \(Int(normalizedSize.width))x\(Int(normalizedSize.height))")
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
        PPLogger.panel.info("Panel window origin set to: \(Int(origin.x)),\(Int(origin.y))")
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
        PPLogger.panel.info("Panel footer visibility set to: \(isVisible)")
    }

    func isPanelCompactRows() throws -> Bool {
        try getBool(Constants.SettingsKey.panelCompactRows, default: false)
    }

    func setPanelCompactRows(_ isCompact: Bool) throws {
        try setBool(Constants.SettingsKey.panelCompactRows, value: isCompact)
        PPLogger.panel.info("Panel compact rows set to: \(isCompact)")
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
        PPLogger.entry.info("Entry sort mode set to: \(rawValue)")
    }
}
