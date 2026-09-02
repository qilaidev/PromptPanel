import AppKit
import Combine
import Foundation

@MainActor
final class QuickPanelViewModel: ObservableObject {
    enum SelectionDirection {
        case up
        case down
    }

    enum StatusTone {
        case info
        case warning
        case error
    }

    @Published var query: String = "" {
        didSet {
            scheduleEntriesRefresh(delayMs: Constants.panelSearchDebounceMs)
        }
    }
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var projects: [Project] = []
    @Published var currentProjectId: String = ""
    @Published var selectedIndex: Int = 0
    @Published var focusToken: Int = 0
    @Published var statusMessage: String?
    @Published private(set) var statusTone: StatusTone = .info
    @Published private(set) var isLoadingEntries: Bool = false
    private(set) var isExecutionReady: Bool = false

    private let appState: AppState
    private let projectRepository: ProjectRepository
    private let settingsRepository: SettingsRepository
    private let searchService: EntrySearchService
    private let executeService: ExecuteService
    private let permissionService: PermissionService
    private let panelOpenTracker: PanelOpenTracker?
    private let onSetPanelPinned: (Bool) -> Bool
    private let onOpenSettings: () -> Void
    private let onClosePanel: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private let searchQueue = DispatchQueue(label: "PromptPanel.quick-panel.search", qos: .userInitiated)
    private var pendingSearchWorkItem: DispatchWorkItem?
    private var searchGeneration: Int = 0

    init(
        appState: AppState,
        projectRepository: ProjectRepository,
        settingsRepository: SettingsRepository,
        searchService: EntrySearchService,
        executeService: ExecuteService,
        permissionService: PermissionService,
        panelOpenTracker: PanelOpenTracker? = nil,
        onSetPanelPinned: @escaping (Bool) -> Bool = { _ in false },
        onOpenSettings: @escaping () -> Void = {},
        onClosePanel: @escaping () -> Void
    ) {
        self.appState = appState
        self.projectRepository = projectRepository
        self.settingsRepository = settingsRepository
        self.searchService = searchService
        self.executeService = executeService
        self.permissionService = permissionService
        self.panelOpenTracker = panelOpenTracker
        self.onSetPanelPinned = onSetPanelPinned
        self.onOpenSettings = onOpenSettings
        self.onClosePanel = onClosePanel
        self.currentProjectId = appState.effectiveProjectId

        observeChanges()
    }

    deinit {
        pendingSearchWorkItem?.cancel()
    }

    var selectedEntry: Entry? {
        guard entries.indices.contains(selectedIndex) else {
            return entries.first
        }
        return entries[selectedIndex]
    }

    func prepareForPresentation() {
        permissionService.refresh()
        applyBaseStatus()
        query = ""
        selectedIndex = 0
        currentProjectId = appState.effectiveProjectId
        isExecutionReady = false
        focusToken += 1
        loadProjects()
        scheduleEntriesRefresh(delayMs: 0)
    }

    func handleSearchFieldFocus(_ result: PanelFocusResult) {
        guard result.token == focusToken else {
            return
        }
        panelOpenTracker?.markSearchFieldFocused(result)
        guard result.succeeded else {
            isExecutionReady = false
            return
        }
        scheduleExecutionUnlock(for: result.token)
    }

    func retryFocusAfterActivationStabilized() {
        isExecutionReady = false
        focusToken += 1
    }

    func closePanel() {
        onClosePanel()
    }

    func setPanelPinned(_ isPinned: Bool) {
        guard onSetPanelPinned(isPinned) else {
            setStatus("固定状态保存失败，请重试。", tone: .error)
            return
        }
        applyBaseStatus()
    }

    func togglePanelPinned() {
        setPanelPinned(!appState.isPanelPinned)
    }

    func openAccessibilitySettings() {
        permissionService.openAccessibilitySettings()
    }

    func openSettings() {
        onOpenSettings()
    }

    func moveSelection(_ direction: SelectionDirection) {
        guard !entries.isEmpty else {
            return
        }

        switch direction {
        case .up:
            selectedIndex = max(0, selectedIndex - 1)
        case .down:
            selectedIndex = min(entries.count - 1, selectedIndex + 1)
        }
    }

    func selectEntry(at index: Int) {
        guard entries.indices.contains(index) else {
            return
        }
        selectedIndex = index
    }

    func executeSelection(
        force: Bool = false,
        triggerSource: Constants.ExecutionTrigger = .keyboardSubmit
    ) {
        PPLogger.panel.info(
            "execute_selection_requested trigger=\(triggerSource.rawValue) ready=\(self.isExecutionReady) force=\(force) selected_index=\(self.selectedIndex) entry_count=\(self.entries.count)"
        )
        guard force || isExecutionReady else {
            PPLogger.panel.warning(
                "execute_selection_blocked trigger=\(triggerSource.rawValue) reason=panel_not_ready focus_token=\(self.focusToken)"
            )
            return
        }
        guard let entry = selectedEntry else {
            PPLogger.panel.warning(
                "execute_selection_blocked trigger=\(triggerSource.rawValue) reason=no_selection selected_index=\(self.selectedIndex) entry_count=\(self.entries.count)"
            )
            return
        }

        executeService.execute(
            entry: entry,
            currentProjectId: currentProjectId,
            triggerSource: triggerSource
        )
    }

