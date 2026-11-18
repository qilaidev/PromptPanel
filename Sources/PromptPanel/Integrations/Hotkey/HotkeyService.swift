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
    /// The global hotkey to toggle the quick panel (slot 0 of `GlobalHotkeyAction.togglePanel`).
    /// The raw name is unchanged so existing user bindings survive the multi-binding upgrade.
    static let togglePanel = Self("togglePanel", default: preferredTogglePanelShortcut)
}

/// Every system-wide action PromptPanel can bind, each with up to `maxBindings`
/// interchangeable shortcuts. Bindings live in `UserDefaults` (via KeyboardShortcuts),
/// i.e. per machine: they are never synced, because a combination that is free on
/// one Mac is often taken on another.
enum GlobalHotkeyAction: String, CaseIterable, Identifiable {
    case togglePanel
    case quickNote
    case quickTodo
    case clipboardToNote
    case repeatLastEntry
    case toggleReferenceWindow

    static let maxBindings = 3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .togglePanel: return "呼出快捷面板"
        case .quickNote: return "直接写便签"
        case .quickTodo: return "直接记待办"
        case .clipboardToNote: return "剪贴板存为便签"
        case .repeatLastEntry: return "重贴上一条词条"
        case .toggleReferenceWindow: return "开关参考窗口"
        }
    }

    var hint: String {
        switch self {
        case .togglePanel: return "可绑定多个组合键，任意一个都能呼出"
        case .quickNote: return "打开面板并进入便签输入，回车即存"
        case .quickTodo: return "打开面板并进入待办输入，回车即存"
        case .clipboardToNote: return "不打开面板，静默存入「速记与待办」"
        case .repeatLastEntry: return "不打开面板，把上次执行的词条贴到当前输入框"
        case .toggleReferenceWindow: return "在任意应用里打开或关闭参考窗口"
        }
    }

    /// Stable, ordered storage names. Slot 0 of `togglePanel` keeps the legacy
    /// `togglePanel` name (and its default); every other slot starts empty.
    var shortcutNames: [KeyboardShortcuts.Name] {
        Self.namesByAction[self] ?? []
    }

    private static let namesByAction: [GlobalHotkeyAction: [KeyboardShortcuts.Name]] = {
        var result: [GlobalHotkeyAction: [KeyboardShortcuts.Name]] = [:]
        for action in GlobalHotkeyAction.allCases {
            result[action] = (0..<maxBindings).map { slot in
                if action == .togglePanel, slot == 0 {
                    return .togglePanel
                }
                return KeyboardShortcuts.Name(slot == 0 ? action.rawValue : "\(action.rawValue)_\(slot)")
            }
        }
        return result
    }()

    static var allShortcutNames: [KeyboardShortcuts.Name] {
        allCases.flatMap(\.shortcutNames)
    }

    /// The action owning a storage name, if any.
    static func owner(of name: KeyboardShortcuts.Name) -> GlobalHotkeyAction? {
        allCases.first { $0.shortcutNames.contains(name) }
    }

    /// Bound shortcuts for this action, in slot order, as `(name, shortcut)` pairs.
    func boundShortcuts(
        lookup: (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? = { KeyboardShortcuts.getShortcut(for: $0) }
    ) -> [(name: KeyboardShortcuts.Name, shortcut: KeyboardShortcuts.Shortcut)] {
        shortcutNames.compactMap { name in
            lookup(name).map { (name, $0) }
        }
    }

    /// Which other binding already uses `shortcut`. Two names holding the same
    /// combination would both fire on one keypress, so the recorder refuses it.
    static func conflict(
        for shortcut: KeyboardShortcuts.Shortcut,
        excluding excludedName: KeyboardShortcuts.Name,
        lookup: (KeyboardShortcuts.Name) -> KeyboardShortcuts.Shortcut? = { KeyboardShortcuts.getShortcut(for: $0) }
    ) -> GlobalHotkeyAction? {
        for action in allCases {
            for name in action.shortcutNames where name != excludedName {
                if lookup(name) == shortcut {
                    return action
                }
            }
        }
        return nil
    }
}

extension Notification.Name {
    /// Posted whenever a global hotkey binding is recorded, cleared or a recording ends.
    static let globalHotkeysDidChange = Notification.Name("PromptPanel.globalHotkeysDidChange")
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
    private let handlers: [GlobalHotkeyAction: () -> Void]
    private let registrar: HotkeyRegistrationHandling
    private let panelOpenTracker: PanelOpenTracker?
    private let userDefaults: UserDefaults

    init(
        handlers: [GlobalHotkeyAction: () -> Void],
        registrar: HotkeyRegistrationHandling = KeyboardShortcutsRegistrar(),
        panelOpenTracker: PanelOpenTracker? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.handlers = handlers
        self.registrar = registrar
        self.panelOpenTracker = panelOpenTracker
        self.userDefaults = userDefaults
    }

    convenience init(
        onTogglePanel: @escaping () -> Void,
        registrar: HotkeyRegistrationHandling = KeyboardShortcutsRegistrar(),
        panelOpenTracker: PanelOpenTracker? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.init(
            handlers: [.togglePanel: onTogglePanel],
            registrar: registrar,
            panelOpenTracker: panelOpenTracker,
            userDefaults: userDefaults
        )
    }

    /// Start listening. Every slot of every handled action is registered up front:
    /// KeyboardShortcuts only grabs the key once a slot actually holds a shortcut,
    /// and picks up later edits from the recorder on its own.
    func start() {
        migrateLegacyShortcutIfNeeded()
        for action in GlobalHotkeyAction.allCases {
            guard handlers[action] != nil else { continue }
            for name in action.shortcutNames {
                registrar.onKeyUp(for: name) { [weak self] in
                    self?.handle(action)
                }
            }
        }
        PPLogger.hotkey.info("Hotkey service started")
    }

    /// Stop listening.
    func stop() {
        for action in GlobalHotkeyAction.allCases where handlers[action] != nil {
            for name in action.shortcutNames {
                registrar.disable(name)
            }
        }
        PPLogger.hotkey.info("Hotkey service stopped")
    }

    private func handle(_ action: GlobalHotkeyAction) {
        if action == .togglePanel || action == .quickNote || action == .quickTodo {
            panelOpenTracker?.markHotkeyTriggered()
        }
        PPLogger.hotkey.info("Global hotkey triggered: \(action.rawValue, privacy: .public)")
        handlers[action]?()
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
