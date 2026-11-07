import Cocoa

/// Manages the menu bar tray icon and its menu.
@MainActor
final class TrayManager {

    private var statusItem: NSStatusItem?
    private let onToggleQuickPanel: () -> Void
    private let onOpenMainWindow: () -> Void
    private let onOpenReferenceWindow: () -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    init(
        onToggleQuickPanel: @escaping () -> Void = {},
        onOpenMainWindow: @escaping () -> Void,
        onOpenReferenceWindow: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onQuit: @escaping () -> Void
    ) {
        self.onToggleQuickPanel = onToggleQuickPanel
        self.onOpenMainWindow = onOpenMainWindow
        self.onOpenReferenceWindow = onOpenReferenceWindow
        self.onOpenSettings = onOpenSettings
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

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 PromptPanel", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        PPLogger.tray.info("Tray setup complete")
    }

    @objc private func handleTogglePanel() {
        onToggleQuickPanel()
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

    @objc private func handleQuit() {
        onQuit()
    }
}
