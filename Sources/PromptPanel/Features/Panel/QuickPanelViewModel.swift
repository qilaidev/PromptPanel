import AppKit
import Combine
import Foundation

@MainActor
final class QuickPanelViewModel: ObservableObject {
    nonisolated static let allProjectsScopeId = EntrySearchService.allProjectsScopeId
    nonisolated static let allProjectsScopeName = "全部内容"
    nonisolated private static let transientStatusDuration: TimeInterval = 2.8

    enum SelectionDirection {
        case up
        case down
    }

    enum StatusTone {
        case info
        case warning
        case error
    }

    enum KindFilter: String, CaseIterable, Equatable, Identifiable {
        case all
        case noteAndTodo
        case note
        case todo
        case prompt
        case code
        case reply

        static let barItems: [KindFilter] = [.all, .noteAndTodo, .prompt, .code, .reply]

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .all: return "全部"
            case .noteAndTodo: return "便签·待办"
            case .note: return "便签"
            case .todo: return "待办"
            case .prompt: return "提示词"
            case .code: return "代码"
            case .reply: return "回复"
            }
        }

        var symbolName: String? {
            switch self {
            case .all: return nil
            case .noteAndTodo, .note: return "note.text"
            case .todo: return "checklist"
            case .prompt: return "text.bubble"
            case .code: return "chevron.left.forwardslash.chevron.right"
            case .reply: return "arrowshape.turn.up.left"
            }
        }

        func matches(_ entry: Entry) -> Bool {
            let resolved = Constants.EntryType.resolve(entry.type)
            switch self {
            case .all:
                return true
            case .noteAndTodo:
                return resolved == .note || resolved == .todo
            case .note:
                return resolved == .note
            case .todo:
                return resolved == .todo
            case .prompt:
                return resolved == .prompt
            case .code:
                return resolved == .code
            case .reply:
                return resolved == .reply
            }
        }
    }

    struct QuickCaptureDraft: Equatable {
        let type: Constants.EntryType
        let matchedPrefix: String
        let rawBody: String
        let title: String
        let cleanedContent: String
        let tags: [String]

        var hasContent: Bool {
            !cleanedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var modeBadgeText: String {
            type == .todo ? "☑️ 待办速记 · 回车即存" : "📝 便签速记 · 回车即存"
        }
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
    private var isSuppressingFilterDidSet = false

    @Published var query: String = "" {
        didSet {
            guard !isSuppressingQueryDidSet, query != oldValue else { return }
            if !query.isEmpty, transientStatus != nil {
                clearTransientStatus(reapplyBase: true)
            }
            if isPreviewPresented {
                isPreviewPresented = false
            }
            if isScopeDropdownOpen {
                isScopeDropdownOpen = false
            }
            scheduleEntriesRefresh(delayMs: Constants.panelSearchDebounceMs, reason: .scopeChanged)
        }
    }
    @Published var activeKindFilter: KindFilter = .all {
        didSet {
            guard !isSuppressingFilterDidSet, activeKindFilter != oldValue else { return }
            let filtered = Self.filterEntries(unfilteredEntries, by: activeKindFilter)
            if entries != filtered {
                entries = filtered
            }
            if selectedIndex != 0 {
                selectedIndex = 0
            }
            scrollSelectionRevision += 1
            if entries.isEmpty, isPreviewPresented {
                isPreviewPresented = false
            }
        }
    }
    @Published private(set) var unfilteredEntries: [Entry] = []
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var projects: [Project] = []
    @Published private(set) var projectNamesById: [String: String] = [:]
    @Published private(set) var isShowingGlobalFallback: Bool = false
    @Published var currentProjectId: String = ""
    @Published var selectedIndex: Int = 0
    @Published private(set) var scrollSelectionRevision: Int = 0
    @Published var focusToken: Int = 0
    @Published var statusMessage: String?
    @Published private(set) var statusTone: StatusTone = .info
    @Published private(set) var isLoadingEntries: Bool = false
    @Published var isPreviewPresented: Bool = false
    @Published var isScopeDropdownOpen: Bool = false
    @Published private(set) var hasClipboardText: Bool = false
    private(set) var isExecutionReady: Bool = false
    var clipboardTextProvider: () -> String? = {
        NSPasteboard.general.string(forType: .string)
    }

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
    private var transientStatusResetWorkItem: DispatchWorkItem?
    private var transientStatus: (message: String, tone: StatusTone, expiresAt: Date)?
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
        transientStatusResetWorkItem?.cancel()
    }

    var selectedEntry: Entry? {
        guard entries.indices.contains(selectedIndex) else {
            return entries.first
        }
        return entries[selectedIndex]
    }

    var quickCaptureDraft: QuickCaptureDraft? {
        Self.parseQuickCapture(from: query)
    }

    var isQuickCaptureMode: Bool {
        quickCaptureDraft != nil
    }

    var isAllProjectsScope: Bool {
        currentProjectId == Self.allProjectsScopeId
    }

    var availableScopeIds: [String] {
        if projects.isEmpty {
            loadProjects(preserveAllProjectsScope: true)
        }
        let inboxIds = projects.filter { $0.groupKind == .inbox }.map(\.id)
        let categoryIds = projects.filter { $0.groupKind == .category }.map(\.id)
        let projectIds = projects.filter { $0.groupKind == .project }.map(\.id)
        return [Self.allProjectsScopeId] + inboxIds + categoryIds + projectIds
    }

    var defaultQuickCreateType: Constants.EntryType {
        if let draft = quickCaptureDraft {
            return draft.type
        }
        if currentProjectId == Constants.inboxProjectId
            || projects.first(where: { $0.id == currentProjectId })?.groupKind == .inbox {
            return .note
        }
        switch activeKindFilter {
        case .noteAndTodo, .note, .todo:
            return .note
        case .code:
            return .code
        case .reply:
            return .reply
        case .all, .prompt:
            return .prompt
        }
    }

    /// Pre-loads projects and initial entries at launch so the first panel open
    /// renders immediately without waiting for a cold database fetch.
    func warmUp() {
        currentProjectId = appState.effectiveProjectId
        refreshClipboardState()
        loadProjects(preserveAllProjectsScope: false)
        scheduleEntriesRefresh(delayMs: 0, reason: .dataChanged)
    }

    func prepareForPresentation() {
        permissionService.refresh()
        clearTransientStatus(reapplyBase: false)
        applyBaseStatus()
        if !query.isEmpty {
            isSuppressingQueryDidSet = true
            query = ""
            isSuppressingQueryDidSet = false
        }
        if activeKindFilter != .all {
            isSuppressingFilterDidSet = true
            activeKindFilter = .all
            isSuppressingFilterDidSet = false
        }
        if isPreviewPresented {
            isPreviewPresented = false
        }
        if isScopeDropdownOpen {
            isScopeDropdownOpen = false
        }
        if selectedIndex != 0 {
            selectedIndex = 0
        }
        scrollSelectionRevision += 1
        if currentProjectId != appState.effectiveProjectId {
            currentProjectId = appState.effectiveProjectId
        }
        isExecutionReady = false
        deferredExecutionRequest = nil
        focusToken += 1
        refreshClipboardState()
        loadProjects(preserveAllProjectsScope: false)
        scheduleEntriesRefresh(delayMs: 0, reason: .scopeChanged)
    }

    func refreshClipboardState() {
        let trimmed = clipboardTextProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        hasClipboardText = !trimmed.isEmpty
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

    func handleEscape() {
        if isPreviewPresented {
            isPreviewPresented = false
            return
        }
        if isScopeDropdownOpen {
            isScopeDropdownOpen = false
            return
        }
        closePanel()
    }

    func closePanel() {
        if isPreviewPresented {
            isPreviewPresented = false
        }
        if isScopeDropdownOpen {
            isScopeDropdownOpen = false
        }
        deferredExecutionRequest = nil
        onClosePanel()
    }

    func togglePreview() {
        if isPreviewPresented {
            isPreviewPresented = false
            return
        }
        guard !isScopeSearchInFlight, selectedEntry != nil else {
            return
        }
        isPreviewPresented = true
    }

    func openPreview(at index: Int) {
        guard !isScopeSearchInFlight, entries.indices.contains(index) else {
            return
        }
        selectedIndex = index
        isPreviewPresented = true
    }

    func dismissPreview() {
        isPreviewPresented = false
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
        scrollSelectionRevision += 1
    }

    func selectEntry(at index: Int) {
        guard entries.indices.contains(index) else {
            return
        }
        if selectedIndex != index {
            selectedIndex = index
        }
    }

    func executeSelection(
        force: Bool = false,
        triggerSource: Constants.ExecutionTrigger = .keyboardSubmit
    ) {
        if let draft = quickCaptureDraft {
            guard draft.hasContent else {
                setTransientStatus(
                    draft.type == .todo ? "请输入待办内容后再按回车保存" : "请输入便签内容后再按回车保存",
                    tone: .info
                )
                return
            }
            quickCreateEntryFromPanel(type: draft.type)
            return
        }

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

        isPreviewPresented = false
        let executionProjectId = currentProjectId == Self.allProjectsScopeId ? entry.projectId : currentProjectId
        executeService.execute(
            entry: entry,
            currentProjectId: executionProjectId,
            triggerSource: triggerSource
        )
    }

    func activateScope(_ id: String) {
        activateProject(id)
    }

    func cycleScope(_ step: Int) {
        guard step != 0 else { return }
        let scopes = availableScopeIds
        guard !scopes.isEmpty else { return }
        guard scopes.count > 1 else {
            activateProject(scopes[0])
            return
        }
        let currentIndex = scopes.firstIndex(of: currentProjectId) ?? 0
        let count = scopes.count
        let offset = ((step % count) + count) % count
        let nextIndex = (currentIndex + offset) % count
        activateProject(scopes[nextIndex])
    }

    func setAllProjectsScope() {
        guard currentProjectId != Self.allProjectsScopeId else {
            return
        }
        if isPreviewPresented {
            isPreviewPresented = false
        }
        currentProjectId = Self.allProjectsScopeId
        scheduleEntriesRefresh(delayMs: 0, reason: .scopeChanged)
    }

    func activateProject(_ id: String) {
        guard !id.isEmpty, currentProjectId != id else {
            return
        }

        if id == Self.allProjectsScopeId {
            setAllProjectsScope()
            return
        }

        if isPreviewPresented {
            isPreviewPresented = false
        }

        do {
            try settingsRepository.setCurrentProjectId(id)
            appState.currentProjectId = id
            currentProjectId = id
            NotificationCenter.default.post(name: .currentProjectDidChange, object: self)
            scheduleEntriesRefresh(delayMs: 0, reason: .scopeChanged)
        } catch {
            PPLogger.project.error("Failed to switch current project: \(error.localizedDescription)")
            setStatus("切换项目失败，请重试。", tone: .error)
        }
    }

    private func observeChanges() {
        NotificationCenter.default.publisher(for: .projectsDidChange)
            .sink { [weak self] _ in
                guard let self else { return }
                self.loadProjects(preserveAllProjectsScope: true)
                self.scheduleEntriesRefresh(delayMs: 0, reason: .scopeChanged)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .currentProjectDidChange)
            .sink { [weak self] notification in
                guard let self else { return }
                guard (notification.object as AnyObject?) !== self else { return }
                self.currentProjectId = self.appState.effectiveProjectId
                self.loadProjects(preserveAllProjectsScope: false)
                self.scheduleEntriesRefresh(delayMs: 0, reason: .scopeChanged)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .entriesDidChange)
            .sink { [weak self] notification in
                guard let self else { return }
                guard (notification.object as AnyObject?) !== self else { return }
                self.scheduleEntriesRefresh(delayMs: 0, reason: .dataChanged)
            }
            .store(in: &cancellables)
    }

    private func loadProjects(preserveAllProjectsScope: Bool = true) {
        do {
            projects = try projectRepository.fetchAll(includeArchived: false)
            projectNamesById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
            if preserveAllProjectsScope, currentProjectId == Self.allProjectsScopeId {
                return
            }
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
        if projectId == Self.allProjectsScopeId {
            return Self.allProjectsScopeName
        }
        return projectNamesById[projectId]
    }

    /// Enters direct note / todo typing mode in the panel search bar (or switches an active
    /// quick-capture draft between `.note` and `.todo` while preserving typed body text),
    /// closing transient overlays and focusing the input field with cursor at the end.
    func startQuickCapture(type: Constants.EntryType = .note) {
        let targetType: Constants.EntryType = (type == .todo) ? .todo : .note
        let prefix = targetType == .todo ? "t " : "; "
        if let draft = quickCaptureDraft {
            let leadingTrimmed = String(query.drop(while: { $0 == " " || $0 == "\t" }))
            let remainder = String(leadingTrimmed.dropFirst(draft.matchedPrefix.count))
                .drop(while: { $0 == " " || $0 == "\t" })
            query = remainder.isEmpty ? prefix : "\(prefix)\(remainder)"
        } else {
            query = prefix
        }
        isScopeDropdownOpen = false
        isPreviewPresented = false
        focusToken += 1
    }

    /// Saves the current clipboard text directly as a scratchpad note in `速记与待办`.
    func quickCreateNoteFromClipboard() {
        let clipboardText = clipboardTextProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        refreshClipboardState()
        guard !clipboardText.isEmpty else {
            setTransientStatus("剪贴板暂无可保存的文本", tone: .info)
            return
        }
        guard let entryRepository else {
            onOpenSettings()
            return
        }
        if projects.isEmpty {
            loadProjects(preserveAllProjectsScope: true)
        }

        let targetProjectId = resolveTargetProjectId(for: .note)
        guard !targetProjectId.isEmpty else {
            onOpenSettings()
            return
        }

        let firstLine = clipboardText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "剪贴板便签"
        let title = String(firstLine.prefix(36))
        let newEntry = Entry(
            projectId: targetProjectId,
            title: title,
            content: clipboardText,
            type: Constants.EntryType.note.rawValue
        )

        do {
            try entryRepository.create(newEntry, changeNote: "剪贴板一键速记")
            if currentProjectId.isEmpty {
                activateProject(targetProjectId)
            } else {
                scheduleEntriesRefresh(delayMs: 0, reason: .dataChanged)
            }
            NotificationCenter.default.post(name: .entriesDidChange, object: self)
            setTransientStatus("已记入「速记与待办」：\(title)", tone: .info)
        } catch {
            PPLogger.entry.error("Failed to create note from clipboard in panel: \(error.localizedDescription)")
            setStatus("保存剪贴板便签失败，请重试。", tone: .error)
        }
    }

    /// Creates a new entry from the current search query (or clipboard if the query is empty)
    /// directly inside the quick panel, or opens the main window's entry editor when `entryRepository` is unavailable.
    func quickCreateEntryFromPanel(type: Constants.EntryType = .prompt) {
        if projects.isEmpty {
            loadProjects(preserveAllProjectsScope: true)
        }

        let hadQuery = !query.isEmpty
        let resolvedType: Constants.EntryType
        let rawContent: String
        let tags: [String]

        if let draft = quickCaptureDraft {
            resolvedType = (type == .note || type == .todo) ? type : draft.type
            if draft.hasContent {
                rawContent = draft.cleanedContent
                tags = draft.tags
            } else {
                let clipboardText = clipboardTextProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                rawContent = clipboardText
                tags = []
            }
        } else {
            resolvedType = type
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty {
                let extracted = Self.extractAllTags(from: trimmedQuery)
                rawContent = extracted.cleanedText.isEmpty ? trimmedQuery : extracted.cleanedText
                tags = extracted.tags
            } else {
                let clipboardText = clipboardTextProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                rawContent = clipboardText
                tags = []
            }
        }

        refreshClipboardState()
        guard !rawContent.isEmpty, let entryRepository else {
            onOpenSettings()
            return
        }

        let targetProjectId = resolveTargetProjectId(for: resolvedType)
        guard !targetProjectId.isEmpty else {
            onOpenSettings()
            return
        }

        let firstLine = rawContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "快捷新建"
        let title = String(firstLine.prefix(36))

        let newEntry = Entry(
            projectId: targetProjectId,
            title: title,
            content: rawContent,
            type: resolvedType.rawValue,
            tags: tags
        )

        do {
            try entryRepository.create(newEntry, changeNote: "快捷面板新建")
            isSuppressingQueryDidSet = true
            query = ""
            isSuppressingQueryDidSet = false
            isPreviewPresented = false

            let isInboxCapture = (resolvedType == .todo || resolvedType == .note)
            if currentProjectId.isEmpty {
                activateProject(targetProjectId)
            } else if !isInboxCapture,
                      currentProjectId != Self.allProjectsScopeId,
                      targetProjectId != currentProjectId,
                      targetProjectId != appState.defaultProjectId {
                activateProject(targetProjectId)
            } else {
                scheduleEntriesRefresh(delayMs: 0, reason: hadQuery ? .scopeChanged : .dataChanged)
            }
            NotificationCenter.default.post(name: .entriesDidChange, object: self)

            let targetIsInbox = targetProjectId == Constants.inboxProjectId
                || projects.first(where: { $0.id == targetProjectId })?.groupKind == .inbox
            if isInboxCapture && targetIsInbox {
                setTransientStatus("已记入「速记与待办」：\(title)", tone: .info)
            } else {
                setTransientStatus("已新建词条：\(title)", tone: .info)
            }
        } catch {
            PPLogger.entry.error("Failed to quick-create entry from panel: \(error.localizedDescription)")
            setStatus("新建词条失败，请重试。", tone: .error)
        }
    }

    private func resolveTargetProjectId(for type: Constants.EntryType) -> String {
        if type == .todo || type == .note {
            if let inbox = projects.first(where: { $0.groupKind == .inbox }) {
                return inbox.id
            }
            if let persistedInbox = try? projectRepository.fetchById(Constants.inboxProjectId) {
                return persistedInbox.id
            }
        }
        if !currentProjectId.isEmpty, currentProjectId != Self.allProjectsScopeId {
            return currentProjectId
        }
        let effective = appState.effectiveProjectId
        if !effective.isEmpty, effective != Self.allProjectsScopeId {
            return effective
        }
        return appState.defaultProjectId ?? projects.first?.id ?? ""
    }

    func toggleEntryCompleted(_ entry: Entry) {
        guard let entryRepository else { return }
        let nextState = !entry.isCompleted
        do {
            try entryRepository.setCompleted(id: entry.id, isCompleted: nextState)
            NotificationCenter.default.post(name: .entriesDidChange, object: self)
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
            NotificationCenter.default.post(name: .entriesDidChange, object: self)
            scheduleEntriesRefresh(delayMs: 0, reason: .dataChanged)
        } catch {
            PPLogger.entry.error("Failed to toggle entry pin in panel: \(error.localizedDescription)")
            setStatus("更新置顶状态失败，请重试。", tone: .error)
        }
    }

    func countForFilter(_ filter: KindFilter) -> Int {
        guard filter != .all else { return unfilteredEntries.count }
        return unfilteredEntries.reduce(into: 0) { count, entry in
            if filter.matches(entry) {
                count += 1
            }
        }
    }

    nonisolated static func filterEntries(_ entries: [Entry], by filter: KindFilter) -> [Entry] {
        guard filter != .all else { return entries }
        return entries.filter { filter.matches($0) }
    }

    private func scheduleEntriesRefresh(delayMs: Int, reason: EntriesRefreshReason) {
        pendingSearchWorkItem?.cancel()
        pendingSearchWorkItem = nil

        if Self.parseQuickCapture(from: self.query) != nil {
            isLoadingEntries = false
            isScopeSearchInFlight = false
            deferredExecutionRequest = nil
            return
        }

        guard !appState.effectiveProjectId.isEmpty || !currentProjectId.isEmpty else {
            unfilteredEntries = []
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

        if effectiveCurrentProjectId != Self.allProjectsScopeId,
           appState.currentProjectId != effectiveCurrentProjectId {
            appState.currentProjectId = effectiveCurrentProjectId
        }
        if reason == .scopeChanged {
            isScopeSearchInFlight = true
            deferredExecutionRequest = nil
            if selectedIndex != 0 {
                selectedIndex = 0
            }
        }
        // Keep existing entries visible while the background query runs so the
        // ScrollView/LazyVStack is never torn down and recreated on keystrokes.
        let shouldShowLoading = entries.isEmpty
        if isLoadingEntries != shouldShowLoading {
            isLoadingEntries = shouldShowLoading
        }
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
                    case .success(let (sortedEntries, isGlobalFallback)):
                        if self.isLoadingEntries {
                            self.isLoadingEntries = false
                        }
                        if self.isShowingGlobalFallback != isGlobalFallback {
                            self.isShowingGlobalFallback = isGlobalFallback
                        }
                        let previousSelectionId = self.selectedEntry?.id
                        if self.unfilteredEntries != sortedEntries {
                            self.unfilteredEntries = sortedEntries
                        }
                        let visibleEntries = Self.filterEntries(sortedEntries, by: self.activeKindFilter)
                        if self.entries != visibleEntries {
                            self.entries = visibleEntries
                        }
                        if visibleEntries.isEmpty || reason == .scopeChanged {
                            if self.selectedIndex != 0 {
                                self.selectedIndex = 0
                            }
                            self.scrollSelectionRevision += 1
                        } else if let previousSelectionId,
                                  let index = visibleEntries.firstIndex(where: { $0.id == previousSelectionId }) {
                            if self.selectedIndex != index {
                                self.selectedIndex = index
                            }
                        } else {
                            let clamped = min(self.selectedIndex, visibleEntries.count - 1)
                            if self.selectedIndex != clamped {
                                self.selectedIndex = clamped
                            }
                        }
                        if visibleEntries.isEmpty, self.isPreviewPresented {
                            self.isPreviewPresented = false
                        }
                        self.applyBaseStatus()
                        if let pendingExecution, !visibleEntries.isEmpty {
                            switch pendingExecution.target {
                            case .selected:
                                self.executeSelection(
                                    force: pendingExecution.force,
                                    triggerSource: pendingExecution.triggerSource
                                )
                            case .index(let targetIndex):
                                guard visibleEntries.indices.contains(targetIndex) else {
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
                        self.unfilteredEntries = []
                        self.entries = []
                        self.selectedIndex = 0
                        self.isPreviewPresented = false
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
        if let transientStatus, Date() < transientStatus.expiresAt {
            if statusMessage != transientStatus.message {
                statusMessage = transientStatus.message
            }
            if statusTone != transientStatus.tone {
                statusTone = transientStatus.tone
            }
            return
        }
        transientStatus = nil

        guard permissionService.isAccessibilityGranted == false else {
            if statusMessage != nil {
                statusMessage = nil
            }
            if statusTone != .info {
                statusTone = .info
            }
            return
        }

        let warningMessage = "未授权辅助功能，当前仅复制到剪贴板"
        if statusMessage != warningMessage {
            statusMessage = warningMessage
        }
        if statusTone != .warning {
            statusTone = .warning
        }
    }

    private func setStatus(_ message: String, tone: StatusTone) {
        transientStatusResetWorkItem?.cancel()
        transientStatusResetWorkItem = nil
        transientStatus = nil
        statusMessage = message
        statusTone = tone
    }

    private func setTransientStatus(
        _ message: String,
        tone: StatusTone,
        duration: TimeInterval = transientStatusDuration
    ) {
        transientStatusResetWorkItem?.cancel()
        let expiresAt = Date().addingTimeInterval(duration)
        transientStatus = (message: message, tone: tone, expiresAt: expiresAt)
        statusMessage = message
        statusTone = tone

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.transientStatus = nil
            self.applyBaseStatus()
        }
        transientStatusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func clearTransientStatus(reapplyBase: Bool) {
        transientStatusResetWorkItem?.cancel()
        transientStatusResetWorkItem = nil
        transientStatus = nil
        if reapplyBase {
            applyBaseStatus()
        }
    }

    /// Order panel results by the same stable keys as the repository so shortcut
    /// numbers do not drift between browsing, searching, and project switching.
    /// Completed items always sink below incomplete items.
    nonisolated static func applyPanelRankingSort(
        _ entries: [Entry],
        currentProjectId: String,
        now: Date = Date()
    ) -> [Entry] {
        let priorityProjectId: String? = (currentProjectId == allProjectsScopeId || currentProjectId.isEmpty)
            ? nil
            : currentProjectId
        return entries.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            return EntryRanking.isOrderedBefore(lhs, rhs, currentProjectId: priorityProjectId, now: now)
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

    /// Extracts all `#tag` tokens from free-form capture text while preserving multi-line structure.
    nonisolated static func extractAllTags(from text: String) -> (cleanedText: String, tags: [String]) {
        var rawTags: [String] = []
        var cleanedLines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            var lineWords: [String] = []
            for token in line.split(whereSeparator: { $0.isWhitespace }) {
                if token.hasPrefix("#"), token.count > 1, !token.dropFirst().hasPrefix("#") {
                    rawTags.append(String(token.dropFirst()))
                } else {
                    lineWords.append(String(token))
                }
            }
            cleanedLines.append(lineWords.joined(separator: " "))
        }

        let normalizedTags = Entry.normalizeTags(rawTags)
        let joined = cleanedLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if joined.isEmpty, !normalizedTags.isEmpty {
            return (normalizedTags.joined(separator: " "), normalizedTags)
        }
        return (joined, normalizedTags)
    }

    /// Detects instant note / todo capture prefixes in the panel search query.
    nonisolated static func parseQuickCapture(from query: String) -> QuickCaptureDraft? {
        let leadingTrimmed = String(query.drop(while: { $0 == " " || $0 == "\t" }))
        guard !leadingTrimmed.isEmpty else {
            return nil
        }

        let lowercased = leadingTrimmed.lowercased()
        let prefixRules: [(prefix: String, type: Constants.EntryType, caseInsensitive: Bool)] = [
            ("[ ] ", .todo, false),
            ("[] ", .todo, false),
            ("todo:", .todo, true),
            ("todo：", .todo, true),
            ("待办:", .todo, false),
            ("待办：", .todo, false),
            ("t ", .todo, true),
            ("note:", .note, true),
            ("note：", .note, true),
            ("便签:", .note, false),
            ("便签：", .note, false),
            ("; ", .note, false),
            ("；", .note, false),
            ("n ", .note, true)
        ]

        for rule in prefixRules {
            let matches = rule.caseInsensitive
                ? lowercased.hasPrefix(rule.prefix)
                : leadingTrimmed.hasPrefix(rule.prefix)
            guard matches else { continue }

            let matchedPrefix = String(leadingTrimmed.prefix(rule.prefix.count))
            let rawBody = String(leadingTrimmed.dropFirst(rule.prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let (cleanedContent, tags) = extractAllTags(from: rawBody)
            let firstLine = cleanedContent
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? ""
            let title = String(firstLine.prefix(36))

            return QuickCaptureDraft(
                type: rule.type,
                matchedPrefix: matchedPrefix,
                rawBody: rawBody,
                title: title,
                cleanedContent: cleanedContent,
                tags: tags
            )
        }
        return nil
    }

    // MARK: - Panel shortcuts

    /// A shortcut combination the quick panel owns.
    ///
    /// These cannot be expressed as SwiftUI `keyboardShortcut`s or solely as a
    /// `keyDown` handler on the search field: while the field is being edited
    /// the field editor is first responder, and AppKit resolves ⌘-combinations
    /// through key-equivalent dispatch (main menu included) before any
    /// `keyDown:` runs. `PanelService` therefore feeds raw key events here from
    /// a local event monitor, which fires ahead of all of that.
    enum PanelKeyCommand: Equatable {
        case executeEntry(number: Int)
        case copySelection
        case togglePin
        case togglePreview
        case quickCreateEntry
        case quickCreateNote
        case quickCreateTodo
        case closePanel
    }

    private static let escapeKeyCode: UInt16 = 53
    private static let returnKeyCode: UInt16 = 36
    private static let keypadEnterKeyCode: UInt16 = 76

    /// Pure mapping from a key event to a panel command.
    static func panelKeyCommand(
        keyCode: UInt16 = .max,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?
    ) -> PanelKeyCommand? {
        let flags = modifierFlags.intersection([.command, .shift, .option, .control])

        // Esc is handled here rather than only on the search field: once focus
        // moves off the field (a background click, a preview pane) the field's
        // key handling stops running and the panel would have no way out.
        if keyCode == escapeKeyCode, flags.isEmpty {
            return .closePanel
        }

        if keyCode == returnKeyCode || keyCode == keypadEnterKeyCode {
            if flags == [.shift] {
                return .quickCreateNote
            }
            if flags == [.option] {
                return .quickCreateTodo
            }
        }

        guard flags == [.command] else {
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
        case "y":
            return .togglePreview
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
            guard !isQuickCaptureMode, (1...9).contains(number) else {
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
            guard !isQuickCaptureMode, !isScopeSearchInFlight, selectedEntry != nil else {
                return false
            }
            copySelectionOnly()
        case .togglePin:
            togglePanelPinned()
        case .togglePreview:
            if isPreviewPresented {
                dismissPreview()
                return true
            }
            guard !isQuickCaptureMode, !isScopeSearchInFlight, selectedEntry != nil else {
                return false
            }
            togglePreview()
        case .quickCreateEntry:
            quickCreateEntryFromPanel(type: defaultQuickCreateType)
        case .quickCreateNote:
            quickCreateEntryFromPanel(type: .note)
        case .quickCreateTodo:
            quickCreateEntryFromPanel(type: .todo)
        case .closePanel:
            handleEscape()
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
            isPreviewPresented = false
            setStatus("已复制到剪贴板：\(entry.title)", tone: .info)
            executeService.onShowNotification?("已复制：\(entry.title)", true)
            onClosePanel()
        } else {
            setStatus("复制到剪贴板失败，请重试。", tone: .error)
            executeService.onShowNotification?("复制到剪贴板失败，请重试。", false)
        }
    }
}
