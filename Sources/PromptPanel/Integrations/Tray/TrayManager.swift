import Cocoa

/// Manages the menu bar tray icon and its menu.
@MainActor
final class TrayManager {

    private var statusItem: NSStatusItem?
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
            if let image = NSImage(systemSymbolName: "text.page.badge.magnifyingglass", accessibilityDescription: "PromptPanel") {
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
