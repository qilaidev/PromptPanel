import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

/// Coordinates global hotkey recording across all `HotkeyRecorderModel` instances
/// so switching between chips or deallocating an old chip never races on
/// `KeyboardShortcuts.isEnabled`.
@MainActor
final class HotkeyRecordingCoordinator {
    static let shared = HotkeyRecordingCoordinator()

    private weak var activeModel: HotkeyRecorderModel?
    private var activeToken: ObjectIdentifier?

    private init() {}

    func beginRecording(_ model: HotkeyRecorderModel) {
        let token = ObjectIdentifier(model)
        if let current = activeModel, current !== model {
            current.cancelFromCoordinator()
        }
        activeModel = model
        activeToken = token
        KeyboardShortcuts.isEnabled = false
    }

    func endRecording(_ model: HotkeyRecorderModel) {
        endRecording(token: ObjectIdentifier(model))
    }

    func endRecording(token: ObjectIdentifier) {
        guard activeToken == token else { return }
        activeModel = nil
        activeToken = nil
        KeyboardShortcuts.isEnabled = true
    }
}

/// Records the global toggle-panel hotkey using only `KeyboardShortcuts`' public,
/// non-UI API.
///
/// Why we do not use `KeyboardShortcuts.Recorder`: its conflict alerts resolve strings via
/// `NSLocalizedString(_, bundle: .module, ...)`, and SwiftPM's generated `Bundle.module`
/// accessor looks in exactly one place — `Bundle.main.bundleURL/<Package>_<Target>.bundle`,
/// which for a packaged app is the `.app` bundle ROOT. Anything placed there (even a
/// symlink) leaves the bundle with unsealed root contents, which makes `codesign --verify`
/// exit non-zero; Gatekeeper then blocks the downloaded app and Sparkle refuses to install
/// it as an update. Driving the shortcut store directly keeps the bundle sealed.
@MainActor
final class HotkeyRecorderModel: ObservableObject {
    /// What the event monitor extracts from an `NSEvent`. NSEvent is explicitly non-Sendable,
    /// so the monitor closure reduces it to plain values before handing anything to the
    /// main-actor-isolated handler.
    struct KeyStroke: Equatable {
        let keyCode: UInt16
        let modifiers: NSEvent.ModifierFlags
        let isFunctionKey: Bool
        /// `nil` when the event is not a usable key event at all.
        let carbonShortcut: (keyCode: Int, modifiers: Int)?

        static func == (lhs: KeyStroke, rhs: KeyStroke) -> Bool {
            lhs.keyCode == rhs.keyCode
                && lhs.modifiers == rhs.modifiers
                && lhs.isFunctionKey == rhs.isFunctionKey
                && lhs.carbonShortcut?.keyCode == rhs.carbonShortcut?.keyCode
                && lhs.carbonShortcut?.modifiers == rhs.carbonShortcut?.modifiers
        }

        init(event: NSEvent) {
            keyCode = event.keyCode
            modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            isFunctionKey = HotkeyRecorderModel.isFunctionKey(event)
            carbonShortcut = KeyboardShortcuts.Shortcut(event: event)
                .map { ($0.carbonKeyCode, $0.carbonModifiers) }
        }

