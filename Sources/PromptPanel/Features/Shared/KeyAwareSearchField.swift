import AppKit
import SwiftUI

struct KeyAwareSearchField: NSViewRepresentable {
    @Binding var text: String

    let placeholder: String
    let focusToken: Int
    let onMoveSelection: (QuickPanelViewModel.SelectionDirection) -> Void
    let onSubmit: () -> Void
    var onQuickCreateNote: () -> Void = {}
    var onQuickCreateTodo: () -> Void = {}
    var onCycleScope: (Int) -> Void = { _ in }
    let onEscape: () -> Void
    let onFocusResolved: (PanelFocusResult) -> Void

    func makeNSView(context: Context) -> PromptSearchField {
        let field = PromptSearchField()
        field.delegate = context.coordinator
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.46)
            ]
        )
        // Must match the SwiftUI placeholder drawn on top of this field
        // (`Design.TextSize.title`), otherwise the text jumps a point when the
        // user starts typing.
        field.font = .systemFont(ofSize: Design.TextSize.title.rawValue)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        // Arrow keys, Tab scope cycling, and Return variants. ⌘-combinations and
        // Esc are claimed by `PanelService`'s local event monitor, which runs
        // ahead of this and keeps working after focus leaves the field; the cases
        // below stay as a fallback for when the field itself is first responder.
        let coordinator = context.coordinator
        field.keyHandler = { [weak field] event in
            if (field?.currentEditor() as? NSTextView)?.hasMarkedText() == true {
                return false
            }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            switch Int(event.keyCode) {
            case 126:
                coordinator.onMoveSelection?(.up)
                return true
            case 125:
                coordinator.onMoveSelection?(.down)
                return true
            case 48:
                if flags == [.shift] {
                    coordinator.onCycleScope?(-1)
                    return true
                } else if flags.isEmpty {
                    coordinator.onCycleScope?(1)
                    return true
                }
                return false
            case 36, 76:
                if flags == [.shift] {
                    coordinator.onQuickCreateNote?()
                    return true
                } else if flags == [.option] {
                    coordinator.onQuickCreateTodo?()
                    return true
                } else if flags.isEmpty {
                    coordinator.onSubmit?()
                    return true
                }
                return false
            case 53:
                coordinator.onEscape?()
                return true
            default:
                return false
            }
        }
        return field
    }

    func updateNSView(_ nsView: PromptSearchField, context: Context) {
        if nsView.stringValue != text || nsView.currentEditor()?.string != text {
            nsView.setDisplayedText(text)
        }

        context.coordinator.onMoveSelection = onMoveSelection
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onQuickCreateNote = onQuickCreateNote
        context.coordinator.onQuickCreateTodo = onQuickCreateTodo
        context.coordinator.onCycleScope = onCycleScope
        context.coordinator.onEscape = onEscape
        context.coordinator.focusResolveHandler = onFocusResolved

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            if focusToken > 0 {
                context.coordinator.scheduleFocus(
                    on: nsView,
                    focusToken: focusToken,
                    onFocusResolved: onFocusResolved
                )
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String
        var lastFocusToken: Int = 0
        var focusResolveHandler: ((PanelFocusResult) -> Void)?
        var onMoveSelection: ((QuickPanelViewModel.SelectionDirection) -> Void)?
        var onSubmit: (() -> Void)?
        var onQuickCreateNote: (() -> Void)?
        var onQuickCreateTodo: (() -> Void)?
        var onCycleScope: ((Int) -> Void)?
        var onEscape: (() -> Void)?
        private var reportedSuccessfulFocusToken: Int = -1

        init(text: Binding<String>) {
            self._text = text
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            guard let field = notification.object as? PromptSearchField else {
                return
            }
            reportSuccessfulFocusIfNeeded(field: field, attempt: Constants.panelFocusMaxAttempts)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else {
                return
            }
            text = field.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if textView.hasMarkedText() {
                return false
            }
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                onMoveSelection?(.up)
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMoveSelection?(.down)
                return true
            case #selector(NSResponder.insertTab(_:)):
                onCycleScope?(1)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                onCycleScope?(-1)
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                let flags = (NSApp.currentEvent?.modifierFlags ?? []).intersection([.command, .shift, .option, .control])
                if flags == [.shift] {
                    onQuickCreateNote?()
                    return true
                } else if flags == [.option] {
                    onQuickCreateTodo?()
                    return true
                }
                onSubmit?()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onEscape?()
                return true
            default:
                return false
            }
        }

        func scheduleFocus(
            on field: PromptSearchField,
            focusToken: Int,
            onFocusResolved: @escaping (PanelFocusResult) -> Void
        ) {
            guard focusToken > 0 else {
                return
            }
            focusResolveHandler = onFocusResolved
            reportedSuccessfulFocusToken = -1
            attemptFocus(
                on: field,
                focusToken: focusToken,
                remainingAttempts: Constants.panelFocusMaxAttempts,
                attempt: 0,
                onFocusResolved: onFocusResolved
            )
        }

        private func attemptFocus(
            on field: PromptSearchField,
            focusToken: Int,
            remainingAttempts: Int,
            attempt: Int,
            onFocusResolved: @escaping (PanelFocusResult) -> Void
        ) {
            let delayMs = attempt == 0 ? 0 : Constants.panelFocusRetryDelayMs
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self, weak field] in
                guard let self, let field else {
                    return
                }
                guard self.lastFocusToken == focusToken else {
                    return
                }
                guard field.window?.isVisible == true else {
                    if remainingAttempts > 0 {
                        self.attemptFocus(
                            on: field,
                            focusToken: focusToken,
                            remainingAttempts: remainingAttempts - 1,
                            attempt: attempt + 1,
                            onFocusResolved: onFocusResolved
                        )
                    } else {
                        onFocusResolved(self.makeFocusResult(field: field, token: focusToken, attempt: attempt))
                    }
                    return
                }

                self.activateWindowIfNeeded(for: field)
                if field.currentEditor() == nil {
                    _ = field.window?.makeFirstResponder(field)
                }
                if let editor = field.currentEditor() as? NSTextView {
                    editor.insertionPointColor = NSColor(srgbRed: 0.49, green: 0.55, blue: 0.97, alpha: 1.0)
                }
                let endLocation = (field.stringValue as NSString).length
                field.currentEditor()?.selectedRange = NSRange(location: endLocation, length: 0)
                let focusResult = self.makeFocusResult(field: field, token: focusToken, attempt: attempt)

                if focusResult.succeeded {
                    self.reportSuccessfulFocusIfNeeded(result: focusResult)
                } else if remainingAttempts > 0 {
                    self.attemptFocus(
                        on: field,
                        focusToken: focusToken,
                        remainingAttempts: remainingAttempts - 1,
                        attempt: attempt + 1,
                        onFocusResolved: onFocusResolved
                    )
                } else {
                    onFocusResolved(focusResult)
                }
            }
        }

        private func makeFocusResult(field: PromptSearchField, token: Int, attempt: Int) -> PanelFocusResult {
            let window = field.window
            let hasEditor = field.currentEditor() != nil
            let firstResponderMatches = window?.firstResponder === field
            let appIsActive = NSApp.isActive
            let windowIsVisible = window?.isVisible ?? false
            let windowIsKey = window?.isKeyWindow ?? false
            let windowIsMain = window?.isMainWindow ?? false
            return PanelFocusResult(
                token: token,
                succeeded: PanelFocusResult.interactionReady(
                    appIsActive: appIsActive,
                    windowIsVisible: windowIsVisible,
                    windowIsKey: windowIsKey,
                    firstResponderMatches: firstResponderMatches,
                    hasEditor: hasEditor
                ),
                attempt: attempt,
                appIsActive: appIsActive,
                windowIsVisible: windowIsVisible,
                windowIsKey: windowIsKey,
                windowIsMain: windowIsMain,
                firstResponderMatches: firstResponderMatches,
                hasEditor: hasEditor
            )
        }

        private func activateWindowIfNeeded(for field: PromptSearchField) {
            guard let window = field.window, window.isVisible else {
                return
            }

            if NSApp.isActive == false {
                _ = NSRunningApplication.current.activate(options: [])
                NSApp.activate(ignoringOtherApps: true)
            }
            if window.isKeyWindow == false {
                window.makeKeyAndOrderFront(nil)
            }
            if window.isMainWindow == false {
                window.makeMain()
            }
        }

        private func reportSuccessfulFocusIfNeeded(field: PromptSearchField, attempt: Int) {
            guard lastFocusToken > 0 else {
                return
            }
            let result = makeFocusResult(field: field, token: lastFocusToken, attempt: attempt)
            guard result.succeeded else {
                return
            }
            reportSuccessfulFocusIfNeeded(result: result)
        }

        private func reportSuccessfulFocusIfNeeded(result: PanelFocusResult) {
            guard reportedSuccessfulFocusToken != result.token else {
                return
            }
            guard let focusResolveHandler else {
                return
            }
            reportedSuccessfulFocusToken = result.token
            focusResolveHandler(result)
        }
    }
}

