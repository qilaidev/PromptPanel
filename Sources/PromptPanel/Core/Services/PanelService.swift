import Cocoa

/// Manages the quick panel (NSPanel) lifecycle:
/// show, hide, toggle, focus control, Esc/click-outside behavior.
@MainActor
final class PanelService {
    enum ActivationAction: Equatable {
        case stable
        case retry(nextAttempt: Int)
        case failed
    }

    private var panel: NSPanel?
    private var currentAppearance: NSAppearance?
    private var panelDelegate: PanelDelegate?
    private var targetApplication: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?
    private var localKeyMonitor: Any?
    private var deactivateCloseGraceDeadline: Date?
    private let appState: AppState
    private let panelVisibilityCoordinator = PanelVisibilityCoordinator()
    private let panelOpenTracker: PanelOpenTracker?

    /// Callback to create the panel content view.
    var contentViewProvider: (() -> NSView)?
    var onWillShow: (() -> Void)?
    var onDidStabilizeActivation: (() -> Void)?
    var onPanelContentSizeChanged: ((NSSize) -> Void)?
    var onPanelWindowOriginChanged: ((NSPoint) -> Void)?
    /// Key events seen while the panel is key, before AppKit's own dispatch.
    /// Return `true` to swallow the event.
    var onPanelKeyEvent: ((NSEvent) -> Bool)?

    init(appState: AppState, panelOpenTracker: PanelOpenTracker? = nil) {
        self.appState = appState
        self.panelOpenTracker = panelOpenTracker
        observeWorkspaceActivation()
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    /// Toggle panel visibility.
    func toggle() {
        switch panelVisibilityCoordinator.toggleAction() {
        case .show:
            show()
        case .hide:
            hide()
        }
    }

    /// Show the panel.
    func show() {
        guard panelVisibilityCoordinator.beginShow() else {
            PPLogger.panel.debug("Panel show ignored because state is already \(String(describing: self.panelVisibilityCoordinator.state))")
            return
        }

        if panel == nil {
            createPanel()
        }

        guard let panel = panel else {
            panelVisibilityCoordinator.finishHide()
            return
        }

        updateTargetApplicationIfNeeded(NSWorkspace.shared.frontmostApplication)

        onWillShow?()
        deactivateCloseGraceDeadline = Date().addingTimeInterval(
            TimeInterval(Constants.panelDeactivateCloseGraceMs) / 1000
        )

        positionPanelForPresentation(panel)

        appState.isPanelVisible = true
        panelVisibilityCoordinator.finishShow()
        panelOpenTracker?.markPanelShown()
        applyActivationPolicyForCurrentVisibility()
        activatePromptPanelApplication()
        bringPanelToFront(panel)
        stabilizePanelActivation(panel)
        PPLogger.panel.info("Panel shown")
    }

    /// Hide the panel.
    func hide() {
        guard panelVisibilityCoordinator.beginHide() else {
            return
        }

        panel?.orderOut(nil)
        appState.isPanelVisible = false
        deactivateCloseGraceDeadline = nil
        panelVisibilityCoordinator.finishHide()
        if panelOpenTracker?.currentTrace?.searchFieldFocusedAt == nil {
            panelOpenTracker?.cancelCurrentTrace(reason: "panel_hidden_before_focus")
        }
        reactivateTargetApplication()
        applyActivationPolicyForCurrentVisibility()
        PPLogger.panel.info("Panel hidden")
    }

    func targetApplicationBundleId() -> String? {
        targetApplication?.bundleIdentifier
    }

    func setPinned(_ isPinned: Bool) {
        appState.isPanelPinned = isPinned

        guard let panel else {
            return
        }

        applyPinnedWindowBehavior(to: panel)
        if isPinned, panel.isVisible {
            bringPanelToFront(panel)
        }
    }

    func setContentSize(_ contentSize: NSSize) {
        appState.panelContentSize = contentSize

        guard let panel else {
            return
        }

        let windowSize = Constants.panelWindowContentSize(for: contentSize)
        let currentFrame = panel.frame
        let newOrigin = NSPoint(
            x: currentFrame.midX - windowSize.width / 2,
            y: currentFrame.midY - windowSize.height / 2
        )
        panel.setFrame(
            NSRect(origin: newOrigin, size: windowSize),
            display: true,
            animate: false
        )
    }

    /// Override the panel's NSAppearance so its chrome tracks the user's
    /// theme choice. Passing `nil` falls back to the system appearance.
    func setAppearance(_ appearance: NSAppearance?) {
        currentAppearance = appearance
        panel?.appearance = appearance
    }

    /// Create the NSPanel with proper configuration.
    private func createPanel() {
        let windowSize = Constants.panelWindowContentSize(for: appState.panelContentSize)
        let panel = QuickPanelWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.resizable],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentMinSize = Constants.panelWindowContentSize(for: Constants.panelMinContentSize)
        panel.contentMaxSize = Constants.panelWindowContentSize(for: Constants.panelMaxContentSize)
        applyPinnedWindowBehavior(to: panel)

        configureWindowButtons(for: panel)

        // Set content view
        if let contentView = contentViewProvider?() {
            panel.contentView = makePanelBackgroundView(contentView: contentView)
        }

        // Handle Esc key and click-outside
        let delegate = PanelDelegate(
            onClose: { [weak self] in
                self?.hide()
            },
            onResize: { [weak self] contentSize in
                self?.handlePanelResize(contentSize: contentSize)
            },
            onMove: { [weak self] origin in
                self?.handlePanelMove(origin: origin)
            },
            shouldDeferCloseOnDeactivate: { [weak self] in
                self?.shouldDeferCloseOnDeactivate() ?? false
            },
            shouldCloseOnDeactivate: { [weak self] in
                self?.appState.isPanelPinned == false
            }
        )
        panel.delegate = delegate

        self.panel = panel
        self.panelDelegate = delegate
        panel.appearance = currentAppearance
        installLocalKeyMonitorIfNeeded()
        PPLogger.panel.info("Panel created")
    }