        init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, isFunctionKey: Bool, carbonShortcut: (keyCode: Int, modifiers: Int)?) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.isFunctionKey = isFunctionKey
            self.carbonShortcut = carbonShortcut
        }
    }

    enum RecordingOutcome: Equatable {
        case cancelled
        case cleared
        case rejected
        case recorded(carbonKeyCode: Int, carbonModifiers: Int)
    }

    /// Escape (53) cancels, delete (51) / forward-delete (117) clears.
    private nonisolated static let escapeKeyCode: UInt16 = 53
    private nonisolated static let clearKeyCodes: Set<UInt16> = [51, 117]

    /// Terminal control chords that must never be hijacked globally (e.g. Ctrl+C SIGINT,
    /// Ctrl+D EOF, Ctrl+Z SIGTSTP, Ctrl+\ SIGQUIT, plus line-editing chords).
    private nonisolated static let terminalReservedControlKeys: Set<KeyboardShortcuts.Key> = [
        .c, .d, .z, .backslash, .u, .k, .l, .w, .a, .e, .r, .s, .q
    ]

    /// Standard macOS editing/app shortcuts reserved regardless of menu population.
    private nonisolated static let systemStandardCommandKeys: Set<KeyboardShortcuts.Key> = [
        .c, .v, .x, .a, .q, .w, .h, .m
    ]

    /// Pure decision function for a recorded keystroke, so the accept/reject/cancel/clear
    /// rules are unit-testable without synthesising real key events end to end.
    nonisolated static func outcome(for stroke: KeyStroke) -> RecordingOutcome {
        let bareModifiers = stroke.modifiers.subtracting(.function)

        if stroke.keyCode == escapeKeyCode, bareModifiers.isEmpty {
            return .cancelled
        }
        if clearKeyCodes.contains(stroke.keyCode), bareModifiers.isEmpty {
            return .cleared
        }
        guard
            isAcceptableCombination(modifiers: stroke.modifiers, isFunctionKey: stroke.isFunctionKey),
            let carbonShortcut = stroke.carbonShortcut
        else {
            return .rejected
        }
        return .recorded(carbonKeyCode: carbonShortcut.keyCode, carbonModifiers: carbonShortcut.modifiers)
    }

    /// A recorded key event is only usable as a global hotkey when it carries a modifier
    /// other than shift, or is a function key. Plain keys (and shift-only combinations)
    /// would swallow ordinary typing, and Carbon refuses to register them reliably.
    nonisolated static func isAcceptableCombination(
        modifiers: NSEvent.ModifierFlags,
        isFunctionKey: Bool
    ) -> Bool {
        if isFunctionKey {
            return true
        }
        return !modifiers
            .intersection([.command, .control, .option])
            .isEmpty
    }

    /// True if `shortcut` is a terminal-reserved control chord (including `Ctrl+C`,
    /// `Ctrl+D`, `Ctrl+Z`, `Ctrl+\`, etc.) that must never be bound globally.
    nonisolated static func isTerminalReserved(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        guard let key = shortcut.key else { return false }
        let mods = shortcut.modifiers.intersection([.command, .control, .option, .shift])
        if mods == [.control], terminalReservedControlKeys.contains(key) {
            return true
        }
        if mods == [.control, .shift], (key == .c || key == .d || key == .z || key == .backslash) {
            return true
        }
        return false
    }

    /// Checks whether `shortcut` conflicts with terminal reserved keys, macOS system
    /// shortcuts, the app's main menu, or another PromptPanel global hotkey binding.
    static func conflictReason(
        for shortcut: KeyboardShortcuts.Shortcut,
        excluding excludedName: KeyboardShortcuts.Name? = nil
    ) -> String? {
        if isTerminalReserved(shortcut) {
            return "\(shortcut.description) 为终端/系统保留键，禁止绑定"
        }

        let mods = shortcut.modifiers.intersection([.command, .control, .option, .shift])
        if mods == [.command], let key = shortcut.key, systemStandardCommandKeys.contains(key) {
            return "\(shortcut.description) 为系统通用快捷键，禁止绑定"
        }

        if isTakenBySystem(shortcut) {
            return "\(shortcut.description) 已被系统快捷键占用"
        }

        if let menuItem = matchingMainMenuItem(for: shortcut) {
            let itemTitle = menuItem.title.isEmpty ? "菜单栏项目" : menuItem.title
            return "\(shortcut.description) 已用于菜单「\(itemTitle)」"
        }

        if let excludedName,
           let owner = GlobalHotkeyAction.conflict(for: shortcut, excluding: excludedName) {
            return "\(shortcut.description) 已用于「\(owner.title)」"
        }

        return nil
    }

    nonisolated static func isTakenBySystem(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        if shortcut == KeyboardShortcuts.Shortcut(.f12, modifiers: []) {
            return false
        }
        var shortcutsUnmanaged: Unmanaged<CFArray>?
        guard
            CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr,
            let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]]
        else {
            return false
        }
        return shortcuts.contains { dict in
            guard
                (dict[kHISymbolicHotKeyEnabled] as? Bool) == true,
                let carbonKeyCode = dict[kHISymbolicHotKeyCode] as? Int,
                let carbonModifiers = dict[kHISymbolicHotKeyModifiers] as? Int
            else {
                return false
            }
            return KeyboardShortcuts.Shortcut(
                carbonKeyCode: carbonKeyCode,
                carbonModifiers: carbonModifiers
            ) == shortcut
        }
    }

    private static func matchingMainMenuItem(for shortcut: KeyboardShortcuts.Shortcut) -> NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu,
              let keyChar = menuKeyEquivalentCharacter(for: shortcut) else {
            return nil
        }
        return findMenuItem(in: mainMenu, keyCharacter: keyChar, modifiers: shortcut.modifiers)
    }

    private static func findMenuItem(
        in menu: NSMenu,
        keyCharacter: String,
        modifiers: NSEvent.ModifierFlags
    ) -> NSMenuItem? {
        for item in menu.items {
            var itemKey = item.keyEquivalent
            var itemMods = item.keyEquivalentModifierMask
            if !itemKey.isEmpty, itemKey.lowercased() != itemKey {
                itemKey = itemKey.lowercased()
                itemMods.insert(.shift)
            }
            if !itemKey.isEmpty,
               itemKey == keyCharacter,
               itemMods.intersection([.command, .control, .option, .shift]) == modifiers.intersection([.command, .control, .option, .shift]) {
                return item
            }
            if let submenu = item.submenu,
               let match = findMenuItem(in: submenu, keyCharacter: keyCharacter, modifiers: modifiers) {
                return match
            }
        }
        return nil
    }

    private static func menuKeyEquivalentCharacter(for shortcut: KeyboardShortcuts.Shortcut) -> String? {
        if let key = shortcut.key {
            switch key {
            case .space: return " "
            case .return: return "\r"
            case .tab: return "\t"
            case .delete: return String(UnicodeScalar(NSBackspaceCharacter)!)
            case .deleteForward: return String(UnicodeScalar(NSDeleteCharacter)!)
            case .escape: return "\u{1b}"
            case .f1: return String(UnicodeScalar(NSF1FunctionKey)!)
            case .f2: return String(UnicodeScalar(NSF2FunctionKey)!)
            case .f3: return String(UnicodeScalar(NSF3FunctionKey)!)
            case .f4: return String(UnicodeScalar(NSF4FunctionKey)!)
            case .f5: return String(UnicodeScalar(NSF5FunctionKey)!)
            case .f6: return String(UnicodeScalar(NSF6FunctionKey)!)
            case .f7: return String(UnicodeScalar(NSF7FunctionKey)!)
            case .f8: return String(UnicodeScalar(NSF8FunctionKey)!)
            case .f9: return String(UnicodeScalar(NSF9FunctionKey)!)
            case .f10: return String(UnicodeScalar(NSF10FunctionKey)!)
            case .f11: return String(UnicodeScalar(NSF11FunctionKey)!)
            case .f12: return String(UnicodeScalar(NSF12FunctionKey)!)
            default: break
            }
        }

        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        guard let ptr = CFDataGetBytePtr(layoutData) else { return nil }
        let keyLayout = UnsafeRawPointer(ptr).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let err = UCKeyTranslate(
            keyLayout,
            UInt16(shortcut.carbonKeyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &length,
            &chars
        )
        guard err == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).lowercased()
    }

    /// `NSEvent.SpecialKey.isFunctionKey` lives inside KeyboardShortcuts and is internal, so
    /// keep our own list. These are the keys macOS lets an app claim on their own.
    private nonisolated static let functionKeys: Set<NSEvent.SpecialKey> = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
        .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20
    ]

    nonisolated static func isFunctionKey(_ event: NSEvent) -> Bool {
        guard let specialKey = event.specialKey else {
            return false
        }
        return functionKeys.contains(specialKey)
    }

    private let name: KeyboardShortcuts.Name

    @Published private(set) var isRecording = false
    @Published private(set) var shortcutDescription: String?
    /// Set when the last keystroke was refused because another binding or system rule owns it.
    @Published private(set) var conflictMessage: String?

    private var eventMonitor: Any?

    init(name: KeyboardShortcuts.Name) {
        self.name = name
        self.shortcutDescription = KeyboardShortcuts.getShortcut(for: name)?.description
    }

    private func notifyBindingsChanged() {
        NotificationCenter.default.post(name: .globalHotkeysDidChange, object: nil)
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        let token = ObjectIdentifier(self)
        Task { @MainActor in
            HotkeyRecordingCoordinator.shared.endRecording(token: token)
        }
    }

    var displayText: String {
        if isRecording {
            return "按下快捷键…"
        }
        return shortcutDescription ?? "未设置"
    }

    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func clearShortcut() {
        stopRecording(notify: false)
        KeyboardShortcuts.setShortcut(nil, for: name)
        shortcutDescription = nil
        conflictMessage = nil
        PPLogger.hotkey.notice("Global hotkey cleared by user: \(self.name.rawValue, privacy: .public)")
        notifyBindingsChanged()
    }

    func startRecording() {
        guard !isRecording else {
            return
        }

        HotkeyRecordingCoordinator.shared.beginRecording(self)
        isRecording = true
        conflictMessage = nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let stroke = KeyStroke(event: event)
            guard let self else {
                return event
            }
            MainActor.assumeIsolated {
                self.apply(outcome: Self.outcome(for: stroke))
            }
            return nil
        }
    }

    func stopRecording() {
        stopRecording(notify: true)
    }

    /// Called by `HotkeyRecordingCoordinator` when another recorder starts.
    /// Does not touch `KeyboardShortcuts.isEnabled` because the new recorder owns it.
    fileprivate func cancelFromCoordinator() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
        conflictMessage = nil
    }

    private func stopRecording(notify: Bool) {
        guard isRecording else {
            return
        }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
        HotkeyRecordingCoordinator.shared.endRecording(self)
        if notify {
            notifyBindingsChanged()
        }
    }

    private func apply(outcome: RecordingOutcome) {
        switch outcome {
        case .cancelled:
            conflictMessage = nil
            stopRecording()
        case .cleared:
            clearShortcut()
        case .rejected:
            conflictMessage = "需搭配 ⌘ / ⌥ / ⌃ 修饰键或功能键"
            NSSound.beep()
        case .recorded(let carbonKeyCode, let carbonModifiers):
            let shortcut = KeyboardShortcuts.Shortcut(
                carbonKeyCode: carbonKeyCode,
                carbonModifiers: carbonModifiers
            )
            if let reason = Self.conflictReason(for: shortcut, excluding: name) {
                conflictMessage = reason
                NSSound.beep()
                return
            }
            conflictMessage = nil
            KeyboardShortcuts.setShortcut(shortcut, for: name)
            shortcutDescription = shortcut.description
            stopRecording(notify: false)
            PPLogger.hotkey.notice("Global hotkey updated by user: \(self.name.rawValue, privacy: .public)")
            notifyBindingsChanged()
        }
    }
}