    func activateProject(_ id: String) {
        guard !id.isEmpty, currentProjectId != id else {
            return
        }

        do {
            try settingsRepository.setCurrentProjectId(id)
            appState.currentProjectId = id
            currentProjectId = id
            NotificationCenter.default.post(name: .currentProjectDidChange, object: nil)
            scheduleEntriesRefresh(delayMs: 0)
        } catch {
            PPLogger.project.error("Failed to switch current project: \(error.localizedDescription)")
            setStatus("切换项目失败，请重试。", tone: .error)
        }
    }

    private func observeChanges() {
        NotificationCenter.default.publisher(for: .projectsDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .currentProjectDidChange))
            .sink { [weak self] _ in
                self?.loadProjects()
                self?.scheduleEntriesRefresh(delayMs: 0)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .entriesDidChange)
            .sink { [weak self] _ in
                self?.scheduleEntriesRefresh(delayMs: 0)
            }
            .store(in: &cancellables)
    }

    private func loadProjects() {
        do {
            projects = try projectRepository.fetchAll()
            if currentProjectId.isEmpty || !projects.contains(where: { $0.id == currentProjectId }) {
                currentProjectId = appState.effectiveProjectId
            }
        } catch {
            PPLogger.project.error("Failed to load projects for panel: \(error.localizedDescription)")
            projects = []
            setStatus("加载项目失败，请重试。", tone: .error)
        }
    }

    private func scheduleEntriesRefresh(delayMs: Int) {
        pendingSearchWorkItem?.cancel()
        entries = []
        selectedIndex = 0

        guard !appState.effectiveProjectId.isEmpty || !currentProjectId.isEmpty else {
            isLoadingEntries = false
            return
        }

        let effectiveCurrentProjectId = currentProjectId.isEmpty ? appState.effectiveProjectId : currentProjectId
        let defaultProjectId = appState.defaultProjectId
        let (cleanedQuery, tagFilter) = Self.extractTagFilter(from: self.query)
        let query = cleanedQuery
        let searchService = self.searchService
        let searchQueue = self.searchQueue

        appState.currentProjectId = effectiveCurrentProjectId
        isLoadingEntries = true
        searchGeneration += 1
        let generation = searchGeneration

        let workItem = DispatchWorkItem { [weak self] in
            guard self != nil else {
                return
            }

            searchQueue.async {
                let result: Result<[Entry], Error>
                do {
                    var entries = try searchService.search(
                        query: query,
                        currentProjectId: effectiveCurrentProjectId,
                        defaultProjectId: defaultProjectId
                    )
                    if let tagFilter {
                        entries = entries.filter { $0.tags.contains(tagFilter) }
                    }
                    entries = Self.applyPanelRankingSort(entries, currentProjectId: effectiveCurrentProjectId)
                    result = .success(entries)
                } catch {
                    result = .failure(error)
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.searchGeneration == generation else {
                        return
                    }

                    switch result {
                    case .success(let entries):
                        self.isLoadingEntries = false
                        self.entries = entries
                        if entries.isEmpty {
                            self.selectedIndex = 0
                        } else {
                            self.selectedIndex = min(self.selectedIndex, entries.count - 1)
                        }
                        self.applyBaseStatus()
                    case .failure(let error):
                        PPLogger.search.error("Panel search failed: \(error.localizedDescription)")
                        self.isLoadingEntries = false
                        self.entries = []
                        self.selectedIndex = 0
                        self.setStatus("搜索失败，请稍后重试。", tone: .error)
                    }
                }
            }
        }

        pendingSearchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(delayMs, 0)), execute: workItem)
    }

    private func scheduleExecutionUnlock(for token: Int) {
        isExecutionReady = false
        let delay = Double(Constants.panelExecutionUnlockDelayMs) / 1000
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else {
                return
            }
            guard self.focusToken == token else {
                return
            }
            self.isExecutionReady = true
            PPLogger.panel.info("execute_selection_unlocked focus_token=\(token) delay_ms=\(Constants.panelExecutionUnlockDelayMs)")
        }
    }

    private func applyBaseStatus() {
        guard permissionService.isAccessibilityGranted == false else {
            statusMessage = nil
            statusTone = .info
            return
        }

        statusMessage = "当前为仅复制模式，请在系统设置中开启 PromptPanel.app 的辅助功能权限。"
        statusTone = .warning
    }

    private func setStatus(_ message: String, tone: StatusTone) {
        statusMessage = message
        statusTone = tone
    }

    /// Order panel results by the same stable keys as the repository so shortcut
    /// numbers do not drift between browsing, searching, and project switching.
    /// `EntryRanking` owns the keys; this only supplies the panel's context.
    nonisolated static func applyPanelRankingSort(
        _ entries: [Entry],
        currentProjectId: String,
        now: Date = Date()
    ) -> [Entry] {
        entries.sorted { lhs, rhs in
            EntryRanking.isOrderedBefore(lhs, rhs, currentProjectId: currentProjectId, now: now)
        }
    }

    /// Extracts the first `#tag` token from the query, returning the remaining
    /// query text and the extracted tag (without the `#`). Used by the panel to
    /// mirror the design's `#tag` search syntax.
    static func extractTagFilter(from query: String) -> (cleanedQuery: String, tag: String?) {
        var extractedTag: String?
        var parts: [String] = []
        for token in query.split(whereSeparator: \.isWhitespace) {
            if extractedTag == nil, token.hasPrefix("#"), token.count > 1 {
                extractedTag = String(token.dropFirst())
                continue
            }
            parts.append(String(token))
        }
        return (parts.joined(separator: " "), extractedTag)
    }

    // MARK: - Panel shortcuts

    /// A ⌘-combination the quick panel owns.
    ///
    /// These cannot be expressed as SwiftUI `keyboardShortcut`s or as a
    /// `keyDown` handler on the search field: while the field is being edited
    /// the field editor is first responder, and AppKit resolves ⌘-combinations
    /// through key-equivalent dispatch (main menu included) before any
    /// `keyDown:` runs. `PanelService` therefore feeds raw key events here from
    /// a local event monitor, which fires ahead of all of that.
    enum PanelKeyCommand: Equatable {
        case executeEntry(number: Int)
        case copySelection
        case togglePin
        case closePanel
    }

    private static let escapeKeyCode: UInt16 = 53

    /// Pure mapping from a key event to a panel command. Only a bare ⌘ counts —
    /// ⌘⇧1 / ⌥⌘1 stay available to the system.
    static func panelKeyCommand(
        keyCode: UInt16 = .max,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?
    ) -> PanelKeyCommand? {
        // Esc is handled here rather than only on the search field: once focus
        // moves off the field (a background click, a closed menu) the field's
        // key handling stops running and the panel would have no way out.
        if keyCode == escapeKeyCode, modifierFlags.isDisjoint(with: [.command, .shift, .option, .control]) {
            return .closePanel
        }
        guard modifierFlags.contains(.command) else {
            return nil
        }
        guard modifierFlags.isDisjoint(with: [.shift, .option, .control]) else {
            return nil
        }
        guard let characters = charactersIgnoringModifiers?.lowercased(), characters.count == 1 else {
            return nil
        }
        if let digit = Int(characters), (1...9).contains(digit) {
            return .executeEntry(number: digit)
        }
        switch characters {
        case "c":
            return .copySelection
        case "p":
            return .togglePin
        default:
            return nil
        }
    }

    /// Run a panel command. Returns `false` when the command does not apply
    /// right now (for example ⌘4 with only three results), so the caller can
    /// let AppKit handle the event normally instead of swallowing it.
    @discardableResult
    func handlePanelKeyCommand(_ command: PanelKeyCommand) -> Bool {
        switch command {
        case .executeEntry(let number):
            guard entries.indices.contains(number - 1) else {
                return false
            }
            executeEntry(atNumber: number)
        case .copySelection:
            guard selectedEntry != nil else {
                return false
            }
            copySelectionOnly()
        case .togglePin:
            togglePanelPinned()
        case .closePanel:
            closePanel()
        }
        return true
    }

    /// Execute the Nth visible entry (1-indexed). Used by ⌘1-9.
    func executeEntry(atNumber number: Int, triggerSource: Constants.ExecutionTrigger = .keyboardSubmit) {
        let index = number - 1
        executeEntry(at: index, triggerSource: triggerSource)
    }

    /// Execute a visible entry by zero-based index. Used by pointer clicks and direct shortcuts.
    func executeEntry(at index: Int, triggerSource: Constants.ExecutionTrigger = .pointerClick) {
        guard entries.indices.contains(index) else {
            return
        }
        selectedIndex = index
        executeSelection(force: true, triggerSource: triggerSource)
    }

    /// Copy the selected entry to clipboard without attempting paste. Used by ⌘C.
    func copySelectionOnly() {
        guard let entry = selectedEntry else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(entry.content, forType: .string)
        if success {
            setStatus("已复制到剪贴板：\(entry.title)", tone: .info)
            onClosePanel()
        } else {
            setStatus("复制到剪贴板失败，请重试。", tone: .error)
        }
    }
}
