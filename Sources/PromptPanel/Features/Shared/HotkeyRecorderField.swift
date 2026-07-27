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

    private var eventMonitor: Any?

    init(name: KeyboardShortcuts.Name) {
        self.name = name
        self.shortcutDescription = KeyboardShortcuts.getShortcut(for: name)?.description
    }

    deinit {
        // `stopRecording` is main-actor isolated and deinit is not, so tear the monitor down
        // directly. Leaving a local monitor installed would keep swallowing key events for
        // the rest of the session.
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
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
        stopRecording()
        KeyboardShortcuts.setShortcut(nil, for: name)
        shortcutDescription = nil
        PPLogger.hotkey.notice("Toggle-panel hotkey cleared by user")
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
        guard isRecording else {
            return
        }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
        KeyboardShortcuts.isEnabled = true
    }

    private func apply(outcome: RecordingOutcome) {
        switch outcome {
        case .cancelled:
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
            KeyboardShortcuts.setShortcut(shortcut, for: name)
            shortcutDescription = shortcut.description
            stopRecording()
            PPLogger.hotkey.notice("Toggle-panel hotkey updated by user")
        }
    }
}

/// Click-to-record hotkey field, styled to match the surrounding settings controls.
struct HotkeyRecorderField: View {
    @StateObject private var model: HotkeyRecorderModel

    init(name: KeyboardShortcuts.Name) {
        _model = StateObject(wrappedValue: HotkeyRecorderModel(name: name))
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.toggleRecording()
            } label: {
                Text(model.displayText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(
                        model.isRecording
                            ? Constants.VisualStyle.accent
                            : Constants.VisualStyle.text
                    )
                    .frame(minWidth: 96, minHeight: Constants.Layout.compactControlHeight)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(
                                model.isRecording
                                    ? Constants.VisualStyle.accentDim
                                    : Constants.VisualStyle.tintMedium
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(
                                model.isRecording
                                    ? Constants.VisualStyle.accentBorder
                                    : Constants.VisualStyle.border,
                                lineWidth: 0.5
                            )
                    )
                    .roundedHitTarget(cornerRadius: 5)
            }
            .buttonStyle(.plain)
            .help(model.isRecording ? "按下想要的组合键，Esc 取消，Delete 清除" : "点击后按下想要的组合键")

            Button {
                model.clearShortcut()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Constants.VisualStyle.textQuaternary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("清除快捷键")
            .opacity(model.shortcutDescription == nil ? 0 : 1)
            .disabled(model.shortcutDescription == nil)
        }
        .onDisappear {
            model.stopRecording()
        }
    }
}