/// Click-to-record hotkey chip, styled to match the surrounding settings controls.
struct HotkeyRecorderField: View {
    @StateObject private var model: HotkeyRecorderModel
    private let autoStartRecording: Bool
    private let showsClearButton: Bool
    private let showsInlineConflict: Bool
    private let onConflictChange: ((String?) -> Void)?

    init(
        name: KeyboardShortcuts.Name,
        autoStartRecording: Bool = false,
        showsClearButton: Bool = true,
        showsInlineConflict: Bool = true,
        onConflictChange: ((String?) -> Void)? = nil
    ) {
        _model = StateObject(wrappedValue: HotkeyRecorderModel(name: name))
        self.autoStartRecording = autoStartRecording
        self.showsClearButton = showsClearButton
        self.showsInlineConflict = showsInlineConflict
        self.onConflictChange = onConflictChange
    }

    private var isConflict: Bool {
        model.isRecording && model.conflictMessage != nil
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 2) {
                Button {
                    model.toggleRecording()
                } label: {
                    Text(model.displayText)
                        .font(.ui(.body, weight: .medium, mono: !model.isRecording && model.shortcutDescription != nil))
                        .foregroundStyle(
                            isConflict
                                ? Constants.VisualStyle.danger
                                : (model.isRecording ? Constants.VisualStyle.accent : Constants.VisualStyle.text)
                        )
                        .lineLimit(1)
                        .frame(minWidth: 64, minHeight: Constants.Layout.compactControlHeight)
                        .padding(.horizontal, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    isConflict
                                        ? Constants.VisualStyle.dangerDim
                                        : (model.isRecording ? Constants.VisualStyle.accentDim : Constants.VisualStyle.inputFill)
                                )
                        )
                        .hoverHighlight(cornerRadius: 6, isEnabled: !model.isRecording)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isConflict
                                        ? Constants.VisualStyle.danger.opacity(0.45)
                                        : (model.isRecording ? Constants.VisualStyle.accentBorder : Constants.VisualStyle.border),
                                    lineWidth: model.isRecording ? 1 : Constants.Layout.hairline
                                )
                        )
                        .roundedHitTarget(cornerRadius: 6)
                }
                .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 6))
                .help(model.isRecording ? "按下想要的组合键，Esc 取消，Delete 清除" : "点击后按下新的组合键")

                if showsClearButton, model.shortcutDescription != nil, !model.isRecording {
                    Button {
                        model.clearShortcut()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.icon(.micro, weight: .semibold))
                            .foregroundStyle(Constants.VisualStyle.textTertiary)
                            .frame(width: Constants.Layout.compactControlHeight - 2, height: Constants.Layout.compactControlHeight)
                            .hoverHighlight(cornerRadius: 5)
                            .roundedHitTarget(cornerRadius: 5)
                    }
                    .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 5))
                    .help("移除这个快捷键")
                }
            }

            if showsInlineConflict, let conflict = model.conflictMessage, model.isRecording {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.icon(.micro))
                    Text(conflict)
                        .font(.ui(.caption))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Constants.VisualStyle.danger)
                .frame(maxWidth: 240, alignment: .trailing)
            }
        }
        .onChange(of: model.conflictMessage) { _, newValue in
            onConflictChange?(model.isRecording ? newValue : nil)
        }
        .onChange(of: model.isRecording) { _, isRecording in
            if !isRecording {
                onConflictChange?(nil)
            }
        }
        .onAppear {
            if autoStartRecording {
                model.startRecording()
            }
        }
        .onDisappear {
            onConflictChange?(nil)
            model.stopRecording()
        }
    }
}

