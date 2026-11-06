import Cocoa

/// Manages the menu bar tray icon and its menu.
@MainActor
final class TrayManager {

    private var statusItem: NSStatusItem?
    private let onOpenMainWindow: () -> Void
    private let onQuit: () -> Void

    init(onOpenMainWindow: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onOpenMainWindow = onOpenMainWindow
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
        let openItem = NSMenuItem(title: "打开主界面", action: #selector(handleOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 PromptPanel", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        PPLogger.tray.info("Tray setup complete")
    }

    @objc private func handleOpen() {
        onOpenMainWindow()
    }

    @objc private func handleQuit() {
        onQuit()
    }
}