    // MARK: - Panel key events

    /// The panel has to intercept its ⌘-shortcuts before AppKit resolves key
    /// equivalents: while the search field is being edited the field editor is
    /// first responder, so a `keyDown:` override on the field never sees them,
    /// and the main menu claims ⌘C outright. A local monitor runs inside
    /// `NSApplication.sendEvent(_:)` ahead of both, which is the only place
    /// where ⌘1-9 and ⌘C can reliably be claimed.
    private func installLocalKeyMonitorIfNeeded() {
        guard localKeyMonitor == nil else {
            return
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // The monitor always fires on the main thread.
            let isClaimed = MainActor.assumeIsolated { self?.shouldSwallowPanelKeyDown(event) ?? false }
            return isClaimed ? nil : event
        }
    }

    private func shouldSwallowPanelKeyDown(_ event: NSEvent) -> Bool {
        guard let panel, panel.isVisible, panel.isKeyWindow else {
            return false
        }
        guard event.window === panel else {
            return false
        }
        guard let onPanelKeyEvent else {
            return false
        }
        return onPanelKeyEvent(event)
    }

    /// True when the focused editor holds a non-empty selection. ⌘C must keep
    /// its "copy the highlighted text" meaning in that case.
    static func hasActiveTextSelection(in window: NSWindow?) -> Bool {
        guard let textView = window?.firstResponder as? NSTextView else {
            return false
        }
        return textView.selectedRange().length > 0
    }

    private func configureWindowButtons(for panel: NSPanel) {
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
    }