/// Visible bindings for one action: every filled slot, plus at most one empty
/// slot the user just asked for with "+" (which starts recording right away).
@MainActor
final class HotkeyBindingsModel: ObservableObject {
    let action: GlobalHotkeyAction

    @Published private(set) var filledNames: [KeyboardShortcuts.Name] = []
    @Published private(set) var pendingName: KeyboardShortcuts.Name?

    private var observer: NSObjectProtocol?

    init(action: GlobalHotkeyAction) {
        self.action = action
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: .globalHotkeysDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pendingName = nil
                self?.reload()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var visibleNames: [KeyboardShortcuts.Name] {
        action.shortcutNames.filter { filledNames.contains($0) || $0 == pendingName }
    }

    var canAddBinding: Bool {
        pendingName == nil && filledNames.count < GlobalHotkeyAction.maxBindings
    }

    func addBinding() {
        guard canAddBinding else { return }
        pendingName = action.shortcutNames.first { !filledNames.contains($0) }
    }

    func reload() {
        filledNames = action.boundShortcuts().map(\.name)
    }
}

/// All bindings of one global action as removable chips plus an add button.
struct MultiHotkeyBindingsField: View {
    @StateObject private var model: HotkeyBindingsModel
    private var _activeConflicts = SwiftUI.State<[String: String]>(initialValue: [:])

