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

        // Wait briefly if a physical modifier (Ctrl/Option/Shift) from the triggering hotkey
        // is still held down, so the synthetic Cmd+V is not mangled into Ctrl+Cmd+V / Opt+Cmd+V.
        waitForPhysicalModifiersRelease()

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

    /// Poll briefly up to `timeoutMs` while Ctrl / Option / Shift are physically held down
    /// so leftover trigger modifiers do not turn synthetic Cmd+V into Ctrl+Cmd+V / Opt+Cmd+V.
    private func waitForPhysicalModifiersRelease(timeoutMs: Int = 150) {
        let modifierKeyCodes: [CGKeyCode] = [
            0x3B, // Left Control
            0x3E, // Right Control
            0x3A, // Left Option
            0x3D, // Right Option
            0x38, // Left Shift
            0x3C, // Right Shift
        ]
        let stepMicros: useconds_t = 10_000
        let maxIterations = max(1, timeoutMs / 10)
        for _ in 0..<maxIterations {
            let anyHeld = modifierKeyCodes.contains { CGEventSource.keyState(.hidSystemState, key: $0) }
            if !anyHeld {
                return
            }
            usleep(stepMicros)
        }
    }
}
