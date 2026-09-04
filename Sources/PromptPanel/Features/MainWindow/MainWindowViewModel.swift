import AppKit
import Combine
import Foundation
import KeyboardShortcuts
import UniformTypeIdentifiers

@MainActor
final class MainWindowViewModel: ObservableObject {
    static let allProjectsSelection = "__all_projects__"

    enum Tab: Hashable {
        case library
        case settings
    }

    enum EntrySortMode: String, CaseIterable, Identifiable {
        case uses
        case byLevel = "by_level"
        case recent
        case alpha

        var id: String { rawValue }

        var title: String {
            switch self {
            case .uses: return "按使用"
            case .byLevel: return "按等级"
            case .recent: return "按最近"
            case .alpha: return "按字母"
            }
        }

        static func resolve(_ rawValue: String?) -> EntrySortMode {
            guard let rawValue, let parsed = EntrySortMode(rawValue: rawValue) else {
                return .uses
            }
            return parsed
        }
    }

    struct EntryTagFacet: Identifiable, Equatable {
        let tag: String
        let count: Int

        var id: String { tag }
    }

    struct ProjectDraft: Identifiable {
        let id: String
        let existingProject: Project?
        var name: String

        init(existingProject: Project?) {
            self.id = existingProject?.id ?? UUID().uuidString
            self.existingProject = existingProject
            self.name = existingProject?.name ?? ""
        }
    }

    struct ProjectDeletionState: Identifiable {
        let id: String
        let project: Project
        let entryCount: Int
        var targetProjectId: String

        init(project: Project, entryCount: Int, targetProjectId: String) {
            self.id = project.id
            self.project = project
            self.entryCount = entryCount
            self.targetProjectId = targetProjectId
        }
    }

    struct EntryDraft: Identifiable {
        let id: String
        let existingEntry: Entry?
        var title: String
        var content: String
        var projectId: String
        var type: String
        var isPinned: Bool
        var sortOrder: Int
        var tagsText: String

        init(existingEntry: Entry?, defaultProjectId: String) {
            self.id = existingEntry?.id ?? UUID().uuidString
            self.existingEntry = existingEntry
            self.title = existingEntry?.title ?? ""
            self.content = existingEntry?.content ?? ""
            self.projectId = existingEntry?.projectId ?? defaultProjectId
            self.type = existingEntry?.type ?? Constants.EntryType.prompt.rawValue
            self.isPinned = existingEntry?.isPinned ?? false
            self.sortOrder = existingEntry?.sortOrder ?? 0
            self.tagsText = (existingEntry?.tags ?? []).joined(separator: ", ")
        }

        var parsedTags: [String] {
            Entry.normalizeTags(
                tagsText
                    .components(separatedBy: CharacterSet(charactersIn: ",，、 "))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            )
        }
    }

    @Published private(set) var projects: [Project] = []
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var displayedEntries: [Entry] = []
    @Published private(set) var recentExecutionLogs: [ExecutionLog] = []
    @Published private(set) var storageHealthSnapshot: StorageHealthSnapshot?
    @Published private(set) var executionHealthSummary: LogRepository.HealthSummary?
    @Published private(set) var updaterStatusMessage: String = "自动更新未初始化。"
    @Published private(set) var canCheckForUpdates: Bool = false
    @Published private(set) var currentProjectId: String = ""
    @Published var selectedTab: Tab = .library
    @Published var selectedProjectId: String = MainWindowViewModel.allProjectsSelection {
        didSet {
            scheduleEntriesRefresh(delayMs: 0)
        }
    }
    @Published var entrySearchText: String = "" {
        didSet {
            scheduleEntriesRefresh(delayMs: Constants.mainWindowSearchDebounceMs)
        }
    }
    @Published var selectedEntryId: String?
    /// Bumped to move focus into the library search field (⌘F).
    @Published private(set) var searchFocusToken: Int = 0
    @Published var entryKindFilter: String? {
        didSet {
            refreshDisplayedEntriesUnlessBatching()
        }
    }
    @Published var entryTagFilter: String? {
        didSet {
            refreshDisplayedEntriesUnlessBatching()
        }
    }
    @Published var entrySortMode: EntrySortMode = .uses {
        didSet {
            guard oldValue != entrySortMode else { return }
            persistEntrySortMode()
            refreshDisplayedEntries()
        }
    }
    @Published private(set) var projectEntryCounts: [String: Int] = [:]
    @Published private(set) var totalEntryCount: Int = 0
    /// Filter-bar facets, recomputed once whenever `entries` changes.
    ///
    /// These were computed properties called straight from `body`: `availableEntryKinds`
    /// and `topTags()` each walked every loaded entry, `topTags()` ran three times per
    /// pass and `kindCount(for:)` once per chip. On a library of any size that is a
    /// full scan several times over for every keystroke in the search field.
    @Published private(set) var availableEntryKinds: [Constants.EntryType] = []
    @Published private(set) var entryKindCounts: [String: Int] = [:]
    @Published private(set) var topTags: [EntryTagFacet] = []
    /// Project id → name, so a row does not linear-scan the project list to render.
    @Published private(set) var projectNamesById: [String: String] = [:]
    @Published var projectDraft: ProjectDraft?
    @Published var entryDraft: EntryDraft?
    @Published var deleteProjectState: ProjectDeletionState?
    @Published var entryPendingDeletion: Entry?
    @Published var hasAccessibilityPermission: Bool = false
    @Published var launchAtLoginEnabled: Bool = false
    /// Transient status line shown above both tabs.
    ///
    /// It used to be rendered only inside the settings tab, so every message raised
    /// from the library — "已复制到剪贴板", "词条已删除", every save failure — was set
    /// and never seen. And nothing ever cleared it, so whatever was last shown sat
    /// at the top of settings until the window was reopened.
    @Published var bannerMessage: String? {
        didSet {
            scheduleBannerAutoDismiss()
        }
    }
    /// Non-nil while a maintenance action (backup / export / import / diagnostics)
    /// is running off the main thread. Drives the busy row in the settings tab and
    /// blocks a second action from starting on top of the first.
    @Published private(set) var activeMaintenanceTask: String?
    @Published var isPanelPinned: Bool = false
    @Published var panelShowFooter: Bool = true
    @Published var panelCompactRows: Bool = false
    @Published var panelContentSize: NSSize = Constants.panelContentSize
    @Published var appTheme: AppTheme = .system
    private let appState: AppState
    private let projectRepository: ProjectRepository
    private let entryRepository: EntryRepository
    private let settingsRepository: SettingsRepository
    private let logRepository: LogRepository
    private let permissionService: PermissionService
    private let loginItemService: LoginItemService
    private let storageMaintenanceService: StorageMaintenanceService
    private let libraryTransferService: LibraryTransferService
    private let updaterService: UpdaterService
    private let launchRecoveryReport: LaunchRecoveryReport?
    private let onSetPanelPinned: (Bool) -> Bool
    private let onSetPanelContentSize: (NSSize) -> Bool
    private let onCopyEntry: ((Entry) -> Bool)?
    /// The window that save/open panels attach to as a sheet. A sheet keeps the
    /// window responsive; `runModal()` used to spin a nested modal loop on the
    /// main thread, which is what made "导出" look like it had frozen the window.
    private let hostWindowProvider: @MainActor () -> NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private let entriesLoadQueue = DispatchQueue(label: "PromptPanel.main-window.entries", qos: .userInitiated)
    /// Serial on purpose: backup, export and import all touch the same SQLite file,
    /// and running them one at a time is both correct and enough — the point is only
    /// to keep them off the main thread.
    private let maintenanceQueue = DispatchQueue(label: "PromptPanel.main-window.maintenance", qos: .userInitiated)
    private let statusQueue = DispatchQueue(label: "PromptPanel.main-window.status", qos: .utility)
    private var pendingEntriesRefreshWorkItem: DispatchWorkItem?
    private var entriesRefreshGeneration: Int = 0
    private var isBatchingEntryFilterUpdate = false
    private var operationalStatusGeneration: Int = 0
    private var hasCompletedInitialLoad = false
    private var bannerDismissWorkItem: DispatchWorkItem?
    static let bannerAutoDismissInterval: TimeInterval = 8