    private var activeConflicts: [String: String] {
        get { _activeConflicts.wrappedValue }
        nonmutating set { _activeConflicts.wrappedValue = newValue }
    }

    init(action: GlobalHotkeyAction) {
        _model = StateObject(wrappedValue: HotkeyBindingsModel(action: action))
    }

    private var currentConflictMessage: String? {
        for name in model.visibleNames {
            if let message = activeConflicts[name.rawValue] {
                return message
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: Design.Space.sm) {
                if model.visibleNames.isEmpty {
                    Text("未设置")
                        .font(.ui(.body))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                }
                ForEach(model.visibleNames, id: \.rawValue) { name in
                    HotkeyRecorderField(
                        name: name,
                        autoStartRecording: name == model.pendingName,
                        showsInlineConflict: false,
                        onConflictChange: { message in
                            if let message {
                                activeConflicts[name.rawValue] = message
                            } else {
                                activeConflicts.removeValue(forKey: name.rawValue)
                            }
                        }
                    )
                    .id(name.rawValue)
                }
                if model.canAddBinding {
                    Button {
                        model.addBinding()
                    } label: {
                        Image(systemName: "plus")
                            .font(.icon(.small, weight: .semibold))
                            .foregroundStyle(Constants.VisualStyle.textSecondary)
                            .frame(width: Constants.Layout.compactControlHeight, height: Constants.Layout.compactControlHeight)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        Constants.VisualStyle.borderStrong,
                                        style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                                    )
                            )
                            .hoverHighlight(cornerRadius: 6)
                            .roundedHitTarget(cornerRadius: 6)
                    }
                    .buttonStyle(PPInteractiveButtonStyle(cornerRadius: 6))
                    .help(model.filledNames.isEmpty ? "添加快捷键" : "再添加一个快捷键（最多 \(GlobalHotkeyAction.maxBindings) 个）")
                }
            }
            .fixedSize()

            if let conflict = currentConflictMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.icon(.micro))
                    Text(conflict)
                        .font(.ui(.caption))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Constants.VisualStyle.danger)
                .frame(maxWidth: 260, alignment: .trailing)
            }
        }
    }
}
