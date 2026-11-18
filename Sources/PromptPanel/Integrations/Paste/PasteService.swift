import Cocoa
import ApplicationServices

protocol PasteDispatching {
    func attemptPaste() -> PasteService.PasteDispatchResult
}

/// Manages auto-paste by simulating Cmd+V via CGEvent.
/// Requires Accessibility permission.
final class PasteService: PasteDispatching {

    enum PasteDispatchResult {
        case dispatched
        case accessibilityNotGranted
        case eventCreationFailed
    }

    /// Attempt to auto-paste by simulating Cmd+V.
    func attemptPaste() -> PasteDispatchResult {
        guard checkAccessibility() else {
            PPLogger.paste.warning("Accessibility permission not granted; cannot auto-paste")
            return .accessibilityNotGranted
        }

        guard let eventSource = CGEventSource(stateID: .hidSystemState) else {
            PPLogger.paste.error("Failed to create HID event source")
            return .eventCreationFailed
        }

        // Create a Cmd+V key down event
        guard let keyDownEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: true) else {
            PPLogger.paste.error("Failed to create key down event")
            return .eventCreationFailed
        }
        keyDownEvent.flags = .maskCommand

        // Create a Cmd+V key up event
        guard let keyUpEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0x09, keyDown: false) else {
            PPLogger.paste.error("Failed to create key up event")
            return .eventCreationFailed
        }
        keyUpEvent.flags = .maskCommand

        // Post keyDown immediately, then keyUp after ~10ms so Electron/Chromium/terminal
        // apps reliably register the synthetic Cmd+V chord.
        keyDownEvent.post(tap: .cghidEventTap)
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + .milliseconds(10)) {
            keyUpEvent.post(tap: .cghidEventTap)
        }

        PPLogger.paste.debug("Auto-paste Cmd+V events dispatched")
        return .dispatched
    }

    /// Check if accessibility permission is granted.
    func checkAccessibility() -> Bool {
        let trusted = AXIsProcessTrusted()
        PPLogger.paste.debug("Accessibility check: \(trusted)")
        return trusted
    }
}
