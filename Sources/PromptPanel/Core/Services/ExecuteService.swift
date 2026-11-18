import Foundation
import Cocoa

/// Orchestrates the entry execution flow:
/// 1. Write to clipboard
/// 2. Close/defocus panel
/// 3. Check permissions
/// 4. Attempt auto-paste
/// 5. Handle success/failure
@MainActor
final class ExecuteService {
    struct TargetApplicationRestoreResult {
        let observedBundleId: String?
        let durationMs: Int
    }

    private let clipboardService: ClipboardWriting
    private let pasteService: PasteDispatching
    private let entryRepository: EntryRepository
    private let logRepository: LogRepository
    private let permissionService: AccessibilityPermissionProviding
    private let targetApplicationProvider: () -> String?
    private let currentFrontApplicationProvider: () -> String?
    private let restoreClipboardEnabled: () -> Bool
    private let clipboardTextProvider: () -> String?
    private var isExecuting = false
    private var executionStartedAt: UInt64?

    static let terminalBundleIdentifiers: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "io.alacritty",
        "co.zeit.hyper",
        "com.github.wez.wezterm",
    ]

    private static let placeholderRegex = try! NSRegularExpression(
        pattern: "\\{\\{(clipboard|date)\\}\\}",
        options: [.caseInsensitive]
    )

    /// How long a single execution can legitimately stay in flight: the wait
    /// for the target app to come back, plus the settle delay, plus slack.
    static let inFlightGuardTimeoutMs =
        Constants.targetAppRestoreTimeoutMs + Constants.targetAppPasteSettleDelayMs + 500

    /// The in-flight guard stops a double-click from pasting twice. It is
    /// deliberately time-bounded: if an execution ever fails to clear the flag,
    /// a permanent guard would silently kill every later click and keystroke
    /// with nothing but a log line to show for it.
    static func shouldStartExecution(isExecuting: Bool, inFlightForMs: Int?) -> Bool {
        guard isExecuting else {
            return true
        }
        guard let inFlightForMs else {
            return true
        }
        return inFlightForMs >= inFlightGuardTimeoutMs
    }

    /// Callback to close/hide the panel before pasting.
    var onClosePanel: (() -> Void)?

    /// Callback to show a user notification.
    var onShowNotification: ((String, Bool) -> Void)?

    init(
        clipboardService: ClipboardWriting,
        pasteService: PasteDispatching,
        entryRepository: EntryRepository,
        logRepository: LogRepository,
        permissionService: AccessibilityPermissionProviding,
        targetApplicationProvider: @escaping () -> String?,
        currentFrontApplicationProvider: @escaping () -> String?,
        restoreClipboardEnabled: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: Constants.LocalDefaultsKey.restoreClipboardAfterPaste)
        },
        clipboardTextProvider: @escaping () -> String? = {
            NSPasteboard.general.string(forType: .string)
        }
    ) {
        self.clipboardService = clipboardService
        self.pasteService = pasteService
        self.entryRepository = entryRepository
        self.logRepository = logRepository
        self.permissionService = permissionService
        self.targetApplicationProvider = targetApplicationProvider
        self.currentFrontApplicationProvider = currentFrontApplicationProvider
        self.restoreClipboardEnabled = restoreClipboardEnabled
        self.clipboardTextProvider = clipboardTextProvider
    }

    /// Expands runtime placeholders (`{{clipboard}}`, `{{date}}` case-insensitively)
    /// and strips trailing newlines when pasting multiline or code entries into terminals.
    static func resolveContent(
        for entry: Entry,
        clipboardText: @autoclosure () -> String?,
        now: Date = Date(),
        targetBundleId: String?
    ) -> String {
        var resolved = entry.content

        let fullRange = NSRange(resolved.startIndex..., in: resolved)
        let matches = placeholderRegex.matches(in: resolved, range: fullRange)
        if !matches.isEmpty {
            var expanded = ""
            expanded.reserveCapacity(resolved.count)
            var currentIndex = resolved.startIndex
            var cachedClipboard: String?
            var didReadClipboard = false
            var cachedDate: String?

            for match in matches {
                guard let matchRange = Range(match.range, in: resolved),
                      let tokenRange = Range(match.range(at: 1), in: resolved) else {
                    continue
                }
                expanded.append(contentsOf: resolved[currentIndex..<matchRange.lowerBound])
                switch resolved[tokenRange].lowercased() {
                case "clipboard":
                    if !didReadClipboard {
                        cachedClipboard = clipboardText() ?? ""
                        didReadClipboard = true
                    }
                    expanded.append(cachedClipboard ?? "")
                case "date":
                    if cachedDate == nil {
                        cachedDate = formatLocalDate(now)
                    }
                    expanded.append(cachedDate ?? "")
                default:
                    expanded.append(contentsOf: resolved[matchRange])
                }
                currentIndex = matchRange.upperBound
            }
            expanded.append(contentsOf: resolved[currentIndex...])
            resolved = expanded
        }

        // Prevent synthetic ⌘V from auto-submitting the final line inside terminal prompts.
        if let targetBundleId,
           terminalBundleIdentifiers.contains(targetBundleId),
           (entry.type == Constants.EntryType.code.rawValue
            || resolved.unicodeScalars.contains(where: { $0 == "\n" || $0 == "\r" })) {
            while let lastScalar = resolved.unicodeScalars.last,
                  lastScalar == "\n" || lastScalar == "\r" {
                resolved.unicodeScalars.removeLast()
            }
        }

        return resolved
    }

    private static func formatLocalDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// The clipboard as it was before an execution overwrote it, to be put back
    /// once the paste has landed.
    private struct ClipboardRestorePlan {
        let snapshotter: ClipboardSnapshotting
        let snapshot: ClipboardSnapshot
        let changeCountAfterWrite: Int
    }

    /// Execute an entry: clipboard → close panel → auto-paste → fallback.
    func execute(entry: Entry, currentProjectId: String, triggerSource: Constants.ExecutionTrigger) {
        run(
            entry: entry,
            currentProjectId: currentProjectId,
            triggerSource: triggerSource,
            frontAppBundleId: targetApplicationProvider()
        )
    }

    /// Execute without the panel: the target is whatever app is frontmost right now
    /// (used by the "重贴上一条词条" global hotkey). The panel's remembered target
    /// would be stale here and turn every repeat into a clipboard-only fallback.
    func executeInPlace(entry: Entry, currentProjectId: String) {
        run(
            entry: entry,
            currentProjectId: currentProjectId,
            triggerSource: .globalHotkey,
            frontAppBundleId: currentFrontApplicationProvider()
        )
    }

    private func run(
        entry: Entry,
        currentProjectId: String,
        triggerSource: Constants.ExecutionTrigger,
        frontAppBundleId: String?
    ) {
        let inFlightForMs = executionStartedAt.map { elapsedMilliseconds(since: $0) }
        guard Self.shouldStartExecution(isExecuting: isExecuting, inFlightForMs: inFlightForMs) else {
            PPLogger.execute.warning(
                "Ignored execute request because another execution is still in flight: entry=\(entry.id), trigger=\(triggerSource.rawValue), in_flight_ms=\(inFlightForMs ?? -1)"
            )
            return
        }
        if isExecuting {
            PPLogger.execute.error(
                "Releasing a stuck in-flight execution guard after \(inFlightForMs ?? -1) ms so the panel stays usable"
            )
        }
        isExecuting = true
        executionStartedAt = DispatchTime.now().uptimeNanoseconds
        PPLogger.execute.info(
            "Executing entry: \(entry.id), trigger=\(triggerSource.rawValue), project=\(currentProjectId)"
        )
        let startTime = DispatchTime.now().uptimeNanoseconds

        // Step 1: Resolve dynamic placeholders and terminal safety guard before
        // overwriting the clipboard (snapshotting the previous contents first when
        // the user asked for them to be restored after the paste).
        let resolvedContent = Self.resolveContent(
            for: entry,
            clipboardText: clipboardTextProvider(),
            targetBundleId: frontAppBundleId
        )

        var restorePlan: ClipboardRestorePlan?
        let clipboardSuccess: Bool
        if restoreClipboardEnabled(),
           let snapshotter = clipboardService as? ClipboardSnapshotting,
           let snapshot = snapshotter.captureSnapshot() {
            if let changeCount = snapshotter.writeTransientText(resolvedContent) {
                restorePlan = ClipboardRestorePlan(
                    snapshotter: snapshotter,
                    snapshot: snapshot,
                    changeCountAfterWrite: changeCount
                )
                clipboardSuccess = true
            } else {
                clipboardSuccess = false
            }
        } else {
            clipboardSuccess = clipboardService.writeText(resolvedContent)
        }

        guard clipboardSuccess else {
            // Clipboard write failed — cannot proceed
            PPLogger.execute.error("Clipboard write failed for entry \(entry.id)")
            logExecution(
                entry: entry,
                projectId: currentProjectId,
                frontAppBundleId: frontAppBundleId,
                observedAppBundleId: currentFrontApplicationProvider(),
                clipboardSuccess: false,
                pasteAttempted: false,
                pasteSuccess: false,
                result: .failed,
                triggerSource: triggerSource,
                failureReason: .clipboardWriteFailed,
                targetAppRestoreDurationMs: nil,
                totalDurationMs: elapsedMilliseconds(since: startTime)
            )
            onShowNotification?("复制失败，请重试", false)
            finishExecution()
            return
        }

        // Step 2: Close panel to return focus to original app
        onClosePanel?()

        Task { [weak self] in
            guard let self else { return }
            let restoreResult = await self.waitForTargetApplicationRestore(expectedBundleId: frontAppBundleId)
            self.performPaste(
                entry: entry,
                projectId: currentProjectId,
                frontAppBundleId: frontAppBundleId,
                restoreResult: restoreResult,
                triggerSource: triggerSource,
                startTime: startTime,
                restorePlan: restorePlan
            )
            self.finishExecution()
        }
    }

    private func finishExecution() {
        isExecuting = false
        executionStartedAt = nil
    }

    private func waitForTargetApplicationRestore(expectedBundleId: String?) async -> TargetApplicationRestoreResult {
        let waitStartedAt = DispatchTime.now().uptimeNanoseconds
        let ownBundleId = Bundle.main.bundleIdentifier

        var observedBundleId = currentFrontApplicationProvider()
        let timeoutNs = UInt64(Constants.targetAppRestoreTimeoutMs) * 1_000_000
        let pollNs = UInt64(Constants.targetAppRestorePollIntervalMs) * 1_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNs

        // Without a recorded target — the panel was opened from the tray, or
        // while PromptPanel was already frontmost — there is still something to
        // wait for: focus leaving PromptPanel. Returning immediately used to
        // fire ⌘V into our own app microseconds after `orderOut`.
        func hasSettled() -> Bool {
            if let expectedBundleId {
                return observedBundleId == expectedBundleId
            }
            guard let ownBundleId else {
                return true
            }
            return observedBundleId != ownBundleId
        }

        while hasSettled() == false && DispatchTime.now().uptimeNanoseconds < deadline {
            try? await Task.sleep(nanoseconds: pollNs)
            observedBundleId = currentFrontApplicationProvider()
        }

        if hasSettled() {
            try? await Task.sleep(nanoseconds: UInt64(Constants.targetAppPasteSettleDelayMs) * 1_000_000)
            observedBundleId = currentFrontApplicationProvider()
        }

        let durationMs = elapsedMilliseconds(since: waitStartedAt)
        PPLogger.execute.info(
            "target_app_restore_completed expected=\(expectedBundleId ?? "unknown") observed=\(observedBundleId ?? "unknown") duration_ms=\(durationMs)"
        )
        return TargetApplicationRestoreResult(
            observedBundleId: observedBundleId,
            durationMs: durationMs
        )
    }

    private func performPaste(
        entry: Entry,
        projectId: String,
        frontAppBundleId: String?,
        restoreResult: TargetApplicationRestoreResult,
        triggerSource: Constants.ExecutionTrigger,
        startTime: UInt64,
        restorePlan: ClipboardRestorePlan? = nil
    ) {
        // Step 3: Check accessibility permission
        permissionService.refresh()
        let hasPermission = permissionService.isAccessibilityGranted

        guard hasPermission else {
            // No permission — clipboard-only mode
            PPLogger.execute.info("No accessibility permission; clipboard-only mode")
            logExecution(
                entry: entry,
                projectId: projectId,
                frontAppBundleId: frontAppBundleId,
                observedAppBundleId: restoreResult.observedBundleId,
                clipboardSuccess: true,
                pasteAttempted: false,
                pasteSuccess: false,
                result: .clipboardOnly,
                triggerSource: triggerSource,
                failureReason: .accessibilityNotGranted,
                targetAppRestoreDurationMs: restoreResult.durationMs,
                totalDurationMs: elapsedMilliseconds(since: startTime)
            )
            recordUsage(entry: entry)
            onShowNotification?("已复制到剪贴板，可手动粘贴 (⌘V)", true)
            return
        }

        if Self.isTargetApplicationRestoreMismatch(expectedBundleId: frontAppBundleId, observedBundleId: restoreResult.observedBundleId) {
            PPLogger.execute.warning(
                "Target app not restored before paste: expected=\(frontAppBundleId ?? "unknown"), observed=\(restoreResult.observedBundleId ?? "unknown"), duration_ms=\(restoreResult.durationMs)"
            )
            logExecution(
                entry: entry,
                projectId: projectId,
                frontAppBundleId: frontAppBundleId,
                observedAppBundleId: restoreResult.observedBundleId,
                clipboardSuccess: true,
                pasteAttempted: false,
                pasteSuccess: false,
                result: .clipboardOnly,
                triggerSource: triggerSource,
                failureReason: .targetAppNotRestored,
                targetAppRestoreDurationMs: restoreResult.durationMs,
                totalDurationMs: elapsedMilliseconds(since: startTime)
            )
            recordUsage(entry: entry)
            onShowNotification?("已复制，原应用未恢复焦点，请手动粘贴 (⌘V)", true)
            return
        }

        // Step 4: Attempt auto-paste
        let pasteResult = pasteService.attemptPaste()

        switch pasteResult {
        case .dispatched:
            PPLogger.execute.info("Auto-paste succeeded for entry \(entry.id)")
            logExecution(
                entry: entry,
                projectId: projectId,
                frontAppBundleId: frontAppBundleId,
                observedAppBundleId: restoreResult.observedBundleId,
                clipboardSuccess: true,
                pasteAttempted: true,
                pasteSuccess: true,
                result: .success,
                triggerSource: triggerSource,
                targetAppRestoreDurationMs: restoreResult.durationMs,
                totalDurationMs: elapsedMilliseconds(since: startTime)
            )
            recordUsage(entry: entry)
            scheduleClipboardRestore(restorePlan)
            // No notification needed on success — user sees content appear
        case .accessibilityNotGranted:
            PPLogger.execute.warning("Accessibility permission disappeared before paste for entry \(entry.id)")
            logExecution(
                entry: entry,
                projectId: projectId,
                frontAppBundleId: frontAppBundleId,
                observedAppBundleId: restoreResult.observedBundleId,
                clipboardSuccess: true,
                pasteAttempted: true,
                pasteSuccess: false,
                result: .clipboardOnly,
                triggerSource: triggerSource,
                failureReason: .accessibilityNotGranted,
                targetAppRestoreDurationMs: restoreResult.durationMs,
                totalDurationMs: elapsedMilliseconds(since: startTime)
            )
            recordUsage(entry: entry)
            onShowNotification?("已复制到剪贴板，可手动粘贴 (⌘V)", true)
        case .eventCreationFailed:
            PPLogger.execute.warning("Auto-paste event creation failed for entry \(entry.id); clipboard fallback")
            logExecution(
                entry: entry,
                projectId: projectId,
                frontAppBundleId: frontAppBundleId,
                observedAppBundleId: restoreResult.observedBundleId,
                clipboardSuccess: true,
                pasteAttempted: true,
                pasteSuccess: false,
                result: .clipboardOnly,
                triggerSource: triggerSource,
                failureReason: .pasteEventCreationFailed,
                targetAppRestoreDurationMs: restoreResult.durationMs,
                totalDurationMs: elapsedMilliseconds(since: startTime)
            )
            recordUsage(entry: entry)
            onShowNotification?("已复制，可手动粘贴 (⌘V)", true)
        }
    }

    /// Whether the keystroke would land somewhere other than the app the user
    /// was in when the panel opened.
    ///
    /// `ownBundleId` matters as much as the expected target: the ⌘V is posted to
    /// the HID event tap, so it goes to whatever is frontmost *at that instant*.
    /// If PromptPanel has not yet yielded focus the paste lands back in our own
    /// window — silently, and logged as a success. Refusing to paste into
    /// ourselves is the only way that failure becomes visible to the user.
    static func isTargetApplicationRestoreMismatch(
        expectedBundleId: String?,
        observedBundleId: String?,
        ownBundleId: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        if let observedBundleId, let ownBundleId, observedBundleId == ownBundleId {
            return true
        }
        guard let expectedBundleId, let observedBundleId else {
            return false
        }
        return expectedBundleId != observedBundleId
    }

    /// Only called after a dispatched paste. When the paste fell back to
    /// clipboard-only, the entry must stay on the clipboard for a manual ⌘V.
    private func scheduleClipboardRestore(_ plan: ClipboardRestorePlan?) {
        guard let plan else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Constants.clipboardRestoreDelayMs) * 1_000_000)
            plan.snapshotter.restore(plan.snapshot, ifChangeCountIs: plan.changeCountAfterWrite)
        }
    }

    private func recordUsage(entry: Entry) {
        do {
            try entryRepository.recordExecution(id: entry.id)
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
        } catch {
            PPLogger.execute.error("Failed to record usage: \(error.localizedDescription)")
        }
    }

    private func logExecution(
        entry: Entry,
        projectId: String,
        frontAppBundleId: String?,
        observedAppBundleId: String?,
        clipboardSuccess: Bool,
        pasteAttempted: Bool,
        pasteSuccess: Bool,
        result: Constants.ExecutionResult,
        triggerSource: Constants.ExecutionTrigger,
        failureReason: Constants.ExecutionFailureReason? = nil,
        targetAppRestoreDurationMs: Int? = nil,
        totalDurationMs: Int? = nil
    ) {
        let log = ExecutionLog(
            entryId: entry.id,
            projectId: projectId,
            frontAppBundleId: frontAppBundleId,
            observedAppBundleId: observedAppBundleId,
            hasAccessibility: permissionService.isAccessibilityGranted,
            clipboardSuccess: clipboardSuccess,
            pasteAttempted: pasteAttempted,
            pasteSuccess: pasteSuccess,
            result: result.rawValue,
            triggerSource: triggerSource.rawValue,
            failureReason: failureReason?.rawValue,
            targetAppRestoreDurationMs: targetAppRestoreDurationMs,
            totalDurationMs: totalDurationMs
        )
        do {
            try logRepository.record(log)
            NotificationCenter.default.post(name: .executionLogsDidChange, object: nil)
            if let totalDurationMs {
                warnIfExecutionSlow(durationMs: totalDurationMs, result: result, failureReason: failureReason)
            }
        } catch {
            PPLogger.execute.error("Failed to write execution log: \(error.localizedDescription)")
        }
    }

    private func warnIfExecutionSlow(
        durationMs: Int,
        result: Constants.ExecutionResult,
        failureReason: Constants.ExecutionFailureReason?
    ) {
        guard durationMs > Constants.executionLatencyTargetMs else {
            return
        }

        PPLogger.execute.warning(
            "execution_latency_exceeded duration_ms=\(durationMs) target_ms=\(Constants.executionLatencyTargetMs) result=\(result.rawValue) failure_reason=\(failureReason?.rawValue ?? "none")"
        )
    }

    private func elapsedMilliseconds(since startTime: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000)
    }
}