    private func makePanelBackgroundView(contentView: NSView) -> NSVisualEffectView {
        let backgroundView = NSVisualEffectView()
        backgroundView.material = .underWindowBackground
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .followsWindowActiveState
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = 14
        backgroundView.layer?.masksToBounds = true

        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        backgroundView.addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: Constants.panelContentInsets.left),
            contentView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -Constants.panelContentInsets.right),
            contentView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: Constants.panelContentInsets.top),
            contentView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -Constants.panelContentInsets.bottom)
        ])

        return backgroundView
    }

    private func handlePanelResize(contentSize: NSSize) {
        let panelContentSize = NSSize(
            width: max(Constants.panelMinContentSize.width, contentSize.width - Constants.panelContentInsets.left - Constants.panelContentInsets.right),
            height: max(Constants.panelMinContentSize.height, contentSize.height - Constants.panelContentInsets.top - Constants.panelContentInsets.bottom)
        )
        let normalizedSize = NSSize(
            width: min(panelContentSize.width, Constants.panelMaxContentSize.width),
            height: min(panelContentSize.height, Constants.panelMaxContentSize.height)
        )
        guard appState.panelContentSize != normalizedSize else {
            return
        }
        appState.panelContentSize = normalizedSize
        onPanelContentSizeChanged?(normalizedSize)
    }

    private func handlePanelMove(origin: NSPoint) {
        guard appState.panelWindowOrigin != origin else {
            return
        }
        appState.panelWindowOrigin = origin
        onPanelWindowOriginChanged?(origin)
    }

    private func positionPanelForPresentation(_ panel: NSPanel) {
        let panelSize = panel.frame.size
        let screen = screenForPanelPlacement(panelSize: panelSize)
        let screenFrame = screen.visibleFrame
        let origin = resolvedPanelOrigin(panelSize: panelSize, screenFrame: screenFrame)
        guard panel.frame.origin != origin else {
            return
        }
        panel.setFrameOrigin(origin)
    }

    private func screenForPanelPlacement(panelSize: NSSize) -> NSScreen {
        if let storedOrigin = appState.panelWindowOrigin,
           let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(NSRect(origin: storedOrigin, size: panelSize)) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func resolvedPanelOrigin(panelSize: NSSize, screenFrame: NSRect) -> NSPoint {
        let candidate = appState.panelWindowOrigin ?? defaultPanelOrigin(panelSize: panelSize, screenFrame: screenFrame)
        return clampPanelOrigin(candidate, panelSize: panelSize, screenFrame: screenFrame)
    }

    private func defaultPanelOrigin(panelSize: NSSize, screenFrame: NSRect) -> NSPoint {
        NSPoint(
            x: screenFrame.midX - panelSize.width / 2 - screenFrame.width * 0.12,
            y: screenFrame.midY - panelSize.height / 2 - screenFrame.height * 0.08
        )
    }

    private func clampPanelOrigin(_ origin: NSPoint, panelSize: NSSize, screenFrame: NSRect) -> NSPoint {
        NSPoint(
            x: min(max(origin.x, screenFrame.minX), max(screenFrame.minX, screenFrame.maxX - panelSize.width)),
            y: min(max(origin.y, screenFrame.minY), max(screenFrame.minY, screenFrame.maxY - panelSize.height))
        )
    }

    private func applyPinnedWindowBehavior(to panel: NSPanel) {
        if appState.isPanelPinned {
            panel.level = .statusBar
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        } else {
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace, .fullScreenAuxiliary]
        }
    }

    private func reactivateTargetApplication() {
        guard let targetApplication else {
            return
        }
        let currentFrontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if currentFrontmostBundleId == Bundle.main.bundleIdentifier {
            _ = targetApplication.activate(options: [.activateAllWindows])
        } else {
            PPLogger.panel.info(
                "Skipped target app reactivation because frontmost app already changed to \(currentFrontmostBundleId ?? "unknown")"
            )
        }
        self.targetApplication = nil
    }

    private func observeWorkspaceActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.updateTargetApplicationIfNeeded(application)
            }
        }
    }

    private func updateTargetApplicationIfNeeded(_ application: NSRunningApplication?) {
        guard let application else {
            return
        }
        guard application.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        targetApplication = application
        PPLogger.panel.debug("Target application updated: \(application.bundleIdentifier ?? "unknown")")
    }

    private func stabilizePanelActivation(_ panel: NSPanel, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(attempt == 0 ? 0 : Constants.panelActivationRetryDelayMs)) { [weak self, weak panel] in
            guard let self, let panel else {
                return
            }
            guard self.panel === panel, self.appState.isPanelVisible else {
                return
            }

            let snapshot = PanelActivationSnapshot(
                appIsActive: NSApp.isActive,
                panelIsVisible: panel.isVisible,
                panelIsKey: panel.isKeyWindow
            )
            let action = Self.activationAction(
                snapshot: snapshot,
                attempt: attempt,
                maxAttempts: Constants.panelActivationMaxAttempts
            )

            switch action {
            case .stable:
                self.deactivateCloseGraceDeadline = nil
                self.panelOpenTracker?.recordPanelActivationCheck(attempt: attempt, snapshot: snapshot, final: true)
                self.onDidStabilizeActivation?()
            case .retry(let nextAttempt):
                self.panelOpenTracker?.recordPanelActivationCheck(attempt: attempt, snapshot: snapshot, final: false)
                self.activatePromptPanelApplication()
                self.bringPanelToFront(panel)
                self.stabilizePanelActivation(panel, attempt: nextAttempt)
            case .failed:
                self.deactivateCloseGraceDeadline = nil
                self.panelOpenTracker?.recordPanelActivationCheck(attempt: attempt, snapshot: snapshot, final: true)
                PPLogger.panel.error(
                    "panel_activation_failed attempt=\(attempt) app_active=\(snapshot.appIsActive) panel_visible=\(snapshot.panelIsVisible) panel_key=\(snapshot.panelIsKey)"
                )
            }
        }
    }

    private func activatePromptPanelApplication() {
        NSApp.activate(ignoringOtherApps: true)
        _ = NSRunningApplication.current.activate(options: [])
    }

    private func bringPanelToFront(_ panel: NSPanel) {
        panel.makeKeyAndOrderFront(nil)
        panel.makeMain()
        panel.orderFrontRegardless()
    }

    static func activationAction(
        snapshot: PanelActivationSnapshot,
        attempt: Int,
        maxAttempts: Int
    ) -> ActivationAction {
        if snapshot.isStable {
            return .stable
        }
        if attempt < maxAttempts {
            return .retry(nextAttempt: attempt + 1)
        }
        return .failed
    }

    static func desiredActivationPolicy(
        isPanelVisible: Bool,
        isMainWindowVisible: Bool
    ) -> NSApplication.ActivationPolicy {
        (isPanelVisible || isMainWindowVisible) ? .regular : .accessory
    }

    private func applyActivationPolicyForCurrentVisibility() {
        applyActivationPolicy(
            Self.desiredActivationPolicy(
                isPanelVisible: appState.isPanelVisible,
                isMainWindowVisible: appState.isMainWindowVisible
            )
        )
    }

    private func applyActivationPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else {
            return
        }

        guard NSApp.setActivationPolicy(policy) else {
            PPLogger.app.error("Failed to switch activation policy to \(String(describing: policy))")
            return
        }

        PPLogger.app.info("Switched activation policy to \(String(describing: policy))")
    }

    private func shouldDeferCloseOnDeactivate(now: Date = Date()) -> Bool {
        guard let deactivateCloseGraceDeadline else {
            return false
        }
        return now < deactivateCloseGraceDeadline
    }
}

