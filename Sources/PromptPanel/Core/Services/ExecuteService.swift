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
    private var isExecuting = false
    private var executionStartedAt: UInt64?

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
        currentFrontApplicationProvider: @escaping () -> String?
    ) {
        self.clipboardService = clipboardService
        self.pasteService = pasteService
        self.entryRepository = entryRepository
        self.logRepository = logRepository
        self.permissionService = permissionService
        self.targetApplicationProvider = targetApplicationProvider
        self.currentFrontApplicationProvider = currentFrontApplicationProvider
    }

    /// Execute an entry: clipboard → close panel → auto-paste → fallback.
    func execute(entry: Entry, currentProjectId: String, triggerSource: Constants.ExecutionTrigger) {
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

        // Get the frontmost app bundle ID BEFORE we do anything
        let frontAppBundleId = targetApplicationProvider()

        // Step 1: Write to clipboard
        let clipboardSuccess = clipboardService.writeText(entry.content)

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
                startTime: startTime
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
        startTime: UInt64
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