    init(
        appState: AppState,
        projectRepository: ProjectRepository,
        entryRepository: EntryRepository,
        settingsRepository: SettingsRepository,
        logRepository: LogRepository,
        permissionService: PermissionService,
        loginItemService: LoginItemService,
        storageMaintenanceService: StorageMaintenanceService,
        libraryTransferService: LibraryTransferService? = nil,
        updaterService: UpdaterService,
        launchRecoveryReport: LaunchRecoveryReport?,
        onSetPanelPinned: @escaping (Bool) -> Bool = { _ in false },
        onSetPanelContentSize: @escaping (NSSize) -> Bool = { _ in false },
        onCopyEntry: ((Entry) -> Bool)? = nil,
        hostWindowProvider: (@MainActor () -> NSWindow?)? = nil
    ) {
        self.appState = appState
        self.projectRepository = projectRepository
        self.entryRepository = entryRepository
        self.settingsRepository = settingsRepository
        self.logRepository = logRepository
        self.permissionService = permissionService
        self.loginItemService = loginItemService
        self.storageMaintenanceService = storageMaintenanceService
        self.libraryTransferService = libraryTransferService ?? LibraryTransferService(
            projectRepository: projectRepository,
            entryRepository: entryRepository,
            storageMaintenanceService: storageMaintenanceService
        )
        self.updaterService = updaterService
        self.launchRecoveryReport = launchRecoveryReport
        self.onSetPanelPinned = onSetPanelPinned
        self.onSetPanelContentSize = onSetPanelContentSize
        self.onCopyEntry = onCopyEntry
        self.hostWindowProvider = hostWindowProvider ?? { NSApp.keyWindow ?? NSApp.mainWindow }

        // Hydrate persisted sort preference before any view binds the publisher,
        // so the sort dropdown opens with the user's saved choice instead of
        // briefly flashing the default.
        if let stored = try? settingsRepository.getEntrySortMode() {
            self.entrySortMode = EntrySortMode.resolve(stored)
        }

        observeChanges()
    }

    deinit {
        pendingEntriesRefreshWorkItem?.cancel()
        bannerDismissWorkItem?.cancel()
    }

