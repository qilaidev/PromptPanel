import Foundation
import Cocoa

@MainActor
protocol AccessibilityPermissionProviding: AnyObject {
    var isAccessibilityGranted: Bool { get }
    func refresh()
}

enum AccessibilityResetOutcome: Equatable {
    case success
    case missingBundleIdentifier
    case launchFailed(String)
    case toolFailed(exitCode: Int32, output: String)
}

/// Service responsible for detecting and guiding accessibility permission.
@MainActor
final class PermissionService: ObservableObject, AccessibilityPermissionProviding {

    @Published private(set) var isAccessibilityGranted: Bool = false

    init() {
        refresh()
    }

    /// Refresh the current accessibility permission status.
    func refresh() {
        isAccessibilityGranted = AXIsProcessTrusted()
        PPLogger.permission.info("Accessibility permission: \(self.isAccessibilityGranted)")
    }

    /// Prompt the user to grant accessibility permission.
    /// Opens System Settings to the appropriate pane.
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        isAccessibilityGranted = trusted
        PPLogger.permission.info("Accessibility permission requested, current status: \(trusted)")
    }

    /// Open System Settings > Privacy & Security > Accessibility.
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Clear any stale TCC entry tied to a previous binary cdhash.
    ///
    /// Why: ad-hoc signed builds get a fresh cdhash on every replacement, so an
    /// existing Accessibility grant becomes a "ghost" — System Settings shows it
    /// checked but `AXIsProcessTrusted()` keeps returning false. `tccutil reset`
    /// drops the entry entirely so the next request creates a clean grant.
    @discardableResult
    func resetAccessibilityApproval() -> AccessibilityResetOutcome {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            PPLogger.permission.error("resetAccessibilityApproval: missing bundle identifier")
            return .missingBundleIdentifier
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleIdentifier]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            PPLogger.permission.error("tccutil launch failed: \(error.localizedDescription)")
            return .launchFailed(error.localizedDescription)
        }

        // Drain the pipe before waiting: if the tool writes more than the pipe
        // buffer (~64KB) it blocks on write, and waitUntilExit() would deadlock.
        let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            PPLogger.permission.error(
                "tccutil reset Accessibility \(bundleIdentifier) failed (\(process.terminationStatus)): \(output)"
            )
            return .toolFailed(exitCode: process.terminationStatus, output: output)
        }

        PPLogger.permission.info("tccutil reset Accessibility \(bundleIdentifier): \(output.isEmpty ? "ok" : output)")
        refresh()
        return .success
    }
}
