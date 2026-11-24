import Cocoa

/// Manages the menu bar tray icon and its menu.
@MainActor
final class TrayManager {

    private var statusItem: NSStatusItem?
    private var syncStatusItem: NSMenuItem?
    private var checkUpdateItem: NSMenuItem?
    private let onToggleQuickPanel: () -> Void
    private let onQuickNoteFromClipboard: () -> Void
    private let onOpenMainWindow: () -> Void
    private let onOpenReferenceWindow: () -> Void
    private let onOpenSettings: () -> Void
    private let onCheckForUpdates: () -> Void
    private let onQuit: () -> Void

    init(
        onToggleQuickPanel: @escaping () -> Void = {},
        onQuickNoteFromClipboard: @escaping () -> Void = {},
        onOpenMainWindow: @escaping () -> Void,
        onOpenReferenceWindow: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onCheckForUpdates: @escaping () -> Void = {},
        onQuit: @escaping () -> Void
    ) {
        self.onToggleQuickPanel = onToggleQuickPanel
        self.onQuickNoteFromClipboard = onQuickNoteFromClipboard
        self.onOpenMainWindow = onOpenMainWindow
        self.onOpenReferenceWindow = onOpenReferenceWindow
        self.onOpenSettings = onOpenSettings
        self.onCheckForUpdates = onCheckForUpdates
        self.onQuit = onQuit
    }

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let symbol = NSImage(systemSymbolName: "text.page.badge.magnifyingglass", accessibilityDescription: "PromptPanel")
                ?? NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "PromptPanel")
            if let image = symbol {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "PP"
            }
        }

        let menu = NSMenu()

        let panelItem = NSMenuItem(title: "呼出快捷面板", action: #selector(handleTogglePanel), keyEquivalent: "")
        panelItem.target = self
        menu.addItem(panelItem)

        let quickNoteItem = NSMenuItem(title: "从剪贴板速记便签", action: #selector(handleQuickNoteFromClipboard), keyEquivalent: "")
        quickNoteItem.target = self
        menu.addItem(quickNoteItem)

        let openItem = NSMenuItem(title: "打开主界面", action: #selector(handleOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let referenceItem = NSMenuItem(title: "打开参考窗口", action: #selector(handleOpenReference), keyEquivalent: "N")
        referenceItem.keyEquivalentModifierMask = [.command, .shift]
        referenceItem.target = self
        menu.addItem(referenceItem)

        let settingsItem = NSMenuItem(title: "偏好设置…", action: #selector(handleOpenSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = [.command]
        settingsItem.target = self
        menu.addItem(settingsItem)

        let syncItem = NSMenuItem(title: "云端同步：未配置", action: #selector(handleOpenSettings), keyEquivalent: "")
        syncItem.target = self
        menu.addItem(syncItem)
        self.syncStatusItem = syncItem

        let updateItem = NSMenuItem(title: "检查更新…", action: #selector(handleCheckUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        self.checkUpdateItem = updateItem

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 PromptPanel", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        PPLogger.tray.info("Tray setup complete")
    }

    func updateCheckMenuItemTitle(_ title: String) {
        checkUpdateItem?.title = title
    }

    func updateCloudSyncState(_ state: SyncBadgeState) {
        let title: String
        switch state {
        case .unconfigured:
            title = "云端同步：未配置"
        case .syncing:
            title = "云端同步：同步中…"
        case .autoSynced(let rev):
            title = rev.map { "云端同步：已同步 (r\($0))" } ?? "云端同步：自动同步已就绪"
        case .autoPending(let count):
            title = count.map { "云端同步：\($0) 项待上传" } ?? "云端同步：有待上传变更"
        case .manualIdle(let rev, let hasPending):
            if hasPending {
                title = "云端同步：手动模式（有待推送）"
            } else if let rev, rev > 0 {
                title = "云端同步：手动模式 (r\(rev))"
            } else {
                title = "云端同步：手动模式"
            }
        case .error:
            title = "⚠ 云端同步异常（点击查看）"
        }
        syncStatusItem?.title = title
    }

    @objc private func handleTogglePanel() {
        onToggleQuickPanel()
    }

    @objc private func handleQuickNoteFromClipboard() {
        onQuickNoteFromClipboard()
    }

    @objc private func handleOpen() {
        onOpenMainWindow()
    }

    @objc private func handleOpenReference() {
        onOpenReferenceWindow()
    }

    @objc private func handleOpenSettings() {
        onOpenSettings()
    }

    @objc private func handleCheckUpdates() {
        onCheckForUpdates()
    }

    @objc private func handleQuit() {
        onQuit()
    }
}