    /// Clear a banner once it has had time to be read. A running maintenance task
    /// owns the banner as its progress line, so it is exempt until it finishes —
    /// `activeMaintenanceTask`'s completion sets a fresh message, which re-arms this.
    private func scheduleBannerAutoDismiss() {
        bannerDismissWorkItem?.cancel()
        bannerDismissWorkItem = nil
        guard bannerMessage != nil, activeMaintenanceTask == nil else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeMaintenanceTask == nil else { return }
            self.bannerMessage = nil
        }
        bannerDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bannerAutoDismissInterval, execute: workItem)
    }

    var selectedProject: Project? {
        projects.first(where: { $0.id == selectedProjectId })
    }

    var projectOptions: [Project] {
        projects
    }

    var selectedEntry: Entry? {
        let visibleEntries = displayedEntries
        guard let selectedEntryId else {
            return visibleEntries.first
        }
        return visibleEntries.first(where: { $0.id == selectedEntryId }) ?? visibleEntries.first
    }

    static let topTagFacetLimit = 8

    /// One pass over `entries` producing every facet the filter bar needs.
    /// Called from the single place `entries` is assigned.
    private func refreshEntryFacets() {
        var kinds: [Constants.EntryType] = []
        var seenKinds = Set<String>()
        var kindCounts: [String: Int] = [:]
        var tagCounts: [String: Int] = [:]

        for entry in entries {
            let type = Constants.EntryType.resolve(entry.type)
            if seenKinds.insert(type.rawValue).inserted {
                kinds.append(type)
            }
            kindCounts[entry.type, default: 0] += 1
            for tag in entry.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        availableEntryKinds = kinds
        entryKindCounts = kindCounts
        topTags = tagCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .prefix(Self.topTagFacetLimit)
            .map { EntryTagFacet(tag: $0.key, count: $0.value) }
    }

    func entryCount(forKind kind: Constants.EntryType) -> Int {
        entryKindCounts[kind.rawValue] ?? 0
    }

    func projectName(forEntry entry: Entry) -> String? {
        projectNamesById[entry.projectId]
    }

    private func sortedVisibleEntries() -> [Entry] {
        let filtered: [Entry] = entries.filter { entry in
            if let kind = entryKindFilter, entry.type != kind {
                return false
            }
            if let tag = entryTagFilter, entry.tags.contains(tag) == false {
                return false
            }
            return true
        }
        return filtered.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned
            }
            switch entrySortMode {
            case .uses:
                if lhs.useCount != rhs.useCount {
                    return lhs.useCount > rhs.useCount
                }
                return compareEntriesByRecencyThenTitle(lhs, rhs)
            case .byLevel:
                // Why distinct from `.uses`: same color tier groups together
                // and within the tier we surface "what did I touch most recently"
                // rather than "what has the highest raw count". Without this
                // tiebreak the two modes would be observationally identical
                // (level is monotone in useCount), making the toggle pointless.
                let lhsLevel = Constants.EntryLevel.resolve(useCount: lhs.useCount).rawValue
                let rhsLevel = Constants.EntryLevel.resolve(useCount: rhs.useCount).rawValue
                if lhsLevel != rhsLevel {
                    return lhsLevel > rhsLevel
                }
                return compareEntriesByRecencyThenTitle(lhs, rhs)
            case .recent:
                return compareEntriesByRecencyThenTitle(lhs, rhs)
            case .alpha:
                let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if titleComparison != .orderedSame {
                    return titleComparison == .orderedAscending
                }
                return compareEntriesByRecencyThenId(lhs, rhs)
            }
        }
    }

    private func refreshDisplayedEntries() {
        displayedEntries = sortedVisibleEntries()
        if let selectedEntryId, displayedEntries.contains(where: { $0.id == selectedEntryId }) == false {
            self.selectedEntryId = displayedEntries.first?.id
        } else if selectedEntryId == nil {
            selectedEntryId = displayedEntries.first?.id
        }
    }

    private func refreshDisplayedEntriesUnlessBatching() {
        guard !isBatchingEntryFilterUpdate else {
            return
        }
        refreshDisplayedEntries()
    }

    private func updateEntryFilters(kind: String?, tag: String?) {
        isBatchingEntryFilterUpdate = true
        entryKindFilter = kind
        entryTagFilter = tag
        isBatchingEntryFilterUpdate = false
        refreshDisplayedEntries()
    }

    private func compareEntriesByRecencyThenTitle(_ lhs: Entry, _ rhs: Entry) -> Bool {
        let lhsDate = lhs.lastUsedAt ?? lhs.updatedAt
        let rhsDate = rhs.lastUsedAt ?? rhs.updatedAt
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.id < rhs.id
    }

    private func compareEntriesByRecencyThenId(_ lhs: Entry, _ rhs: Entry) -> Bool {
        let lhsDate = lhs.lastUsedAt ?? lhs.updatedAt
        let rhsDate = rhs.lastUsedAt ?? rhs.updatedAt
        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }
        return lhs.id < rhs.id
    }

    func entryCount(forProjectId id: String) -> Int {
        projectEntryCounts[id] ?? 0
    }

    private func refreshProjectEntryCounts() {
        let entryRepository = self.entryRepository
        entriesLoadQueue.async {
            guard let counts = try? entryRepository.entryCountByProject() else {
                PPLogger.entry.error("Failed to load project entry counts")
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.projectEntryCounts = counts
                self.totalEntryCount = counts.values.reduce(0, +)
            }
        }
    }

    func toggleEntryKindFilter(_ type: Constants.EntryType) {
        if entryKindFilter == type.rawValue {
            updateEntryFilters(kind: nil, tag: entryTagFilter)
        } else {
            updateEntryFilters(kind: type.rawValue, tag: nil)
        }
    }

    func toggleEntryTagFilter(_ tag: String) {
        if entryTagFilter == tag {
            updateEntryFilters(kind: entryKindFilter, tag: nil)
        } else {
            updateEntryFilters(kind: nil, tag: tag)
        }
    }

    func clearEntryFilters() {
        updateEntryFilters(kind: nil, tag: nil)
    }

    // MARK: - Main window shortcuts

    /// A ⌘-combination the main window owns.
    ///
    /// The library drew ⌘F / ⌘C / ⌘E next to the controls they belong to, but
    /// nothing implemented them: ⌘C fell through to the Edit menu's generic
    /// Copy, and ⌘F / ⌘E did nothing at all.
    ///
    /// Copy-entry is bound to ⇧⌘C rather than ⌘C on purpose. The preview pane's
    /// content is selectable, so claiming plain ⌘C would mean a user who
    /// highlights part of a prompt and copies it silently gets the whole entry
    /// instead. ⇧⌘C is unclaimed, leaves ⌘C alone everywhere, and still gives
    /// the action a keyboard route.
    enum MainWindowKeyCommand: Equatable {
        case focusSearch
        case copySelectedEntry
        case editSelectedEntry
    }

    static func mainWindowKeyCommand(
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?
    ) -> MainWindowKeyCommand? {
        guard modifierFlags.contains(.command) else {
            return nil
        }
        guard modifierFlags.isDisjoint(with: [.option, .control]) else {
            return nil
        }
        let characters = charactersIgnoringModifiers?.lowercased()
        if modifierFlags.contains(.shift) {
            return characters == "c" ? .copySelectedEntry : nil
        }
        switch characters {
        case "f": return .focusSearch
        case "e": return .editSelectedEntry
        default: return nil
        }
    }

    /// Run a main-window command. Returns `false` when it does not apply, so
    /// the caller lets AppKit handle the event normally — that is what keeps
    /// ⌘C copying highlighted text when no entry is selected.
    @discardableResult
    func handleMainWindowKeyCommand(_ command: MainWindowKeyCommand) -> Bool {
        guard selectedTab == .library else {
            return false
        }
        switch command {
        case .focusSearch:
            searchFocusToken += 1
        case .copySelectedEntry:
            guard let entry = selectedEntry else {
                return false
            }
            copyEntryContent(entry)
        case .editSelectedEntry:
            guard let entry = selectedEntry else {
                return false
            }
            startEditEntry(entry)
        }
        return true
    }

    func copyEntryContent(_ entry: Entry) {
        if let onCopyEntry, onCopyEntry(entry) {
            bannerMessage = "已复制到剪贴板：\(entry.title)"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(entry.content, forType: .string) {
            bannerMessage = "已复制到剪贴板：\(entry.title)"
        } else {
            bannerMessage = "复制到剪贴板失败，请重试。"
        }
    }

    func togglePin(_ entry: Entry) {
        var updated = entry
        updated.isPinned.toggle()
        updated.updatedAt = Date()
        do {
            try entryRepository.update(updated)
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            bannerMessage = updated.isPinned ? "已置顶词条。" : "已取消置顶。"
        } catch {
            PPLogger.entry.error("Failed to toggle pin: \(error.localizedDescription)")
            bannerMessage = "更新置顶失败，请重试。"
        }
    }

    /// Called both from `openMainWindow` and from the view's `onAppear`, which fire
    /// back to back the first time the window is shown. Everything here is either
    /// idempotent or coalesced, and the expensive parts (storage health, logs) run
    /// off the main thread.
    func load() {
        syncCurrentProjectId()
        refreshPermissionState()
        loadProjects()
        refreshProjectEntryCounts()
        scheduleEntriesRefresh(delayMs: 0)
        refreshLogs()
        refreshOperationalStatus()
        refreshUpdaterStatus()
        if let launchRecoveryReport, !hasCompletedInitialLoad {
            bannerMessage = launchRecoveryReport.userFacingMessage
        }
        hasCompletedInitialLoad = true
    }

    /// The cheap half: `AXIsProcessTrusted()` plus in-memory app state. The login-item
    /// lookup is deliberately *not* here — see `refreshLaunchAtLoginState()`.
    func refreshPermissionState() {
        permissionService.refresh()
        hasAccessibilityPermission = permissionService.isAccessibilityGranted
        isPanelPinned = appState.isPanelPinned
        panelShowFooter = appState.panelShowFooter
        panelCompactRows = appState.panelCompactRows
        panelContentSize = appState.panelContentSize
        appTheme = appState.appTheme
        refreshLaunchAtLoginState()
    }

    /// `SMAppService.mainApp.status` is a synchronous round-trip to the service
    /// management daemon. It used to run inside `refreshPermissionState()`, which is
    /// called on every `applicationDidBecomeActive` — including the one fired when a
    /// save panel closes, so it landed right in the middle of the export interaction.
    private func refreshLaunchAtLoginState() {
        let loginItemService = self.loginItemService
        statusQueue.async {
            let isEnabled = loginItemService.isEnabled
            DispatchQueue.main.async { [weak self] in
                guard let self, self.launchAtLoginEnabled != isEnabled else { return }
                self.launchAtLoginEnabled = isEnabled
            }
        }
    }

    private func persistEntrySortMode() {
        do {
            try settingsRepository.setEntrySortMode(entrySortMode.rawValue)
        } catch {
            // Non-fatal: the in-memory choice still applies; we'll retry on the
            // next change. No user-visible banner — the dropdown already gave
            // them feedback that the click was received.
            PPLogger.entry.error("Failed to persist entry sort mode: \(error.localizedDescription)")
        }
    }

    func setAppTheme(_ theme: AppTheme) {
        do {
            try settingsRepository.setAppTheme(theme)
            appState.appTheme = theme
            appTheme = theme
        } catch {
            PPLogger.app.error("Failed to persist app theme: \(error.localizedDescription)")
            appTheme = appState.appTheme
            bannerMessage = "保存外观失败，请重试。"
        }
    }

    func setPanelShowFooter(_ isVisible: Bool) {
        do {
            try settingsRepository.setPanelFooterVisible(isVisible)
            appState.panelShowFooter = isVisible
            panelShowFooter = isVisible
        } catch {
            PPLogger.panel.error("Failed to persist panel footer visibility: \(error.localizedDescription)")
            panelShowFooter = appState.panelShowFooter
            bannerMessage = "保存面板提示栏开关失败，请重试。"
        }
    }

    func setPanelCompactRows(_ isCompact: Bool) {
        do {
            try settingsRepository.setPanelCompactRows(isCompact)
            appState.panelCompactRows = isCompact
            panelCompactRows = isCompact
        } catch {
            PPLogger.panel.error("Failed to persist panel compact rows: \(error.localizedDescription)")
            panelCompactRows = appState.panelCompactRows
            bannerMessage = "保存紧凑行高开关失败，请重试。"
        }
    }

    func setPanelPinned(_ isPinned: Bool) {
        guard onSetPanelPinned(isPinned) else {
            self.isPanelPinned = appState.isPanelPinned
            bannerMessage = "固定状态保存失败，请重试。"
            return
        }
        self.isPanelPinned = appState.isPanelPinned
        bannerMessage = self.isPanelPinned ? "快捷面板已固定置顶。" : "快捷面板已恢复临时置顶。"
    }

    func setPanelContentWidth(_ width: Int) {
        setPanelContentSize(NSSize(width: CGFloat(width), height: panelContentSize.height))
    }

    func setPanelContentHeight(_ height: Int) {
        setPanelContentSize(NSSize(width: panelContentSize.width, height: CGFloat(height)))
    }

    func resetPanelContentSize() {
        setPanelContentSize(Constants.panelContentSize, successMessage: "快捷面板尺寸已恢复默认。")
    }

    private func setPanelContentSize(_ size: NSSize, successMessage: String? = nil) {
        guard onSetPanelContentSize(size) else {
            panelContentSize = appState.panelContentSize
            bannerMessage = "保存面板尺寸失败，请重试。"
            return
        }
        panelContentSize = appState.panelContentSize
        if let successMessage {
            bannerMessage = successMessage
        }
    }

    func hotkeySummary() -> String {
        guard let shortcut = KeyboardShortcuts.Name.togglePanel.shortcut else {
            return "未设置快捷键"
        }
        return shortcut.description
    }

    func refreshLogs() {
        let logRepository = self.logRepository
        statusQueue.async {
            let result = Result { try logRepository.fetchRecent(limit: 50) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let logs):
                    self.recentExecutionLogs = logs
                case .failure(let error):
                    PPLogger.execute.error("Failed to load execution logs: \(error.localizedDescription)")
                    self.recentExecutionLogs = []
                    self.bannerMessage = "加载执行日志失败。"
                }
            }
        }
    }

    /// Storage health touches the filesystem (backup directory enumeration + a stat per
    /// backup) and the database. It is refreshed on load, after every maintenance action
    /// and on every execution-log change, so running it inline stuttered the window each
    /// time an entry was pasted.
    func refreshOperationalStatus() {
        let storageMaintenanceService = self.storageMaintenanceService
        let logRepository = self.logRepository
        operationalStatusGeneration += 1
        let generation = operationalStatusGeneration

        statusQueue.async {
            let result = Result { () -> (StorageHealthSnapshot, LogRepository.HealthSummary) in
                let snapshot = try storageMaintenanceService.healthSnapshot()
                let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
                return (snapshot, try logRepository.fetchHealthSummary(since: cutoff))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.operationalStatusGeneration == generation else { return }
                switch result {
                case .success(let (snapshot, summary)):
                    self.storageHealthSnapshot = snapshot
                    self.executionHealthSummary = summary
                case .failure(let error):
                    PPLogger.database.error("Failed to refresh operational status: \(error.localizedDescription)")
                    self.bannerMessage = "加载运行健康信息失败。"
                }
            }
        }
    }

    func refreshUpdaterStatus() {
        updaterStatusMessage = updaterService.statusMessage
        canCheckForUpdates = updaterService.canCheckForUpdates
    }

    func cleanupLogs(olderThanDays days: Int = 30) {
        runMaintenance("正在清理执行日志…") { [logRepository] in
            try logRepository.cleanup(olderThanDays: days)
        } onSuccess: { [weak self] in
            self?.refreshLogs()
            self?.refreshOperationalStatus()
            self?.bannerMessage = "已清理 \(days) 天前的执行日志。"
        } onFailure: { error in
            PPLogger.execute.error("Failed to clean execution logs: \(error.localizedDescription)")
            return "清理执行日志失败，请重试。"
        }
    }

    func projectName(for id: String) -> String {
        projectNamesById[id] ?? "未知项目"
    }

    func requestAccessibilityPermission() {
        permissionService.requestPermission()
        refreshPermissionState()
        bannerMessage = permissionService.isAccessibilityGranted
            ? "辅助功能权限已启用。"
            : "权限尚未完成，请在系统设置中开启 PromptPanel.app；若列表里同时出现 PromptPanel，请以 PromptPanel.app 为准。"
    }

    func openAccessibilitySettings() {
        permissionService.openAccessibilitySettings()
    }

    func resetAccessibilityApproval() {
        let outcome = permissionService.resetAccessibilityApproval()
        refreshPermissionState()
        switch outcome {
        case .success:
            bannerMessage = "已清空旧授权记录，请在系统设置里重新开启 PromptPanel.app。"
        case .missingBundleIdentifier:
            bannerMessage = "无法读取应用 Bundle ID，重置失败。"
        case .launchFailed(let reason):
            bannerMessage = "重置授权记录失败：\(reason)"
        case .toolFailed(let exitCode, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                bannerMessage = "tccutil 退出码 \(exitCode)，重置失败。"
            } else {
                bannerMessage = "tccutil 退出码 \(exitCode)：\(detail)"
            }
        }
    }

    /// Registering a login item talks to the service management daemon, which can
    /// stall for a noticeable fraction of a second. The switch flips optimistically
    /// and is reconciled against the real state once the daemon answers.
    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
        let loginItemService = self.loginItemService
        statusQueue.async {
            var failure: Error?
            do {
                if enabled {
                    try loginItemService.enable()
                } else {
                    try loginItemService.disable()
                }
            } catch {
                failure = error
            }
            let actual = loginItemService.isEnabled

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.launchAtLoginEnabled = actual
                if let failure {
                    PPLogger.loginItem.error("Failed to update login item state: \(failure.localizedDescription)")
                    self.bannerMessage = enabled ? "启用登录时启动失败，请重试。" : "关闭登录时启动失败，请重试。"
                } else if actual == enabled {
                    self.bannerMessage = enabled ? "已启用登录时启动。" : "已关闭登录时启动。"
                } else {
                    self.bannerMessage = enabled ? "系统尚未启用登录时启动，请检查系统设置。" : "系统尚未关闭登录时启动，请检查系统设置。"
                }
            }
        }
    }

    func createBackupNow() {
        runMaintenance("正在创建备份…") { [storageMaintenanceService] in
            try storageMaintenanceService.createManualBackup()
        } onSuccess: { [weak self] backupURL in
            self?.refreshOperationalStatus()
            self?.bannerMessage = "已创建备份：\(backupURL.lastPathComponent)"
        } onFailure: { error in
            PPLogger.database.error("Failed to create manual backup: \(error.localizedDescription)")
            return "创建备份失败，请稍后重试。"
        }
    }

    func exportLibraryAsJSON() {
        presentSavePanel(
            title: "导出词库 JSON",
            fileName: "PromptPanel-Library-\(Self.fileTimestamp()).json",
            contentTypes: [.json]
        ) { [weak self] destinationURL in
            guard let self else { return }
            self.runMaintenance("正在导出词库 JSON…") { [libraryTransferService = self.libraryTransferService] in
                try libraryTransferService.exportJSON(to: destinationURL)
            } onSuccess: { [weak self] outputURL in
                self?.bannerMessage = "词库 JSON 已保存：\(outputURL.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } onFailure: { error in
                PPLogger.app.error("Failed to export library JSON: \(error.localizedDescription)")
                return "导出词库 JSON 失败：\(error.localizedDescription)"
            }
        }
    }

    func exportLibraryAsMarkdown() {
        presentSavePanel(
            title: "导出词库 Markdown",
            fileName: "PromptPanel-Library-\(Self.fileTimestamp()).md",
            contentTypes: [Self.markdownContentType]
        ) { [weak self] destinationURL in
            guard let self else { return }
            self.runMaintenance("正在导出词库 Markdown…") { [libraryTransferService = self.libraryTransferService] in
                try libraryTransferService.exportMarkdown(to: destinationURL)
            } onSuccess: { [weak self] outputURL in
                self?.bannerMessage = "词库 Markdown 已保存：\(outputURL.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            } onFailure: { error in
                PPLogger.app.error("Failed to export library Markdown: \(error.localizedDescription)")
                return "导出词库 Markdown 失败：\(error.localizedDescription)"
            }
        }
    }

    func importLibraryFromJSON() {
        presentOpenPanel(title: "导入词库 JSON", contentTypes: [.json]) { [weak self] sourceURL in
            guard let self else { return }
            self.importLibrary(label: "正在导入词库 JSON…") { [libraryTransferService = self.libraryTransferService] in
                try libraryTransferService.importJSON(from: sourceURL)
            }
        }
    }

    func importLibraryFromMarkdown() {
        presentOpenPanel(
            title: "导入词库 Markdown",
            contentTypes: [Self.markdownContentType, .plainText]
        ) { [weak self] sourceURL in
            guard let self else { return }
            self.importLibrary(label: "正在导入词库 Markdown…") { [libraryTransferService = self.libraryTransferService] in
                try libraryTransferService.importMarkdown(from: sourceURL)
            }
        }
    }

    /// Lets the user assemble and save a diagnostics zip (privacy-safe — no entry content).
    /// Shows an NSSavePanel sheet for the destination; on success reveals the resulting zip
    /// in Finder. The bundle itself (unified-log read + `ditto`) is built off the main thread:
    /// `OSLogStore.getEntries` alone routinely takes seconds.
    func exportDiagnosticsBundle() {
        presentSavePanel(
            title: "导出诊断包",
            fileName: "PromptPanel-Diagnostics-\(Self.fileTimestamp()).zip",
            contentTypes: [.zip]
        ) { [weak self] destinationURL in
            guard let self else { return }
            // Built here, on the main actor, because it snapshots permission state.
            let service = DiagnosticsExportService(
                logRepository: self.logRepository,
                storageMaintenanceService: self.storageMaintenanceService,
                permissionService: self.permissionService
            )
            self.runMaintenance("正在生成诊断包…") {
                try service.exportBundle(to: destinationURL)
            } onSuccess: { [weak self] zipURL in
                self?.bannerMessage = "诊断包已保存：\(zipURL.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([zipURL])
            } onFailure: { error in
                PPLogger.app.error("Failed to export diagnostics bundle: \(error.localizedDescription)")
                return error.localizedDescription
            }
        }
    }

    private func importLibrary(
        label: String,
        _ action: @escaping @Sendable () throws -> LibraryTransferSummary
    ) {
        runMaintenance(label, work: action) { [weak self] summary in
            guard let self else { return }
            // Broadcast rather than refreshing only ourselves. An import can create
            // projects and entries, and the quick panel keeps its own copies of both;
            // refreshing in place left its project menu showing the pre-import list
            // until something else happened to post one of these.
            self.notifyProjectsChanged()
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            self.refreshOperationalStatus()
            let backupName = summary.backupURL?.lastPathComponent ?? "未生成备份"
            self.bannerMessage = "导入完成：项目 +\(summary.projectsCreated)/更新 \(summary.projectsUpdated)，词条 +\(summary.entriesCreated)/更新 \(summary.entriesUpdated)。导入前备份：\(backupName)"
        } onFailure: { error in
            PPLogger.app.error("Failed to import library: \(error.localizedDescription)")
            return "导入词库失败：\(error.localizedDescription)"
        }
    }

    // MARK: - Off-main maintenance plumbing

    /// Run `work` on `maintenanceQueue` and deliver the outcome on the main actor.
    ///
    /// Every one of these operations used to run inline on the main actor: a full
    /// SQLite backup, a whole-library JSON encode, a `ditto` subprocess. The window
    /// stopped drawing and stopped accepting clicks for the duration, which read as
    /// "the export hung" even though it always finished.
    private func runMaintenance<T: Sendable>(
        _ label: String,
        work: @escaping @Sendable () throws -> T,
        onSuccess: @escaping (T) -> Void,
        onFailure: @escaping (Error) -> String
    ) {
        guard activeMaintenanceTask == nil else {
            bannerMessage = "请等待“\(activeMaintenanceTask ?? "当前操作")”结束后再试。"
            return
        }

        activeMaintenanceTask = label
        bannerMessage = label
        maintenanceQueue.async {
            let result = Result { try work() }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.activeMaintenanceTask = nil
                switch result {
                case .success(let value):
                    onSuccess(value)
                case .failure(let error):
                    self.bannerMessage = onFailure(error)
                }
            }
        }
    }

    private func presentSavePanel(
        title: String,
        fileName: String,
        contentTypes: [UTType],
        completion: @escaping (URL) -> Void
    ) {
        let savePanel = NSSavePanel()
        savePanel.title = title
        savePanel.nameFieldStringValue = fileName
        savePanel.allowedContentTypes = contentTypes
        savePanel.canCreateDirectories = true
        beginPanel(savePanel) { completion($0) }
    }

    private func presentOpenPanel(
        title: String,
        contentTypes: [UTType],
        completion: @escaping (URL) -> Void
    ) {
        let openPanel = NSOpenPanel()
        openPanel.title = title
        openPanel.allowedContentTypes = contentTypes
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        beginPanel(openPanel) { completion($0) }
    }

    /// Present as a sheet on the main window when there is one, so the rest of the
    /// app keeps running; fall back to a standalone panel otherwise.
    private func beginPanel(_ panel: NSSavePanel, completion: @escaping (URL) -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                completion(url)
            }
        }

        // A sheet needs a window that is actually on screen; attaching one to a
        // hidden window would present nothing at all.
        if let window = hostWindowProvider(), window.isVisible {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    private static func fileTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
    }

    private static var markdownContentType: UTType {
        UTType(filenameExtension: "md") ?? .plainText
    }

    func openDataDirectory() {
        storageMaintenanceService.openDatabaseDirectory()
    }

    func openBackupDirectory() {
        storageMaintenanceService.openBackupDirectory()
    }

    func checkForUpdates() {
        bannerMessage = updaterService.checkForUpdates()
        refreshUpdaterStatus()
    }

    func setCurrentProjectToSelected() {
        guard let project = selectedProject else {
            bannerMessage = "请先选择一个具体项目。"
            return
        }
        persistCurrentProject(project.id)
        bannerMessage = "当前项目已切换为 \(project.name)。"
    }

    func startCreateProject() {
        projectDraft = ProjectDraft(existingProject: nil)
    }

    func startRenameSelectedProject() {
        guard let project = selectedProject else {
            bannerMessage = "请先选择要重命名的项目。"
            return
        }
        projectDraft = ProjectDraft(existingProject: project)
    }

    func saveProjectDraft() -> Bool {
        guard var draft = projectDraft else {
            return false
        }

        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.name.isEmpty else {
            bannerMessage = "项目名称不能为空。"
            return false
        }

        do {
            if let existingProject = draft.existingProject {
                try projectRepository.rename(id: existingProject.id, newName: draft.name)
                bannerMessage = "项目已重命名。"
            } else {
                let project = Project(name: draft.name)
                try projectRepository.create(project)
                selectedProjectId = project.id
                bannerMessage = "项目已创建。"
            }

            projectDraft = nil
            notifyProjectsChanged()
            return true
        } catch {
            PPLogger.project.error("Failed to save project draft: \(error.localizedDescription)")
            bannerMessage = "保存项目失败，请重试。"
            return false
        }
    }

    func requestDeleteSelectedProject() {
        guard let project = selectedProject else {
            bannerMessage = "请先选择要删除的项目。"
            return
        }
        guard !project.isDefault else {
            bannerMessage = "通用项目不能删除。"
            return
        }

        do {
            let entryCount = try projectRepository.entryCount(forProjectId: project.id)
            if entryCount == 0 {
                try projectRepository.delete(id: project.id)
                handleProjectDeletionFallback(deletedProjectId: project.id, replacementProjectId: appState.defaultProjectId)
                notifyProjectsChanged()
                bannerMessage = "项目已删除。"
            } else if let targetProjectId = projects.first(where: { $0.id != project.id })?.id {
                deleteProjectState = ProjectDeletionState(
                    project: project,
                    entryCount: entryCount,
                    targetProjectId: targetProjectId
                )
            }
        } catch {
            PPLogger.project.error("Failed to request project deletion: \(error.localizedDescription)")
            bannerMessage = "删除项目失败，请重试。"
        }
    }

    func confirmDeleteProject() -> Bool {
        guard let state = deleteProjectState else {
            return false
        }

        do {
            try projectRepository.migrateAndDelete(fromId: state.project.id, toId: state.targetProjectId)
            handleProjectDeletionFallback(deletedProjectId: state.project.id, replacementProjectId: state.targetProjectId)
            deleteProjectState = nil
            notifyProjectsChanged()
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            bannerMessage = "项目已删除，词条已迁移。"
            return true
        } catch {
            PPLogger.project.error("Failed to migrate and delete project: \(error.localizedDescription)")
            bannerMessage = "项目迁移删除失败，请重试。"
            return false
        }
    }

    func startCreateEntry() {
        let defaultProjectId = selectedProjectId == Self.allProjectsSelection ? currentProjectId : selectedProjectId
        entryDraft = EntryDraft(existingEntry: nil, defaultProjectId: defaultProjectId)
    }

    func startEditEntry(_ entry: Entry) {
        entryDraft = EntryDraft(existingEntry: entry, defaultProjectId: entry.projectId)
    }

    func saveEntryDraft() -> Bool {
        guard let draft = entryDraft else {
            return false
        }

        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else {
            bannerMessage = "词条标题和内容都不能为空。"
            return false
        }

        do {
            let parsedTags = draft.parsedTags
            if let existingEntry = draft.existingEntry {
                let updated = Entry(
                    id: existingEntry.id,
                    projectId: draft.projectId,
                    title: trimmedTitle,
                    content: draft.content,
                    type: draft.type,
                    isPinned: draft.isPinned,
                    sortOrder: draft.sortOrder,
                    useCount: existingEntry.useCount,
                    lastUsedAt: existingEntry.lastUsedAt,
                    createdAt: existingEntry.createdAt,
                    updatedAt: Date(),
                    tags: parsedTags
                )
                try entryRepository.update(updated)
                bannerMessage = "词条已更新。"
            } else {
                let entry = Entry(
                    projectId: draft.projectId,
                    title: trimmedTitle,
                    content: draft.content,
                    type: draft.type,
                    isPinned: draft.isPinned,
                    sortOrder: draft.sortOrder,
                    tags: parsedTags
                )
                try entryRepository.create(entry)
                bannerMessage = "词条已创建。"
            }

            entryDraft = nil
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            return true
        } catch {
            PPLogger.entry.error("Failed to save entry draft: \(error.localizedDescription)")
            bannerMessage = "保存词条失败，请重试。"
            return false
        }
    }

    func requestDeleteEntry(_ entry: Entry) {
        entryPendingDeletion = entry
    }

    func confirmDeleteEntry() {
        guard let entry = entryPendingDeletion else {
            return
        }

        do {
            try entryRepository.delete(id: entry.id)
            entryPendingDeletion = nil
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            bannerMessage = "词条已删除。"
        } catch {
            PPLogger.entry.error("Failed to delete entry: \(error.localizedDescription)")
            bannerMessage = "删除词条失败，请重试。"
        }
    }

    private func observeChanges() {
        appState.$isPanelPinned
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPinned in
                self?.isPanelPinned = isPinned
            }
            .store(in: &cancellables)

        appState.$panelShowFooter
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.panelShowFooter = value
            }
            .store(in: &cancellables)

        appState.$panelCompactRows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.panelCompactRows = value
            }
            .store(in: &cancellables)

        appState.$panelContentSize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.panelContentSize = value
            }
            .store(in: &cancellables)

        appState.$appTheme
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.appTheme = value
            }
            .store(in: &cancellables)

        appState.$currentProjectId
            .combineLatest(appState.$defaultProjectId)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.syncCurrentProjectId()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .projectsDidChange)
            .sink { [weak self] _ in
                self?.loadProjects()
                self?.scheduleEntriesRefresh(delayMs: 0)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .entriesDidChange)
            .sink { [weak self] _ in
                self?.scheduleEntriesRefresh(delayMs: 0)
                self?.refreshProjectEntryCounts()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .executionLogsDidChange)
            .sink { [weak self] _ in
                self?.refreshLogs()
                self?.refreshOperationalStatus()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .currentProjectDidChange)
            .sink { [weak self] _ in
                self?.syncCurrentProjectId()
                self?.scheduleEntriesRefresh(delayMs: 0)
            }
            .store(in: &cancellables)
    }

    private func syncCurrentProjectId() {
        currentProjectId = appState.effectiveProjectId
    }

    private func notifyProjectsChanged() {
        NotificationCenter.default.post(name: .projectsDidChange, object: nil)
    }

    private func loadProjects() {
        do {
            projects = try projectRepository.fetchAll()
            projectNamesById = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
            if selectedProjectId == Self.allProjectsSelection {
                return
            }
            if !projects.contains(where: { $0.id == selectedProjectId }) {
                selectedProjectId = appState.effectiveProjectId.isEmpty ? Self.allProjectsSelection : appState.effectiveProjectId
            }
        } catch {
            PPLogger.project.error("Failed to load projects: \(error.localizedDescription)")
            projects = []
            projectNamesById = [:]
            selectedProjectId = Self.allProjectsSelection
            bannerMessage = "加载项目列表失败。"
        }
    }

    private func scheduleEntriesRefresh(delayMs: Int) {
        pendingEntriesRefreshWorkItem?.cancel()

        let selectedProjectId = self.selectedProjectId
        let entrySearchText = self.entrySearchText
        let projectIds = projects.map(\.id)
        let allProjectsSelection = Self.allProjectsSelection
        let entryRepository = self.entryRepository
        let entriesLoadQueue = self.entriesLoadQueue

        entriesRefreshGeneration += 1
        let generation = entriesRefreshGeneration

        let workItem = DispatchWorkItem { [weak self] in
            guard self != nil else {
                return
            }

            entriesLoadQueue.async {
                let result: Result<[Entry], Error>
                do {
                    let entries: [Entry]
                    if selectedProjectId == allProjectsSelection {
                        if entrySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            entries = try entryRepository.fetchAll()
                        } else {
                            entries = try entryRepository.search(
                                query: entrySearchText,
                                projectIds: projectIds
                            )
                        }
                    } else if entrySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        entries = try entryRepository.fetchByProject(selectedProjectId)
                    } else {
                        entries = try entryRepository.search(
                            query: entrySearchText,
                            projectIds: [selectedProjectId]
                        )
                    }
                    result = .success(entries)
                } catch {
                    result = .failure(error)
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self, self.entriesRefreshGeneration == generation else {
                        return
                    }

                    switch result {
                    case .success(let entries):
                        self.entries = entries
                        self.refreshEntryFacets()
                        self.refreshDisplayedEntries()
                    case .failure(let error):
                        PPLogger.entry.error("Failed to load entries: \(error.localizedDescription)")
                        self.entries = []
                        self.refreshEntryFacets()
                        self.displayedEntries = []
                        self.selectedEntryId = nil
                        self.bannerMessage = "加载词条失败。"
                    }
                }
            }
        }

        pendingEntriesRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(delayMs, 0)), execute: workItem)
    }

    private func persistCurrentProject(_ projectId: String?) {
        guard let projectId else {
            return
        }

        do {
            try settingsRepository.setCurrentProjectId(projectId)
            appState.currentProjectId = projectId
            NotificationCenter.default.post(name: .currentProjectDidChange, object: nil)
        } catch {
            PPLogger.project.error("Failed to persist current project: \(error.localizedDescription)")
            bannerMessage = "切换当前项目失败，请重试。"
        }
    }

    private func handleProjectDeletionFallback(deletedProjectId: String, replacementProjectId: String?) {
        if selectedProjectId == deletedProjectId {
            selectedProjectId = replacementProjectId ?? Self.allProjectsSelection
        }

        if appState.currentProjectId == deletedProjectId || appState.effectiveProjectId == deletedProjectId {
            persistCurrentProject(replacementProjectId ?? appState.defaultProjectId)
        }
    }
}
