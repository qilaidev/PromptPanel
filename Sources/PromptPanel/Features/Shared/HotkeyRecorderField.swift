import AppKit
import KeyboardShortcuts
import SwiftUI

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
///
/// What we give up versus the library's recorder: its "this shortcut is already used by the
/// <x> menu item / by the system" alerts. macOS silently keeps the existing owner of such a
/// shortcut, so the user-visible symptom is a hotkey that does nothing — the hint text and
/// the FAQ both tell the user to pick another combination in that case.
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
    /// Set when the last keystroke was refused because another binding owns it.
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
        // `stopRecording` is main-actor isolated and deinit is not, so tear the monitor down
        // directly. Leaving a local monitor installed would keep swallowing key events for
        // the rest of the session, and leaving `KeyboardShortcuts.isEnabled` false would
        // permanently disable the global hotkey.
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            Task { @MainActor in
                KeyboardShortcuts.isEnabled = true
            }
        }
    }

    var displayText: String {
        if isRecording {
            return conflictMessage ?? "按下快捷键…"
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

        // The current hotkey is registered with Carbon, which consumes the event before any
        // local monitor sees it. Without this the user could never re-record the combination
        // they already have, and recording would toggle the panel instead.
        KeyboardShortcuts.isEnabled = false
        isRecording = true
        conflictMessage = nil

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // The monitor runs on the main thread, but its closure is not main-actor typed and
            // NSEvent is non-Sendable — so reduce the event to plain values here and hop with
            // those only.
            let stroke = KeyStroke(event: event)
            guard let self else {
                return event
            }
            MainActor.assumeIsolated {
                self.apply(outcome: Self.outcome(for: stroke))
            }
            // Always swallow the event while recording so it never reaches the UI behind us.
            return nil
        }
    }

    func stopRecording() {
        stopRecording(notify: true)
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
        KeyboardShortcuts.isEnabled = true
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
            // Keep recording so the user can just try another combination.
            NSSound.beep()
        case .recorded(let carbonKeyCode, let carbonModifiers):
            let shortcut = KeyboardShortcuts.Shortcut(
                carbonKeyCode: carbonKeyCode,
                carbonModifiers: carbonModifiers
            )
            if let owner = GlobalHotkeyAction.conflict(for: shortcut, excluding: name) {
                // Keep recording: one keypress must never fire two actions.
                conflictMessage = "\(shortcut.description) 已用于「\(owner.title)」"
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

    init(name: KeyboardShortcuts.Name, autoStartRecording: Bool = false, showsClearButton: Bool = true) {
        _model = StateObject(wrappedValue: HotkeyRecorderModel(name: name))
        self.autoStartRecording = autoStartRecording
        self.showsClearButton = showsClearButton
    }

    private var isConflict: Bool {
        model.isRecording && model.conflictMessage != nil
    }

    var body: some View {
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
                    .frame(minWidth: 56, minHeight: Constants.Layout.compactControlHeight)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                isConflict
                                    ? Constants.VisualStyle.dangerDim
                                    : (model.isRecording ? Constants.VisualStyle.accentDim : Constants.VisualStyle.inputFill)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                model.isRecording
                                    ? Constants.VisualStyle.accentBorder
                                    : Constants.VisualStyle.border,
                                lineWidth: Constants.Layout.hairline
                            )
                    )
                    .roundedHitTarget(cornerRadius: 6)
            }
            .buttonStyle(.plain)
            .help(model.isRecording ? "按下想要的组合键，Esc 取消，Delete 清除" : "点击后按下新的组合键")

            if showsClearButton, model.shortcutDescription != nil, !model.isRecording {
                Button {
                    model.clearShortcut()
                } label: {
                    Image(systemName: "xmark")
                        .font(.icon(.micro, weight: .semibold))
                        .foregroundStyle(Constants.VisualStyle.textTertiary)
                        .frame(width: 16, height: 16)
                        .hoverHighlight(cornerRadius: 4)
                        .roundedHitTarget(cornerRadius: 4)
                }
                .buttonStyle(.plain)
                .help("移除这个快捷键")
            }
        }
        .onAppear {
            if autoStartRecording {
                model.startRecording()
            }
        }
        .onDisappear {
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

    init(action: GlobalHotkeyAction) {
        _model = StateObject(wrappedValue: HotkeyBindingsModel(action: action))
    }

    var body: some View {
        HStack(spacing: Design.Space.sm) {
            if model.visibleNames.isEmpty {
                Text("未设置")
                    .font(.ui(.body))
                    .foregroundStyle(Constants.VisualStyle.textQuaternary)
            }
            ForEach(model.visibleNames, id: \.rawValue) { name in
                HotkeyRecorderField(name: name, autoStartRecording: name == model.pendingName)
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
                .buttonStyle(.plain)
                .help(model.filledNames.isEmpty ? "添加快捷键" : "再添加一个快捷键（最多 \(GlobalHotkeyAction.maxBindings) 个）")
            }
        }
        .fixedSize()
    }
}
