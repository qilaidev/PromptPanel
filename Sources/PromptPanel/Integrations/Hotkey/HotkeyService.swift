import Foundation
import KeyboardShortcuts

private let preferredTogglePanelShortcut = KeyboardShortcuts.Shortcut(.two, modifiers: [.option])
private let migratableDefaultTogglePanelShortcuts = [
    KeyboardShortcuts.Shortcut(.space, modifiers: [.option]),
    KeyboardShortcuts.Shortcut(.space, modifiers: [.option, .shift]),
    KeyboardShortcuts.Shortcut(.p, modifiers: [.option, .shift]),
]
private let togglePanelShortcutMigrationFlagKey = "toggle_panel_shortcut_migrated_to_option_2"

// MARK: - Hotkey Name Registration

extension KeyboardShortcuts.Name {
    /// The global hotkey to toggle the quick panel.
    static let togglePanel = Self("togglePanel", default: preferredTogglePanelShortcut)
}

protocol HotkeyRegistrationHandling {
    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping () -> Void)
    func disable(_ name: KeyboardShortcuts.Name)
}

struct KeyboardShortcutsRegistrar: HotkeyRegistrationHandling {
    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: name, action: action)
    }

    func disable(_ name: KeyboardShortcuts.Name) {
        KeyboardShortcuts.disable(name)
    }
}

/// Manages global hotkey registration and handling.
@MainActor
final class HotkeyService {
    private let onTogglePanel: () -> Void
    private let registrar: HotkeyRegistrationHandling
    private let panelOpenTracker: PanelOpenTracker?
    private let userDefaults: UserDefaults

    init(
        onTogglePanel: @escaping () -> Void,
        registrar: HotkeyRegistrationHandling = KeyboardShortcutsRegistrar(),
        panelOpenTracker: PanelOpenTracker? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.onTogglePanel = onTogglePanel
        self.registrar = registrar
        self.panelOpenTracker = panelOpenTracker
        self.userDefaults = userDefaults
    }

    /// Start listening for the global hotkey.
    func start() {
        migrateLegacyShortcutIfNeeded()
        registrar.onKeyUp(for: .togglePanel) { [weak self] in
            self?.handleTogglePanel()
        }
        PPLogger.hotkey.info("Hotkey service started")
    }

    /// Stop listening.
    func stop() {
        registrar.disable(.togglePanel)
        PPLogger.hotkey.info("Hotkey service stopped")
    }

    private func handleTogglePanel() {
        panelOpenTracker?.markHotkeyTriggered()
        PPLogger.hotkey.info("Toggle panel hotkey triggered")
        onTogglePanel()
    }

    private func migrateLegacyShortcutIfNeeded() {
        guard !userDefaults.bool(forKey: togglePanelShortcutMigrationFlagKey) else {
            return
        }
        guard let currentShortcut = KeyboardShortcuts.Name.togglePanel.shortcut else {
            return
        }
        guard migratableDefaultTogglePanelShortcuts.contains(currentShortcut) else {
            return
        }

        KeyboardShortcuts.setShortcut(preferredTogglePanelShortcut, for: .togglePanel)
        userDefaults.set(true, forKey: togglePanelShortcutMigrationFlagKey)
        PPLogger.hotkey.notice("Migrated legacy toggle-panel hotkey to preferred default")
    }
}