// MARK: - Panel Delegate

private class PanelDelegate: NSObject, NSWindowDelegate {

    let onClose: () -> Void
    let onResize: (NSSize) -> Void
    let onMove: (NSPoint) -> Void
    let shouldDeferCloseOnDeactivate: () -> Bool
    let shouldCloseOnDeactivate: () -> Bool
    private let resignCloseDelayMs = 80

    init(
        onClose: @escaping () -> Void,
        onResize: @escaping (NSSize) -> Void,
        onMove: @escaping (NSPoint) -> Void,
        shouldDeferCloseOnDeactivate: @escaping () -> Bool,
        shouldCloseOnDeactivate: @escaping () -> Bool
    ) {
        self.onClose = onClose
        self.onResize = onResize
        self.onMove = onMove
        self.shouldDeferCloseOnDeactivate = shouldDeferCloseOnDeactivate
        self.shouldCloseOnDeactivate = shouldCloseOnDeactivate
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        let contentRect = window.contentRect(forFrameRect: window.frame)
        onResize(contentRect.size)
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        onMove(window.frame.origin)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        scheduleDeactivateCloseCheck(for: window)
    }

    private func scheduleDeactivateCloseCheck(for window: NSWindow) {
        // Delay the close check so transient focus churn during presentation does not
        // immediately dismiss the panel, while real click-outside transitions still do.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(resignCloseDelayMs)) { [weak self, weak window] in
            guard let self, let window else {
                return
            }
            guard window.isVisible else {
                return
            }
            guard window.isKeyWindow == false else {
                return
            }
            guard NSApp.isActive == false else {
                return
            }
            guard self.shouldCloseOnDeactivate() else {
                return
            }
            if self.shouldDeferCloseOnDeactivate() {
                self.scheduleDeactivateCloseCheck(for: window)
                return
            }
            self.onClose()
        }
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

final class QuickPanelWindow: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}
