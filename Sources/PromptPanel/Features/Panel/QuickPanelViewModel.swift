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

    /// Why a results refresh was requested — which decides whether incoming execution
    /// requests must wait for the new query to finish.
    ///
    /// When the query text or the project scope changes (`.scopeChanged`), `isScopeSearchInFlight`
    /// is raised until the background query lands: `Enter` and `⌘1-9` are deferred to the new
    /// results, and pointer clicks on stale rows are ignored so the panel never pastes an entry
    /// from the previous scope. Keep `testQuickPanelClearsResultsWhileAsyncSearchIsPending`
    /// (and the deferred-execution coverage in `PromptPanelTests`) aligned with this contract.
    ///
    /// `.dataChanged` is the other case: same query, same scope, the rows underneath
    /// just changed (a use count bumped after an execution, an edit made in the
    /// library). There the old rows are still the right answer, so refreshing in place
    /// without gating avoids unnecessary churn.
    private enum EntriesRefreshReason {
        case scopeChanged
        case dataChanged
    }

    private enum DeferredExecutionTarget: Equatable {
        case selected
        case index(Int)
    }

    private var isSuppressingQueryDidSet = false

    @Published var query: String = "" {
        didSet {
            guard !isSuppressingQueryDidSet, query != oldValue else { return }
            scheduleEntriesRefresh(delayMs: Constants.panelSearchDebounceMs, reason: .scopeChanged)
        }
    }
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var projects: [Project] = []
    @Published private(set) var projectNamesById: [String: String] = [:]
    @Published private(set) var isShowingGlobalFallback: Bool = false
    @Published var currentProjectId: String = ""
    @Published var selectedIndex: Int = 0
    @Published var focusToken: Int = 0
    @Published var statusMessage: String?
    @Published private(set) var statusTone: StatusTone = .info
    @Published private(set) var isLoadingEntries: Bool = false
    private(set) var isExecutionReady: Bool = false

    private let appState: AppState
    private let projectRepository: ProjectRepository
    private let entryRepository: EntryRepository?
    private let settingsRepository: SettingsRepository
    private let searchService: EntrySearchService
    private let executeService: ExecuteService
    private let clipboardService: ClipboardWriting
    private let permissionService: PermissionService
    private let panelOpenTracker: PanelOpenTracker?
    private let onSetPanelPinned: (Bool) -> Bool
    private let onOpenSettings: () -> Void
    private let onClosePanel: () -> Void
    private var cancellables = Set<AnyCancellable>()
    private let searchQueue = DispatchQueue(label: "PromptPanel.quick-panel.search", qos: .userInteractive)
    private var pendingSearchWorkItem: DispatchWorkItem?
    private var searchGeneration: Int = 0
    private(set) var isScopeSearchInFlight: Bool = false
    private var deferredExecutionRequest: (target: DeferredExecutionTarget, force: Bool, triggerSource: Constants.ExecutionTrigger)?

    init(
        appState: AppState,
        projectRepository: ProjectRepository,
        entryRepository: EntryRepository? = nil,
        settingsRepository: SettingsRepository,
        searchService: EntrySearchService,
        executeService: ExecuteService,
        clipboardService: ClipboardWriting = ClipboardService(),
        permissionService: PermissionService,
        panelOpenTracker: PanelOpenTracker? = nil,
        onSetPanelPinned: @escaping (Bool) -> Bool = { _ in false },
        onOpenSettings: @escaping () -> Void = {},
        onClosePanel: @escaping () -> Void
    ) {
        self.appState = appState
        self.projectRepository = projectRepository
        self.entryRepository = entryRepository
        self.settingsRepository = settingsRepository
        self.searchService = searchService
        self.executeService = executeService
        self.clipboardService = clipboardService
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

    /// Pre-loads projects and initial entries at launch so the first panel open
    /// renders immediately without waiting for a cold database fetch.
    func warmUp() {
        currentProjectId = appState.effectiveProjectId
        loadProjects()
        scheduleEntriesRefresh(delayMs: 0, reason: .dataChanged)
    }

    func prepareForPresentation() {
        permissionService.refresh()
        applyBaseStatus()
        if !query.isEmpty {
            isSuppressingQueryDidSet = true
            query = ""
            isSuppressingQueryDidSet = false
        }
        selectedIndex = 0
        currentProjectId = appState.effectiveProjectId
        isExecutionReady = false
        deferredExecutionRequest = nil
        focusToken += 1
        loadProjects()
        scheduleEntriesRefresh(delayMs: 0, reason: .scopeChanged)
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
        deferredExecutionRequest = nil
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
        PPLogger.panel.debug(
            "execute_selection_requested trigger=\(triggerSource.rawValue) ready=\(self.isExecutionReady) force=\(force) selected_index=\(self.selectedIndex) entry_count=\(self.entries.count)"
        )
        guard force || isExecutionReady else {
            PPLogger.panel.warning(
                "execute_selection_blocked trigger=\(triggerSource.rawValue) reason=panel_not_ready focus_token=\(self.focusToken)"
            )
            return
        }
        if isScopeSearchInFlight {
            if triggerSource == .keyboardSubmit {
                PPLogger.panel.debug(
                    "execute_selection_deferred trigger=\(triggerSource.rawValue) target=selected generation=\(self.searchGeneration)"
                )
                deferredExecutionRequest = (target: .selected, force: force, triggerSource: triggerSource)
            } else {
                PPLogger.panel.warning(
                    "execute_selection_blocked trigger=\(triggerSource.rawValue) reason=scope_search_in_flight generation=\(self.searchGeneration)"
                )
            }
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
            scheduleEntriesRefresh(delayMs: 0, reason: .scopeChanged)
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
                self?.scheduleEntriesRefresh(delayMs: 0, reason: .scopeChanged)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .entriesDidChange)
            .sink { [weak self] _ in
                self?.scheduleEntriesRefresh(delayMs: 0, reason: .dataChanged)
            }
            .store(in: &cancellables)
    }

    private func loadProjects() {
        do {
            projects = try projectRepository.fetchAll(includeArchived: false)
            projectNamesById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
            if currentProjectId.isEmpty || !projects.contains(where: { $0.id == currentProjectId }) {
                currentProjectId = appState.effectiveProjectId
            }
        } catch {
            PPLogger.project.error("Failed to load projects for panel: \(error.localizedDescription)")
            projects = []
            projectNamesById = [:]
            setStatus("加载项目失败，请重试。", tone: .error)
        }
    }

    func projectName(for projectId: String) -> String? {
        projectNamesById[projectId]
    }

    /// Creates a new entry from the current search query (or clipboard if the query is empty)
    /// directly inside the quick panel, or opens the main window's entry editor when `entryRepository` is unavailable.
    func quickCreateEntryFromPanel(type: Constants.EntryType = .prompt) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let (cleanedQuery, inlineTag) = Self.extractTagFilter(from: trimmedQuery)
        let effectiveQueryContent = cleanedQuery.isEmpty ? trimmedQuery : cleanedQuery
        let clipboardText = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawContent = !effectiveQueryContent.isEmpty ? effectiveQueryContent : clipboardText
        guard !rawContent.isEmpty, let entryRepository else {
            onOpenSettings()
            return
        }

        let targetProjectId: String = {
            if type == .todo || type == .note,
               let inbox = projects.first(where: { $0.groupKind == .inbox }) {
                return inbox.id
            }
            return currentProjectId.isEmpty ? appState.effectiveProjectId : currentProjectId
        }()
        guard !targetProjectId.isEmpty else {
            onOpenSettings()
            return
        }

        let firstLine = rawContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "快捷新建"
        let title = String(firstLine.prefix(36))
        let tags: [String] = {
            guard let inlineTag, !inlineTag.isEmpty else { return [] }
            return Entry.normalizeTags([inlineTag])
        }()

        let newEntry = Entry(
            projectId: targetProjectId,
            title: title,
            content: rawContent,
            type: type.rawValue,
            tags: tags
        )

        do {
            try entryRepository.create(newEntry, changeNote: "快捷面板新建")
            isSuppressingQueryDidSet = true
            query = ""
            isSuppressingQueryDidSet = false
            if targetProjectId != currentProjectId && targetProjectId != appState.defaultProjectId {
                activateProject(targetProjectId)
            } else {
                scheduleEntriesRefresh(delayMs: 0, reason: .dataChanged)
            }
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            setStatus("已新建词条：\(title)", tone: .info)
        } catch {
            PPLogger.entry.error("Failed to quick-create entry from panel: \(error.localizedDescription)")
            setStatus("新建词条失败，请重试。", tone: .error)
        }
    }

    func toggleEntryCompleted(_ entry: Entry) {
        guard let entryRepository else { return }
        let nextState = !entry.isCompleted
        do {
            try entryRepository.setCompleted(id: entry.id, isCompleted: nextState)
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            scheduleEntriesRefresh(delayMs: 0, reason: .dataChanged)
        } catch {
            PPLogger.entry.error("Failed to toggle entry completed in panel: \(error.localizedDescription)")
            setStatus("更新完成状态失败，请重试。", tone: .error)
        }
    }

    func toggleEntryPinned(_ entry: Entry) {
        guard let entryRepository else { return }
        var updated = entry
        updated.isPinned.toggle()
        updated.updatedAt = Date()
        do {
            try entryRepository.update(updated)
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            scheduleEntriesRefresh(delayMs: 0, reason: .dataChanged)
        } catch {
            PPLogger.entry.error("Failed to toggle entry pin in panel: \(error.localizedDescription)")
            setStatus("更新置顶状态失败，请重试。", tone: .error)
        }
    }

    private func scheduleEntriesRefresh(delayMs: Int, reason: EntriesRefreshReason) {
        pendingSearchWorkItem?.cancel()
        pendingSearchWorkItem = nil

        guard !appState.effectiveProjectId.isEmpty || !currentProjectId.isEmpty else {
            entries = []
            selectedIndex = 0
            isLoadingEntries = false
            isScopeSearchInFlight = false
            deferredExecutionRequest = nil
            return
        }

        let effectiveCurrentProjectId = currentProjectId.isEmpty ? appState.effectiveProjectId : currentProjectId
        let defaultProjectId = appState.defaultProjectId
        let (cleanedQuery, tagFilter) = Self.extractTagFilter(from: self.query)
        let query = cleanedQuery
        let searchService = self.searchService
        let searchQueue = self.searchQueue

        appState.currentProjectId = effectiveCurrentProjectId
        if reason == .scopeChanged {
            isScopeSearchInFlight = true
            deferredExecutionRequest = nil
            selectedIndex = 0
        }
        // Keep existing entries visible while the background query runs so the
        // ScrollView/LazyVStack is never torn down and recreated on keystrokes.
        isLoadingEntries = entries.isEmpty
        searchGeneration += 1
        let generation = searchGeneration

        let runSearch: @Sendable () -> Void = { [weak self] in
            searchQueue.async {
                let result: Result<(entries: [Entry], isGlobalFallback: Bool), Error>
                do {
                    let searchOutcome = try searchService.searchWithScopeFallback(
                        query: query,
                        currentProjectId: effectiveCurrentProjectId,
                        defaultProjectId: defaultProjectId,
                        tag: tagFilter
                    )
                    let sortedEntries = Self.applyPanelRankingSort(
                        searchOutcome.entries,
                        currentProjectId: effectiveCurrentProjectId
                    )
                    result = .success((sortedEntries, searchOutcome.isGlobalFallback))
                } catch {
                    result = .failure(error)
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.searchGeneration == generation else {
                        return
                    }

                    self.isScopeSearchInFlight = false
                    let pendingExecution = self.deferredExecutionRequest
                    self.deferredExecutionRequest = nil

                    switch result {
                    case .success(let (entries, isGlobalFallback)):
                        self.isLoadingEntries = false
                        self.isShowingGlobalFallback = isGlobalFallback
                        let previousSelectionId = self.selectedEntry?.id
                        self.entries = entries
                        if entries.isEmpty || reason == .scopeChanged {
                            self.selectedIndex = 0
                        } else if let previousSelectionId,
                                  let index = entries.firstIndex(where: { $0.id == previousSelectionId }) {
                            self.selectedIndex = index
                        } else {
                            self.selectedIndex = min(self.selectedIndex, entries.count - 1)
                        }
                        self.applyBaseStatus()
                        if let pendingExecution, !entries.isEmpty {
                            switch pendingExecution.target {
                            case .selected:
                                self.executeSelection(
                                    force: pendingExecution.force,
                                    triggerSource: pendingExecution.triggerSource
                                )
                            case .index(let targetIndex):
                                guard entries.indices.contains(targetIndex) else {
                                    break
                                }
                                self.selectedIndex = targetIndex
                                self.executeSelection(
                                    force: pendingExecution.force,
                                    triggerSource: pendingExecution.triggerSource
                                )
                            }
                        }
                    case .failure(let error):
                        PPLogger.search.error("Panel search failed: \(error.localizedDescription)")
                        self.isLoadingEntries = false
                        self.isShowingGlobalFallback = false
                        self.entries = []
                        self.selectedIndex = 0
                        self.setStatus("搜索失败，请稍后重试。", tone: .error)
                    }
                }
            }
        }

        if delayMs <= 0 {
            runSearch()
        } else {
            let workItem = DispatchWorkItem(block: runSearch)
            pendingSearchWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: workItem)
        }
    }

    private func scheduleExecutionUnlock(for token: Int) {
        if Constants.panelExecutionUnlockDelayMs <= 0 {
            guard focusToken == token else { return }
            isExecutionReady = true
            PPLogger.panel.debug("execute_selection_unlocked focus_token=\(token) delay_ms=0")
            return
        }

        isExecutionReady = false
        let delay = Double(Constants.panelExecutionUnlockDelayMs) / 1000
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.focusToken == token else {
                return
            }
            self.isExecutionReady = true
            PPLogger.panel.debug("execute_selection_unlocked focus_token=\(token) delay_ms=\(Constants.panelExecutionUnlockDelayMs)")
        }
    }

    private func applyBaseStatus() {
        guard permissionService.isAccessibilityGranted == false else {
            statusMessage = nil
            statusTone = .info
            return
        }

        statusMessage = "未授权辅助功能，当前仅复制到剪贴板"
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
        case quickCreateEntry
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
        case "n":
            return .quickCreateEntry
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
            guard (1...9).contains(number) else {
                return false
            }
            if isScopeSearchInFlight {
                executeEntry(atNumber: number)
                return true
            }
            guard entries.indices.contains(number - 1) else {
                return false
            }
            executeEntry(atNumber: number)
        case .copySelection:
            guard !isScopeSearchInFlight, selectedEntry != nil else {
                return false
            }
            copySelectionOnly()
        case .togglePin:
            togglePanelPinned()
        case .quickCreateEntry:
            quickCreateEntryFromPanel()
        case .closePanel:
            closePanel()
        }
        return true
    }

    /// Execute the Nth visible entry (1-indexed). Used by ⌘1-9.
    func executeEntry(atNumber number: Int, triggerSource: Constants.ExecutionTrigger = .keyboardSubmit) {
        let index = number - 1
        guard index >= 0 else { return }
        if isScopeSearchInFlight, triggerSource == .keyboardSubmit {
            PPLogger.panel.debug(
                "execute_selection_deferred trigger=\(triggerSource.rawValue) target=index(\(index)) generation=\(self.searchGeneration)"
            )
            deferredExecutionRequest = (target: .index(index), force: true, triggerSource: triggerSource)
            return
        }
        executeEntry(at: index, triggerSource: triggerSource)
    }

    /// Execute a visible entry by zero-based index. Used by pointer clicks and direct shortcuts.
    func executeEntry(at index: Int, triggerSource: Constants.ExecutionTrigger = .pointerClick) {
        guard !isScopeSearchInFlight else {
            PPLogger.panel.warning(
                "execute_entry_blocked index=\(index) trigger=\(triggerSource.rawValue) reason=scope_search_in_flight"
            )
            return
        }
        guard entries.indices.contains(index) else {
            return
        }
        selectedIndex = index
        executeSelection(force: true, triggerSource: triggerSource)
    }

    /// Copy a visible entry by zero-based index without attempting paste.
    func copyEntry(at index: Int) {
        guard !isScopeSearchInFlight, entries.indices.contains(index) else {
            return
        }
        selectedIndex = index
        copySelectionOnly()
    }

    /// Copy the selected entry to clipboard without attempting paste. Used by ⌘C.
    func copySelectionOnly() {
        guard !isScopeSearchInFlight, let entry = selectedEntry else { return }
        let success = clipboardService.writeText(entry.content)
        if success {
            if let entryRepository {
                do {
                    try entryRepository.recordExecution(id: entry.id)
                    NotificationCenter.default.post(name: .entriesDidChange, object: nil)
                } catch {
                    PPLogger.execute.error("Failed to record usage on copy: \(error.localizedDescription)")
                }
            }
            setStatus("已复制到剪贴板：\(entry.title)", tone: .info)
            executeService.onShowNotification?("已复制：\(entry.title)", true)
            onClosePanel()
        } else {
            setStatus("复制到剪贴板失败，请重试。", tone: .error)
            executeService.onShowNotification?("复制到剪贴板失败，请重试。", false)
        }
    }
}