extension PanelFocusResult {
    static func interactionReady(
        appIsActive: Bool,
        windowIsVisible: Bool,
        windowIsKey: Bool,
        firstResponderMatches: Bool,
        hasEditor: Bool
    ) -> Bool {
        appIsActive && windowIsVisible && windowIsKey && (firstResponderMatches || hasEditor)
    }
}

final class PromptSearchField: NSSearchField {
    var keyHandler: ((NSEvent) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAppearance()
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        focusForImmediateTyping()
        super.mouseDown(with: event)
        focusForImmediateTyping()
    }

    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification)
        applyAppearance(isFocused: true)
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        applyAppearance(isFocused: false)
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            applyAppearance(isFocused: true)
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            applyAppearance(isFocused: false)
        }
        return didResignFirstResponder
    }

    func setDisplayedText(_ text: String) {
        stringValue = text
        currentEditor()?.string = text
        currentEditor()?.selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }

    private func focusForImmediateTyping() {
        if NSApp.isActive == false {
            _ = NSRunningApplication.current.activate(options: [])
            NSApp.activate(ignoringOtherApps: true)
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
    }

    private func configureAppearance() {
        focusRingType = .none
        isBordered = false
        drawsBackground = false
        wantsLayer = true
        maximumRecents = 0
        recentsAutosaveName = nil
        translatesAutoresizingMaskIntoConstraints = false
        lineBreakMode = .byTruncatingTail
        cell?.usesSingleLineMode = true
        if let searchCell = cell as? NSSearchFieldCell {
            searchCell.searchButtonCell = nil
            searchCell.cancelButtonCell = nil
        }
        applyAppearance(isFocused: false)
    }

    private func applyAppearance(isFocused: Bool) {
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = NSColor(srgbRed: 0.49, green: 0.55, blue: 0.97, alpha: 1.0)
        }
        guard let layer else {
            return
        }

        layer.cornerRadius = 0
        layer.borderWidth = 0
        layer.backgroundColor = NSColor.clear.cgColor
        layer.borderColor = NSColor.clear.cgColor
        layer.shadowOpacity = 0
        layer.shadowRadius = 0
        layer.shadowOffset = .zero
    }
}
