import Foundation

struct PanelFocusResult {
    let token: Int
    let succeeded: Bool
    let attempt: Int
    let appIsActive: Bool
    let windowIsVisible: Bool
    let windowIsKey: Bool
    let windowIsMain: Bool
    let firstResponderMatches: Bool
    let hasEditor: Bool

    init(
        token: Int,
        succeeded: Bool,
        attempt: Int = 0,
        appIsActive: Bool = false,
        windowIsVisible: Bool = false,
        windowIsKey: Bool = false,
        windowIsMain: Bool = false,
        firstResponderMatches: Bool = false,
        hasEditor: Bool = false
    ) {
        self.token = token
        self.succeeded = succeeded
        self.attempt = attempt
        self.appIsActive = appIsActive
        self.windowIsVisible = windowIsVisible
        self.windowIsKey = windowIsKey
        self.windowIsMain = windowIsMain
        self.firstResponderMatches = firstResponderMatches
        self.hasEditor = hasEditor
    }
}

struct PanelActivationSnapshot {
    let appIsActive: Bool
    let panelIsVisible: Bool
    let panelIsKey: Bool

    var isStable: Bool {
        appIsActive && panelIsVisible && panelIsKey
    }

    init(appIsActive: Bool, panelIsVisible: Bool, panelIsKey: Bool) {
        self.appIsActive = appIsActive
        self.panelIsVisible = panelIsVisible
        self.panelIsKey = panelIsKey
    }
}

struct PanelOpenTrace {
    let id: String
    let hotkeyTriggeredAt: Date
    let hotkeyTriggeredUptimeNs: UInt64
    var panelShownAt: Date?
    var panelShownUptimeNs: UInt64?
    var searchFieldFocusedAt: Date?
    var searchFieldFocusedUptimeNs: UInt64?

    init(
        id: String = UUID().uuidString,
        hotkeyTriggeredAt: Date = Date(),
        hotkeyTriggeredUptimeNs: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) {
        self.id = id
        self.hotkeyTriggeredAt = hotkeyTriggeredAt
        self.hotkeyTriggeredUptimeNs = hotkeyTriggeredUptimeNs
    }

    var hotkeyToPanelShownMs: Int? {
        guard let panelShownUptimeNs else {
            return nil
        }
        return Int((panelShownUptimeNs - hotkeyTriggeredUptimeNs) / 1_000_000)
    }

    var hotkeyToSearchFieldFocusedMs: Int? {
        guard let searchFieldFocusedUptimeNs else {
            return nil
        }
        return Int((searchFieldFocusedUptimeNs - hotkeyTriggeredUptimeNs) / 1_000_000)
    }
}

@MainActor
final class PanelOpenTracker {
    private(set) var currentTrace: PanelOpenTrace?

    func markHotkeyTriggered() {
        let trace = PanelOpenTrace()
        currentTrace = trace
        PPLogger.hotkey.info("hotkey_triggered_at=\(trace.hotkeyTriggeredAt.ISO8601Format()) trace_id=\(trace.id)")
    }

    func markPanelShown() {
        guard var trace = currentTrace else {
            return
        }

        let now = Date()
        trace.panelShownAt = now
        trace.panelShownUptimeNs = DispatchTime.now().uptimeNanoseconds
        currentTrace = trace

        PPLogger.panel.info(
            "panel_shown_at=\(now.ISO8601Format()) trace_id=\(trace.id) hotkey_to_panel_ms=\(trace.hotkeyToPanelShownMs ?? -1)"
        )
    }

    func recordPanelActivationCheck(attempt: Int, snapshot: PanelActivationSnapshot, final: Bool) {
        guard let trace = currentTrace else {
            return
        }

        let status = snapshot.isStable ? "stable" : (final ? "failed" : "retrying")
        if snapshot.isStable {
            PPLogger.panel.info(
                "panel_activation_check trace_id=\(trace.id) attempt=\(attempt) status=\(status) app_active=\(snapshot.appIsActive) panel_visible=\(snapshot.panelIsVisible) panel_key=\(snapshot.panelIsKey)"
            )
        } else {
            PPLogger.panel.warning(
                "panel_activation_check trace_id=\(trace.id) attempt=\(attempt) status=\(status) app_active=\(snapshot.appIsActive) panel_visible=\(snapshot.panelIsVisible) panel_key=\(snapshot.panelIsKey)"
            )
        }
    }

    func markSearchFieldFocused(_ result: PanelFocusResult) {
        guard var trace = currentTrace else {
            return
        }

        if result.succeeded {
            let now = Date()
            trace.searchFieldFocusedAt = now
            trace.searchFieldFocusedUptimeNs = DispatchTime.now().uptimeNanoseconds
            currentTrace = trace

            let hotkeyToFocusMs = trace.hotkeyToSearchFieldFocusedMs ?? -1
            PPLogger.panel.info(
                "search_field_focused_at=\(now.ISO8601Format()) trace_id=\(trace.id) focus_token=\(result.token) attempt=\(result.attempt) hotkey_to_focus_ms=\(hotkeyToFocusMs) app_active=\(result.appIsActive) window_visible=\(result.windowIsVisible) window_key=\(result.windowIsKey) window_main=\(result.windowIsMain) responder_match=\(result.firstResponderMatches) has_editor=\(result.hasEditor)"
            )

            if hotkeyToFocusMs > Constants.panelOpenLatencyTargetMs {
                PPLogger.panel.warning(
                    "panel_open_latency_exceeded trace_id=\(trace.id) hotkey_to_focus_ms=\(hotkeyToFocusMs) target_ms=\(Constants.panelOpenLatencyTargetMs)"
                )
            }
        } else {
            PPLogger.panel.warning(
                "search_field_focus_failed trace_id=\(trace.id) focus_token=\(result.token) attempt=\(result.attempt) app_active=\(result.appIsActive) window_visible=\(result.windowIsVisible) window_key=\(result.windowIsKey) window_main=\(result.windowIsMain) responder_match=\(result.firstResponderMatches) has_editor=\(result.hasEditor)"
            )
        }
    }

    func cancelCurrentTrace(reason: String) {
        guard let trace = currentTrace else {
            return
        }
        PPLogger.panel.info("panel_open_trace_cancelled trace_id=\(trace.id) reason=\(reason)")
        currentTrace = nil
    }
}
