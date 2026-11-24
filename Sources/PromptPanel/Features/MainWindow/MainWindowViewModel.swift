import AppKit
import Combine
import Foundation
import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class InlineEditorSession: ObservableObject {
    @Published var entryId: String = ""
    @Published var title: String = "" {
        didSet {
            guard title != oldValue else { return }
            onFieldMutation?()
        }
    }
    @Published var content: String = "" {
        didSet {
            guard content != oldValue else { return }
            onFieldMutation?()
        }
    }
    @Published var projectId: String = "" {
        didSet {
            guard projectId != oldValue else { return }
            onFieldMutation?()
        }
    }
    @Published var type: String = Constants.EntryType.prompt.rawValue {
        didSet {
            guard type != oldValue else { return }
            onFieldMutation?()
        }
    }
    @Published var isPinned: Bool = false {
        didSet {
            guard isPinned != oldValue else { return }
            onFieldMutation?()
        }
    }
    @Published var isCompleted: Bool = false {
        didSet {
            guard isCompleted != oldValue else { return }
            onFieldMutation?()
        }
    }
    @Published var tagsText: String = "" {
        didSet {
            guard tagsText != oldValue else { return }
            onFieldMutation?()
        }
    }
    @Published var saveState: MainWindowViewModel.InlineAutoSaveState = .idle

    fileprivate var onFieldMutation: (() -> Void)?
}

@MainActor
final class MainWindowViewModel: ObservableObject {
    nonisolated static let allProjectsSelection = "__all_projects__"

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
        var groupKind: Project.GroupKind

        init(existingProject: Project?, defaultKind: Project.GroupKind = .project) {
            self.id = existingProject?.id ?? UUID().uuidString
            self.existingProject = existingProject
            self.name = existingProject?.name ?? ""
            self.groupKind = existingProject?.groupKind ?? defaultKind
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

    enum InlineAutoSaveState: Equatable {
        case idle
        case pending
        case saving
        case saved
        case invalid
    }

    static let inlineAutoSaveDebounceMs: Int = 900
    static let inlineVersionSnapshotInterval: TimeInterval = 180

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

        init(
            existingEntry: Entry?,
            defaultProjectId: String,
            defaultType: String = Constants.EntryType.prompt.rawValue
        ) {
            self.id = existingEntry?.id ?? UUID().uuidString
            self.existingEntry = existingEntry
            self.title = existingEntry?.title ?? ""
            self.content = existingEntry?.content ?? ""
            self.projectId = existingEntry?.projectId ?? defaultProjectId
            self.type = existingEntry?.type ?? defaultType
            self.isPinned = existingEntry?.isPinned ?? false
            self.sortOrder = existingEntry?.sortOrder ?? 0
            self.tagsText = (existingEntry?.tags ?? []).joined(separator: ", ")
        }

        var parsedTags: [String] {
            Entry.normalizeTags(
                tagsText
                    .components(separatedBy: CharacterSet(charactersIn: ",，、"))
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            )
        }
    }

    @Published private(set) var projects: [Project] = [] {
        didSet {
            rebuildProjectPartitions()
        }
    }
    private(set) var cachedInboxProject: Project?
    private(set) var cachedCategoryProjects: [Project] = []
    private(set) var cachedActiveProjects: [Project] = []
    private(set) var cachedArchivedProjects: [Project] = []
    private(set) var nonArchivedProjects: [Project] = []
    private(set) var cachedActiveTargetProjects: [Project] = []
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var displayedEntries: [Entry] = []
    @Published private(set) var recentExecutionLogs: [ExecutionLog] = []
    @Published private(set) var storageHealthSnapshot: StorageHealthSnapshot?
    @Published private(set) var executionHealthSummary: LogRepository.HealthSummary?
    @Published private(set) var updaterStatusMessage: String = "自动更新未初始化。"
    @Published private(set) var canCheckForUpdates: Bool = false
    @Published var autoUpdateEnabled: Bool = false
    @Published private(set) var updaterActionTitle: String = "检查更新"
    @Published private(set) var hasPendingAppUpdate: Bool = false
    @Published private(set) var currentProjectId: String = ""
    private var isRevertingSelectedTab = false
    @Published var selectedTab: Tab = .library {
        didSet {
            guard !isRevertingSelectedTab, selectedTab != oldValue else { return }
            if oldValue == .library, !commitPendingInlineChangesIfNeeded() {
                isRevertingSelectedTab = true
                selectedTab = oldValue
                isRevertingSelectedTab = false
            }
        }
    }
    @Published var selectedSettingsArea: SettingsArea = .preferences
    private var isRevertingSelectedProjectId = false
    @Published var selectedProjectId: String = MainWindowViewModel.allProjectsSelection {
        didSet {
            guard !isRevertingSelectedProjectId else { return }
            if selectedProjectId != oldValue {
                if !commitPendingInlineChangesIfNeeded() {
                    isRevertingSelectedProjectId = true
                    selectedProjectId = oldValue
                    isRevertingSelectedProjectId = false
                    return
                }
                quickCapturePreferInbox = false
            }
            scheduleEntriesRefresh(delayMs: 0, pruneStaleFilters: selectedProjectId != oldValue)
        }
    }
    @Published var entrySearchText: String = "" {
        didSet {
            guard oldValue != entrySearchText else { return }
            scheduleEntriesRefresh(delayMs: Constants.mainWindowSearchDebounceMs, pruneStaleFilters: true)
        }
    }
    @Published var quickCaptureText: String = ""
    @Published var quickCapturePreferInbox: Bool = false
    @Published var quickCaptureAsTodo: Bool = false
    @Published var hideCompletedEntries: Bool = false {
        didSet {
            guard oldValue != hideCompletedEntries else { return }
            refreshDisplayedEntriesUnlessBatching()
        }
    }
    @Published private(set) var completedEntryCount: Int = 0
    private var isRevertingSelectedEntryId = false
    @Published var selectedEntryId: String? {
        didSet {
            if selectedEntryId != oldValue {
                if isRevertingSelectedEntryId {
                    return
                }
                pendingInlineAutoSaveWorkItem?.cancel()
                pendingInlineAutoSaveWorkItem = nil
                let previousEntryId: String?
                if !inlineDraftEntryId.isEmpty, inlineDraftEntryId != selectedEntryId {
                    previousEntryId = inlineDraftEntryId
                } else {
                    previousEntryId = oldValue
                }
                if let previousEntryId,
                   !commitPendingInlineChangesIfNeeded(forEntryId: previousEntryId) {
                    isRevertingSelectedEntryId = true
                    selectedEntryId = previousEntryId
                    isRevertingSelectedEntryId = false
                    return
                }
                refreshSelectedEntryVersions()
                if let entry = selectedEntry {
                    syncInlineDraft(with: entry, force: true)
                }
            }
        }
    }
    @Published private(set) var selectedEntryVersions: [EntryVersion] = []
    @Published var isArchivedSectionExpanded: Bool = false
    @Published var isShowingVersionPopover: Bool = false
    @Published private(set) var programmaticScrollRevision: Int = 0
    private(set) var programmaticScrollAnchor: UnitPoint? = nil

    let inlineSession = InlineEditorSession()

    var inlineDraftEntryId: String {
        get { inlineSession.entryId }
        set { inlineSession.entryId = newValue }
    }
    var inlineDraftTitle: String {
        get { inlineSession.title }
        set { inlineSession.title = newValue }
    }
    var inlineDraftContent: String {
        get { inlineSession.content }
        set { inlineSession.content = newValue }
    }
    var inlineDraftProjectId: String {
        get { inlineSession.projectId }
        set { inlineSession.projectId = newValue }
    }
    var inlineDraftType: String {
        get { inlineSession.type }
        set { inlineSession.type = newValue }
    }
    var inlineDraftIsPinned: Bool {
        get { inlineSession.isPinned }
        set { inlineSession.isPinned = newValue }
    }
    var inlineDraftIsCompleted: Bool {
        get { inlineSession.isCompleted }
        set { inlineSession.isCompleted = newValue }
    }
    var inlineDraftTagsText: String {
        get { inlineSession.tagsText }
        set { inlineSession.tagsText = newValue }
    }
    var inlineAutoSaveState: InlineAutoSaveState {
        get { inlineSession.saveState }
        set { inlineSession.saveState = newValue }
    }

    var inlineTitle: String {
        get { inlineSession.title }
        set { inlineSession.title = newValue }
    }
    var inlineContent: String {
        get { inlineSession.content }
        set { inlineSession.content = newValue }
    }
    var inlineTagsText: String {
        get { inlineSession.tagsText }
        set { inlineSession.tagsText = newValue }
    }

    private var pendingInlineAutoSaveWorkItem: DispatchWorkItem?
    private var isSyncingInlineDraftProgrammatically = false
    private var inlineSessionVersionedEntryId: String?
    private var lastInlineVersionSnapshotAtByEntryId: [String: Date] = [:]
    static let maxInlineVersionSnapshotCacheCount = 200
    private var suppressSelfEntriesReloadCount: Int = 0
    @Published var isContextDropdownOpen: Bool = false
    @Published var referenceTargetProjectId: String = ""
    @Published var referenceSourceProjectId: String = MainWindowViewModel.allProjectsSelection
    @Published var referenceSearchText: String = ""
    @Published private(set) var referenceEntries: [Entry] = []
    @Published var clipboardPreviewText: String = ""
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
    @Published var cloudSyncEnabled: Bool = false
    @Published var cloudSyncEndpoint: String = "" {
        didSet {
            guard !isHydratingCloudSyncState, oldValue != cloudSyncEndpoint else { return }
            isSyncAuthPaused = false
            lastSyncErrorMessage = nil
            recomputeSyncBadgeState()
            scheduleCloudSyncSettingsAutoPersist()
        }
    }
    @Published var cloudSyncApiKey: String = "" {
        didSet {
            guard !isHydratingCloudSyncState, oldValue != cloudSyncApiKey else { return }
            isSyncAuthPaused = false
            lastSyncErrorMessage = nil
            recomputeSyncBadgeState()
            scheduleCloudSyncSettingsAutoPersist()
        }
    }
    @Published var isShowingMobilePairingQR: Bool = false
    @Published private(set) var cloudSyncLastStatus: String = "尚未执行云端同步"
    @Published private(set) var cloudSyncConnectionStatus: String = "未检测"
    @Published private(set) var cloudSyncConnectionHealthy: Bool? = nil
    @Published private(set) var syncBadgeState: SyncBadgeState = .unconfigured
    @Published private(set) var lastSyncReport: CloudSyncReport? = nil
    @Published private(set) var hasPendingLocalChanges: Bool = false
    @Published private(set) var pendingLocalDelta: Int = 0
    @Published private(set) var cloudRemoteRevision: Int? = nil
    @Published private(set) var recentSoftDeletedEntries: [SoftDeletedEntryItem] = []
    @Published private(set) var isSyncAuthPaused: Bool = false
    @Published private(set) var isCloudSyncSecretAccessDenied: Bool = false
    @Published private(set) var lastSyncErrorMessage: String? = nil
    var onSyncBadgeStateChanged: ((SyncBadgeState) -> Void)?
    private var pendingAutoCloudSyncWorkItem: DispatchWorkItem?
    private var pendingCloudSyncSettingsPersistWorkItem: DispatchWorkItem?
    private var autoCloudSyncPollTimer: DispatchSourceTimer?
    private var activeCloudSyncTask: Task<Void, Never>?
    private var activeConnectionTestTask: Task<Void, Never>?
    private var lastOpportunisticCloudSyncAt: Date = .distantPast
    private var isHydratingCloudSyncState = false
    private var isApplyingCloudSyncChanges = false
    private var isCloudSyncInFlight = false {
        didSet {
            if oldValue != isCloudSyncInFlight {
                recomputeSyncBadgeState()
            }
        }
    }
    private let appState: AppState
    private let projectRepository: ProjectRepository
    private let entryRepository: EntryRepository
    private let settingsRepository: SettingsRepository
    private let logRepository: LogRepository
    private let permissionService: PermissionService
    private let loginItemService: LoginItemService
    private let storageMaintenanceService: StorageMaintenanceService
    private let libraryTransferService: LibraryTransferService
    private let cloudSyncService: CloudSyncService?
    private let updaterService: UpdaterService
    private let launchRecoveryReport: LaunchRecoveryReport?
    private let onSetPanelPinned: (Bool) -> Bool
    private let onSetPanelContentSize: (NSSize) -> Bool
    private let onCopyEntry: ((Entry) -> Bool)?
    var onOpenReferenceWindow: (() -> Void)?
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
    private var pendingReferenceSearchWorkItem: DispatchWorkItem?
    private var pendingVersionRefreshWorkItem: DispatchWorkItem?
    private var entriesRefreshGeneration: Int = 0
    private var referenceRefreshGeneration: Int = 0
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
        cloudSyncService: CloudSyncService? = nil,
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
        self.cloudSyncService = cloudSyncService
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
        self.inlineSession.onFieldMutation = { [weak self] in
            self?.handleInlineDraftFieldMutation()
        }
        self.autoUpdateEnabled = (try? settingsRepository.isAutoUpdateEnabled()) ?? false
        refreshUpdaterStatus()
        refreshCloudSyncState()
        updateAutoCloudSyncPollTimer()

        observeChanges()
        if cloudSyncEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.triggerOpportunisticCloudSyncIfNeeded(force: true)
            }
        }
    }

    deinit {
        pendingEntriesRefreshWorkItem?.cancel()
        pendingReferenceSearchWorkItem?.cancel()
        pendingVersionRefreshWorkItem?.cancel()
        pendingInlineAutoSaveWorkItem?.cancel()
        pendingAutoCloudSyncWorkItem?.cancel()
        pendingCloudSyncSettingsPersistWorkItem?.cancel()
        autoCloudSyncPollTimer?.cancel()
        activeCloudSyncTask?.cancel()
        activeConnectionTestTask?.cancel()
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

    private func rebuildProjectPartitions() {
        var inbox: Project?
        var categories: [Project] = []
        var active: [Project] = []
        var archived: [Project] = []
        var nonArchived: [Project] = []

        for project in projects {
            if project.groupKind == .inbox, inbox == nil {
                inbox = project
            }
            if project.isArchived {
                archived.append(project)
            } else {
                nonArchived.append(project)
                switch project.groupKind {
                case .category:
                    categories.append(project)
                case .project:
                    active.append(project)
                case .inbox:
                    break
                }
            }
        }

        cachedInboxProject = inbox
        cachedCategoryProjects = categories
        cachedActiveProjects = active
        cachedArchivedProjects = archived
        nonArchivedProjects = nonArchived
    }

    var selectedProject: Project? {
        projects.first(where: { $0.id == selectedProjectId })
    }

    var projectOptions: [Project] {
        projects
    }

    var inboxProject: Project? {
        cachedInboxProject
    }

    var categoryProjects: [Project] {
        cachedCategoryProjects
    }

    var activeProjects: [Project] {
        cachedActiveProjects
    }

    var archivedProjects: [Project] {
        cachedArchivedProjects
    }

    func targetProjects(excluding projectId: String) -> [Project] {
        let base = cachedActiveTargetProjects.isEmpty ? nonArchivedProjects : cachedActiveTargetProjects
        return base.filter { $0.id != projectId }
    }

    /// Ordered non-archived projects for the top-left context switcher & scroll cycling.
    var switchableProjects: [Project] {
        var ordered: [Project] = []
        var seen = Set<String>()
        if let inbox = inboxProject, !inbox.isArchived, seen.insert(inbox.id).inserted {
            ordered.append(inbox)
        }
        for category in categoryProjects where seen.insert(category.id).inserted {
            ordered.append(category)
        }
        for project in activeProjects where seen.insert(project.id).inserted {
            ordered.append(project)
        }
        for project in nonArchivedProjects where seen.insert(project.id).inserted {
            ordered.append(project)
        }
        return ordered
    }

    var quickCaptureTargetProjectId: String {
        let resolvedInboxId = inboxProject?.id
            ?? (projects.isEmpty ? (try? projectRepository.fetchById(Constants.inboxProjectId))?.id : nil)
            ?? (currentProjectId.isEmpty ? appState.effectiveProjectId : currentProjectId)
        if quickCapturePreferInbox || selectedProjectId == Self.allProjectsSelection {
            return resolvedInboxId
        }
        if let selected = selectedProject ?? (projects.isEmpty ? (try? projectRepository.fetchById(selectedProjectId)) : nil) {
            if selected.isArchived {
                return resolvedInboxId
            }
            return selected.id
        }
        return resolvedInboxId
    }

    var quickCaptureDestinationName: String {
        let targetId = quickCaptureTargetProjectId
        if let known = projectNamesById[targetId] {
            return known
        }
        if targetId == Constants.inboxProjectId {
            return Constants.inboxProjectName
        }
        if projects.isEmpty, let fetched = try? projectRepository.fetchById(targetId) {
            return fetched.name
        }
        return Constants.inboxProjectName
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
        var completedCount = 0

        for entry in entries {
            if entry.isCompleted {
                completedCount += 1
            }
            let type = Constants.EntryType.resolve(entry.type)
            if seenKinds.insert(type.rawValue).inserted {
                kinds.append(type)
            }
            kindCounts[entry.type, default: 0] += 1
            for tag in entry.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        if completedEntryCount != completedCount {
            completedEntryCount = completedCount
        }
        if availableEntryKinds != kinds {
            availableEntryKinds = kinds
        }
        if entryKindCounts != kindCounts {
            entryKindCounts = kindCounts
        }
        let nextTopTags = tagCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
            }
            .prefix(Self.topTagFacetLimit)
            .map { EntryTagFacet(tag: $0.key, count: $0.value) }
        if topTags != nextTopTags {
            topTags = nextTopTags
        }
    }

    func entryCount(forKind kind: Constants.EntryType) -> Int {
        entryKindCounts[kind.rawValue] ?? 0
    }

    func projectName(forEntry entry: Entry) -> String? {
        projectNamesById[entry.projectId]
    }

    private func sortedVisibleEntries() -> [Entry] {
        let filtered: [Entry] = entries.filter { entry in
            if hideCompletedEntries && entry.isCompleted {
                return false
            }
            if let kind = entryKindFilter, entry.type != kind {
                return false
            }
            if let tag = entryTagFilter,
               !entry.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                return false
            }
            return true
        }
        return filtered.sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
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
        if let entry = selectedEntry {
            let isSameEntry = inlineDraftEntryId == entry.id
            let hasLiveTyping = isSameEntry && (
                hasUnsavedInlineChanges(for: entry)
                || inlineAutoSaveState == .pending
                || inlineAutoSaveState == .saving
                || inlineAutoSaveState == .invalid
            )
            syncInlineDraft(with: entry, force: !hasLiveTyping, preserveSavedState: isSameEntry)
        }
        refreshSelectedEntryVersions()
        refreshReferenceEntries()
    }

    private static func parseNormalizedInlineTags(from raw: String) -> [String] {
        Entry.normalizeTags(
            raw
                .components(separatedBy: CharacterSet(charactersIn: ",，、"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    func requestProgrammaticScroll(anchor: UnitPoint? = nil) {
        programmaticScrollAnchor = anchor
        programmaticScrollRevision &+= 1
    }

    func syncInlineDraft(with entry: Entry, force: Bool = false, preserveSavedState: Bool = false) {
        guard force || inlineSession.entryId != entry.id else { return }
        let isSwitchingEntry = inlineSession.entryId != entry.id
        if isSwitchingEntry {
            pendingInlineAutoSaveWorkItem?.cancel()
            pendingInlineAutoSaveWorkItem = nil
            if inlineSessionVersionedEntryId != entry.id {
                inlineSessionVersionedEntryId = nil
            }
        }
        isSyncingInlineDraftProgrammatically = true
        defer { isSyncingInlineDraftProgrammatically = false }
        let trimmedDraftTitle = inlineSession.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldKeepLiveTitle = preserveSavedState
            && !isSwitchingEntry
            && !trimmedDraftTitle.isEmpty
            && trimmedDraftTitle == entry.title
        let currentParsedTags = Self.parseNormalizedInlineTags(from: inlineSession.tagsText)
        let shouldKeepLiveTagsText = preserveSavedState
            && !isSwitchingEntry
            && currentParsedTags == entry.tags

        if inlineSession.entryId != entry.id {
            inlineSession.entryId = entry.id
        }
        if !shouldKeepLiveTitle, inlineSession.title != entry.title {
            inlineSession.title = entry.title
        }
        if inlineSession.content != entry.content {
            inlineSession.content = entry.content
        }
        if inlineSession.projectId != entry.projectId {
            inlineSession.projectId = entry.projectId
        }
        if inlineSession.type != entry.type {
            inlineSession.type = entry.type
        }
        if inlineSession.isPinned != entry.isPinned {
            inlineSession.isPinned = entry.isPinned
        }
        if inlineSession.isCompleted != entry.isCompleted {
            inlineSession.isCompleted = entry.isCompleted
        }
        let joinedTags = entry.tags.joined(separator: ", ")
        if !shouldKeepLiveTagsText, inlineSession.tagsText != joinedTags {
            inlineSession.tagsText = joinedTags
        }
        if (isSwitchingEntry || !preserveSavedState), inlineSession.saveState != .idle {
            inlineSession.saveState = .idle
        }
    }

    func handleInlineFieldEdit() {
        handleInlineDraftFieldMutation()
    }

    func flushPendingInlineChangesIfNeeded(forEntryId targetId: String? = nil) {
        commitPendingInlineChangesIfNeeded(forEntryId: targetId)
    }

    private func handleInlineDraftFieldMutation() {
        guard !isSyncingInlineDraftProgrammatically else { return }
        scheduleInlineAutoSaveIfNeeded()
    }

    private func scheduleInlineAutoSaveIfNeeded() {
        pendingInlineAutoSaveWorkItem?.cancel()
        pendingInlineAutoSaveWorkItem = nil

        guard !inlineDraftEntryId.isEmpty,
              let entry = entries.first(where: { $0.id == inlineDraftEntryId })
                  ?? (try? entryRepository.fetchById(inlineDraftEntryId)) else {
            inlineAutoSaveState = .idle
            return
        }

        guard hasUnsavedInlineChanges(for: entry) else {
            if inlineAutoSaveState != .saved {
                inlineAutoSaveState = .idle
            }
            return
        }

        let trimmedContent = inlineDraftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            inlineAutoSaveState = .invalid
            return
        }

        inlineAutoSaveState = .pending
        let targetEntryId = entry.id
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.performDebouncedInlineAutoSave(forEntryId: targetEntryId)
        }
        pendingInlineAutoSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(Self.inlineAutoSaveDebounceMs),
            execute: workItem
        )
    }

    private func performDebouncedInlineAutoSave(forEntryId targetEntryId: String) {
        pendingInlineAutoSaveWorkItem = nil
        guard inlineDraftEntryId == targetEntryId,
              let entry = entries.first(where: { $0.id == targetEntryId })
                  ?? (try? entryRepository.fetchById(targetEntryId)),
              hasUnsavedInlineChanges(for: entry) else {
            return
        }
        let trimmedContent = inlineDraftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            inlineAutoSaveState = .invalid
            return
        }
        let trimmedTitle = inlineDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = trimmedTitle.isEmpty
            ? Self.deriveEntryTitle(from: inlineDraftContent, fallback: entry.title)
            : trimmedTitle
        if trimmedTitle.isEmpty {
            isSyncingInlineDraftProgrammatically = true
            inlineDraftTitle = effectiveTitle
            isSyncingInlineDraftProgrammatically = false
        }
        inlineAutoSaveState = .saving
        _ = saveInlineEntry(
            entry,
            title: effectiveTitle,
            content: inlineDraftContent,
            projectId: inlineDraftProjectId,
            type: inlineDraftType,
            isPinned: inlineDraftIsPinned,
            isCompleted: inlineDraftIsCompleted,
            tagsText: inlineDraftTagsText,
            changeNote: "自动保存",
            isAutoSave: true
        )
    }

    func hasUnsavedInlineChanges(for entry: Entry) -> Bool {
        guard inlineDraftEntryId == entry.id else { return false }
        let titleChanged = inlineDraftTitle != entry.title
            && inlineDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                != entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedTags = Self.parseNormalizedInlineTags(from: inlineDraftTagsText)
        return titleChanged
            || inlineDraftContent != entry.content
            || inlineDraftProjectId != entry.projectId
            || inlineDraftType != entry.type
            || inlineDraftIsPinned != entry.isPinned
            || inlineDraftIsCompleted != entry.isCompleted
            || parsedTags != entry.tags
    }

    private func flushAndResolveLatestEntry(_ entry: Entry) -> Entry {
        if inlineDraftEntryId == entry.id {
            commitPendingInlineChangesIfNeeded(forEntryId: entry.id)
        }
        return (try? entryRepository.fetchById(entry.id))
            ?? entries.first(where: { $0.id == entry.id })
            ?? entry
    }

    func hasUnsavedInlineContentChanges(for entry: Entry) -> Bool {
        guard inlineDraftEntryId == entry.id else { return false }
        let titleChanged = inlineDraftTitle != entry.title
            && inlineDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                != entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return titleChanged || inlineDraftContent != entry.content
    }

    @discardableResult
    func commitInlineChanges(for entry: Entry) -> Bool {
        pendingInlineAutoSaveWorkItem?.cancel()
        pendingInlineAutoSaveWorkItem = nil
        let trimmedTitle = inlineDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = trimmedTitle.isEmpty
            ? Self.deriveEntryTitle(from: inlineDraftContent, fallback: entry.title)
            : trimmedTitle
        return saveInlineEntry(
            entry,
            title: effectiveTitle,
            content: inlineDraftContent,
            projectId: inlineDraftProjectId,
            type: inlineDraftType,
            isPinned: inlineDraftIsPinned,
            isCompleted: inlineDraftIsCompleted,
            tagsText: inlineDraftTagsText,
            changeNote: "内联编辑保存"
        )
    }

    /// Commits valid unsaved inline draft changes for the specified (or currently active) entry
    /// so switching selection or closing the window never silently discards user edits.
    /// Returns `false` if dirty non-blank edits could not be saved and selection should remain.
    @discardableResult
    func commitPendingInlineChangesIfNeeded(forEntryId targetId: String? = nil) -> Bool {
        let entryId = targetId ?? inlineDraftEntryId
        if targetId == nil || targetId == inlineDraftEntryId {
            pendingInlineAutoSaveWorkItem?.cancel()
            pendingInlineAutoSaveWorkItem = nil
        }
        guard !entryId.isEmpty,
              inlineDraftEntryId == entryId,
              let entry = entries.first(where: { $0.id == entryId })
                  ?? (try? entryRepository.fetchById(entryId)),
              hasUnsavedInlineChanges(for: entry) else {
            return true
        }
        let trimmedContent = inlineDraftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            // Only auto-discard if the persisted entry itself was a brand-new blank draft.
            if entry.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            inlineAutoSaveState = .invalid
            bannerMessage = "内容不能为空，已保留当前未保存编辑，请补充内容后再切换词条。"
            return false
        }
        let trimmedTitle = inlineDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = trimmedTitle.isEmpty
            ? Self.deriveEntryTitle(from: inlineDraftContent, fallback: entry.title)
            : trimmedTitle
        let saved = saveInlineEntry(
            entry,
            title: effectiveTitle,
            content: inlineDraftContent,
            projectId: inlineDraftProjectId,
            type: inlineDraftType,
            isPinned: inlineDraftIsPinned,
            isCompleted: inlineDraftIsCompleted,
            tagsText: inlineDraftTagsText,
            changeNote: "自动保存",
            isAutoSave: true
        )
        if !saved {
            bannerMessage = "保存修改失败，已保留当前未保存编辑，请重试。"
        }
        return saved
    }

    func refreshReferenceEntries(immediate: Bool = false) {
        pendingReferenceSearchWorkItem?.cancel()
        pendingReferenceSearchWorkItem = nil

        referenceRefreshGeneration += 1
        let generation = referenceRefreshGeneration
        let sourceId = referenceSourceProjectId
        let query = referenceSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let entryRepository = self.entryRepository
        let categoryIds = Set(categoryProjects.map(\.id))
        let runLoad: @Sendable () -> Void = { [weak self] in
            self?.entriesLoadQueue.async { [weak self] in
                let allEntries: [Entry]
                if sourceId == Self.allProjectsSelection {
                    allEntries = (try? entryRepository.fetchAll(excludeArchivedProjects: true)) ?? []
                } else {
                    allEntries = (try? entryRepository.fetchByProject(sourceId)) ?? []
                }
                var filtered = allEntries.filter { entry in
                    guard !query.isEmpty else { return true }
                    return entry.title.localizedCaseInsensitiveContains(query)
                        || entry.content.localizedCaseInsensitiveContains(query)
                        || entry.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                }
                if sourceId == Self.allProjectsSelection && query.isEmpty && !categoryIds.isEmpty {
                    let categoryMatches = filtered.filter { categoryIds.contains($0.projectId) }
                    let otherMatches = filtered.filter { !categoryIds.contains($0.projectId) }
                    filtered = categoryMatches + otherMatches
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.referenceRefreshGeneration == generation else { return }
                    if self.referenceEntries != filtered {
                        self.referenceEntries = filtered
                    }
                }
            }
        }

        if immediate {
            runLoad()
        } else {
            let workItem = DispatchWorkItem(block: runLoad)
            pendingReferenceSearchWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: workItem)
        }
    }

    func refreshClipboardPreview() {
        clipboardPreviewText = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func refreshSelectedEntryVersions(immediate: Bool = false) {
        pendingVersionRefreshWorkItem?.cancel()
        pendingVersionRefreshWorkItem = nil

        guard let entryId = selectedEntry?.id else {
            if !selectedEntryVersions.isEmpty {
                selectedEntryVersions = []
            }
            return
        }
        let entryRepository = self.entryRepository
        let runLoad: @Sendable () -> Void = { [weak self] in
            self?.entriesLoadQueue.async { [weak self] in
                let versions = (try? entryRepository.fetchVersions(forEntryId: entryId)) ?? []
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.selectedEntry?.id == entryId else { return }
                    if self.selectedEntryVersions != versions {
                        self.selectedEntryVersions = versions
                    }
                }
            }
        }

        if immediate {
            runLoad()
        } else {
            let workItem = DispatchWorkItem(block: runLoad)
            pendingVersionRefreshWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(80), execute: workItem)
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
        entriesLoadQueue.async { [weak self] in
            guard let allCounts = try? entryRepository.entryCountByProject(excludeArchivedProjects: false),
                  let activeCounts = try? entryRepository.entryCountByProject(excludeArchivedProjects: true) else {
                PPLogger.entry.error("Failed to load project entry counts")
                return
            }
            let totalActive = activeCounts.values.reduce(0, +)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.projectEntryCounts != allCounts {
                    self.projectEntryCounts = allCounts
                }
                if self.totalEntryCount != totalActive {
                    self.totalEntryCount = totalActive
                }
            }
        }
    }

    func toggleEntryKindFilter(_ type: Constants.EntryType) {
        if entryKindFilter == type.rawValue {
            updateEntryFilters(kind: nil, tag: entryTagFilter)
        } else {
            updateEntryFilters(kind: type.rawValue, tag: entryTagFilter)
        }
    }

    func toggleEntryTagFilter(_ tag: String) {
        if entryTagFilter == tag {
            updateEntryFilters(kind: entryKindFilter, tag: nil)
        } else {
            updateEntryFilters(kind: entryKindFilter, tag: tag)
        }
    }

    func clearEntryFilters() {
        updateEntryFilters(kind: nil, tag: nil)
    }

    // MARK: - Main window shortcuts

    enum MainWindowKeyCommand: Equatable {
        case focusSearch
        case copySelectedEntry
        case editSelectedEntry
        case createNewEntry
        case saveInlineDraft
        case openReferenceWindow
        case openSettings
        case moveSelectionUp
        case moveSelectionDown
    }

    private static let upArrowKeyCode: UInt16 = 126
    private static let downArrowKeyCode: UInt16 = 125
    private static let commandShiftActionByKeyCode: [UInt16: MainWindowKeyCommand] = [
        8: .copySelectedEntry,   // Cmd+Shift+C
        45: .openReferenceWindow // Cmd+Shift+N
    ]
    private static let commandActionByKeyCode: [UInt16: MainWindowKeyCommand] = [
        3: .focusSearch,         // Cmd+F
        14: .editSelectedEntry,  // Cmd+E
        45: .createNewEntry,     // Cmd+N
        1: .saveInlineDraft,     // Cmd+S
        43: .openSettings        // Cmd+,
    ]

    static func mainWindowKeyCommand(
        keyCode: UInt16 = .max,
        modifierFlags: NSEvent.ModifierFlags,
        charactersIgnoringModifiers: String?
    ) -> MainWindowKeyCommand? {
        let flags = modifierFlags.intersection([.command, .shift, .option, .control])

        if flags.isEmpty {
            switch keyCode {
            case upArrowKeyCode:
                return .moveSelectionUp
            case downArrowKeyCode:
                return .moveSelectionDown
            default:
                return nil
            }
        }

        if flags == [.command, .shift] {
            if keyCode != .max, let command = commandShiftActionByKeyCode[keyCode] {
                return command
            }
            switch charactersIgnoringModifiers?.lowercased() {
            case "c": return .copySelectedEntry
            case "n": return .openReferenceWindow
            default: return nil
            }
        }

        guard flags == [.command] else {
            return nil
        }

        if keyCode != .max, let command = commandActionByKeyCode[keyCode] {
            return command
        }

        switch charactersIgnoringModifiers?.lowercased() {
        case "f": return .focusSearch
        case "e": return .editSelectedEntry
        case "n": return .createNewEntry
        case "s": return .saveInlineDraft
        case ",": return .openSettings
        default: return nil
        }
    }

    /// Arrow keys should navigate the entry list unless the user is actively
    /// composing IME text (marked text), manipulating a text selection, or
    /// navigating inside a multi-line text view.
    static func shouldAllowArrowKeyNavigation(firstResponder: NSResponder?) -> Bool {
        guard let textView = firstResponder as? NSTextView else {
            return true
        }
        if textView.hasMarkedText() {
            return false
        }
        if textView.selectedRange().length > 0 {
            return false
        }
        if !textView.isFieldEditor && (textView.string.contains("\n") || textView.enclosingScrollView != nil) {
            return false
        }
        return true
    }

    @discardableResult
    func handleMainWindowKeyCommand(_ command: MainWindowKeyCommand) -> Bool {
        guard !isContextDropdownOpen, !isShowingVersionPopover else {
            return false
        }
        if command == .openSettings {
            if selectedTab == .library, !commitPendingInlineChangesIfNeeded() {
                return true
            }
            selectedTab = .settings
            return true
        }
        guard selectedTab == .library else {
            return false
        }
        guard projectDraft == nil,
              entryDraft == nil,
              deleteProjectState == nil,
              entryPendingDeletion == nil else {
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
        case .createNewEntry:
            startCreateEntry()
        case .saveInlineDraft:
            guard let entry = selectedEntry else {
                return false
            }
            if hasUnsavedInlineChanges(for: entry) {
                _ = commitInlineChanges(for: entry)
            }
            return true
        case .openReferenceWindow:
            openReferenceWindow()
        case .openSettings:
            selectedTab = .settings
        case .moveSelectionUp:
            return moveSelectedEntry(offset: -1)
        case .moveSelectionDown:
            return moveSelectedEntry(offset: 1)
        }
        return true
    }

    @discardableResult
    func moveSelection(delta: Int) -> Bool {
        moveSelectedEntry(offset: delta)
    }

    private func moveSelectedEntry(offset: Int) -> Bool {
        guard !displayedEntries.isEmpty else {
            return false
        }
        guard let currentId = selectedEntry?.id,
              let currentIndex = displayedEntries.firstIndex(where: { $0.id == currentId }) else {
            selectedEntryId = displayedEntries.first?.id
            requestProgrammaticScroll(anchor: nil)
            return true
        }
        let nextIndex = min(max(currentIndex + offset, 0), displayedEntries.count - 1)
        selectedEntryId = displayedEntries[nextIndex].id
        requestProgrammaticScroll(anchor: nil)
        return true
    }

    func copyEntryContent(_ entry: Entry) {
        var effectiveEntry = entry
        if inlineDraftEntryId == entry.id,
           hasUnsavedInlineChanges(for: entry),
           !inlineDraftContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let draftTitle = inlineDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !draftTitle.isEmpty {
                effectiveEntry.title = draftTitle
            }
            effectiveEntry.content = inlineDraftContent
        }
        if let onCopyEntry, onCopyEntry(effectiveEntry) {
            bannerMessage = "已复制到剪贴板：\(effectiveEntry.title)"
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(effectiveEntry.content, forType: .string) {
            do {
                try entryRepository.recordExecution(id: entry.id)
                NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            } catch {
                PPLogger.entry.error("Failed to record usage on library copy: \(error.localizedDescription)")
            }
            bannerMessage = "已复制到剪贴板：\(effectiveEntry.title)"
        } else {
            bannerMessage = "复制到剪贴板失败，请重试。"
        }
    }

    func togglePin(_ entry: Entry) {
        var updated = flushAndResolveLatestEntry(entry)
        updated.isPinned.toggle()
        updated.updatedAt = Date()
        do {
            try entryRepository.update(updated, recordVersion: false)
            if inlineDraftEntryId == updated.id {
                isSyncingInlineDraftProgrammatically = true
                inlineDraftIsPinned = updated.isPinned
                isSyncingInlineDraftProgrammatically = false
            }
            if let idx = entries.firstIndex(where: { $0.id == updated.id }) {
                entries[idx] = updated
                refreshEntryFacets()
                refreshDisplayedEntries()
            }
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
        triggerOpportunisticCloudSyncIfNeeded(minIntervalSeconds: 18)
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
        statusQueue.async { [weak self] in
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
        statusQueue.async { [weak self] in
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

    func refreshOperationalStatus() {
        let storageMaintenanceService = self.storageMaintenanceService
        let logRepository = self.logRepository
        operationalStatusGeneration += 1
        let generation = operationalStatusGeneration

        statusQueue.async { [weak self] in
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
        updaterActionTitle = updaterService.actionButtonTitle
        hasPendingAppUpdate = updaterService.hasPendingUpdate
    }

    func setAutoUpdateEnabled(_ enabled: Bool) {
        autoUpdateEnabled = enabled
        do {
            try settingsRepository.setAutoUpdateEnabled(enabled)
            updaterService.autoUpdateEnabled = enabled
            refreshUpdaterStatus()
            bannerMessage = enabled ? "已开启自动检查与后台静默更新。" : "已关闭自动更新，仍可随时点击一键更新。"
        } catch {
            PPLogger.updater.error("Failed to persist auto update preference: \(error.localizedDescription)")
            bannerMessage = "保存自动更新设置失败，请重试。"
        }
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
        Task { @MainActor [weak self] in
            guard let self else { return }
            let outcome = await self.permissionService.resetAccessibilityApproval()
            self.refreshPermissionState()
            switch outcome {
            case .success:
                self.bannerMessage = "已清空旧授权记录，请在系统设置里重新开启 PromptPanel.app。"
            case .missingBundleIdentifier:
                self.bannerMessage = "无法读取应用 Bundle ID，重置失败。"
            case .launchFailed(let reason):
                self.bannerMessage = "重置授权记录失败：\(reason)"
            case .toolFailed(let exitCode, let output):
                let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.isEmpty {
                    self.bannerMessage = "tccutil 退出码 \(exitCode)，重置失败。"
                } else {
                    self.bannerMessage = "tccutil 退出码 \(exitCode)：\(detail)"
                }
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginEnabled = enabled
        let loginItemService = self.loginItemService
        statusQueue.async { [weak self] in
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

    func exportDiagnosticsBundle() {
        presentSavePanel(
            title: "导出诊断包",
            fileName: "PromptPanel-Diagnostics-\(Self.fileTimestamp()).zip",
            contentTypes: [.zip]
        ) { [weak self] destinationURL in
            guard let self else { return }
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

    // MARK: - Cloud Sync Actions

    func refreshCloudSyncState() {
        isHydratingCloudSyncState = true
        defer { isHydratingCloudSyncState = false }
        cloudSyncEnabled = (try? settingsRepository.isCloudSyncEnabled()) ?? false
        cloudSyncEndpoint = (try? settingsRepository.getCloudSyncEndpoint()) ?? ""
        let apiKeyStatus = (try? settingsRepository.getCloudSyncApiKeyStatus()) ?? .missing
        switch apiKeyStatus {
        case .loaded(let secret):
            cloudSyncApiKey = secret
            isCloudSyncSecretAccessDenied = false
        case .missing:
            cloudSyncApiKey = ""
            isCloudSyncSecretAccessDenied = false
        case .accessDenied:
            cloudSyncApiKey = ""
            isCloudSyncSecretAccessDenied = true
            isSyncAuthPaused = true
            cloudSyncConnectionHealthy = false
            lastSyncErrorMessage = "应用升级后系统钥匙串拒绝自动读取旧 Token，请重新粘贴访问令牌并保存"
            cloudSyncConnectionStatus = "凭据需重新确认"
        }
        if let status = try? cloudSyncService?.lastSyncStatus(), !status.isEmpty {
            cloudSyncLastStatus = status
        }
        if let report = try? cloudSyncService?.lastSyncReport() {
            lastSyncReport = report
        }
        if let pending = try? cloudSyncService?.pendingSyncState() {
            hasPendingLocalChanges = pending.hasPendingLocalChanges
            pendingLocalDelta = pending.pendingDelta
            cloudRemoteRevision = pending.lastSyncedRevision ?? lastSyncReport?.remoteRevision
        } else {
            cloudRemoteRevision = lastSyncReport?.remoteRevision
        }
        if cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cloudSyncConnectionStatus = "未配置同步地址"
            cloudSyncConnectionHealthy = nil
            isSyncAuthPaused = false
            lastSyncErrorMessage = nil
        } else if !isCloudSyncSecretAccessDenied, let endpointError = cloudSyncEndpointValidationError {
            cloudSyncConnectionHealthy = false
            lastSyncErrorMessage = endpointError
            cloudSyncConnectionStatus = "同步地址不受安全策略允许"
        }
        recomputeSyncBadgeState()
    }

    /// Immediate client-side validation for configured remote sync URLs so users never suffer
    /// silent multi-day sync stalls on disallowed cleartext `http://` remote endpoints.
    var cloudSyncEndpointValidationError: String? {
        let trimmed = cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else {
            return nil
        }
        guard let url = URL(string: trimmed) else {
            return "无效的同步地址：\(trimmed)"
        }
        guard CloudSyncService.isAllowedRemoteHTTPURL(url) else {
            return "为保护同步数据与 Token 安全，远程同步仅允许 https:// 地址（仅本机回环允许 http://localhost 或 http://127.0.0.1）"
        }
        return nil
    }

    private func recomputeSyncBadgeState() {
        let trimmedEndpoint = cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextState: SyncBadgeState
        if trimmedEndpoint.isEmpty {
            nextState = .unconfigured
        } else if isCloudSyncInFlight {
            nextState = .syncing
        } else if isCloudSyncSecretAccessDenied {
            nextState = .error(lastSyncErrorMessage ?? "系统钥匙串拒绝读取旧 Token，请重新保存访问令牌")
        } else if let endpointError = cloudSyncEndpointValidationError {
            nextState = .error(endpointError)
        } else if isSyncAuthPaused {
            nextState = .error(lastSyncErrorMessage ?? "Token 鉴权失败，请检查同步凭据")
        } else if cloudSyncConnectionHealthy == false, let errorMsg = lastSyncErrorMessage {
            nextState = .error(errorMsg)
        } else if cloudSyncEnabled {
            if hasPendingLocalChanges {
                nextState = .autoPending(pendingCount: pendingLocalDelta > 0 ? pendingLocalDelta : nil)
            } else {
                nextState = .autoSynced(revision: cloudRemoteRevision)
            }
        } else {
            nextState = .manualIdle(revision: cloudRemoteRevision, hasPending: hasPendingLocalChanges)
        }
        if syncBadgeState != nextState {
            syncBadgeState = nextState
            onSyncBadgeStateChanged?(nextState)
        }
    }

    private static func isAuthenticationError(_ error: Error) -> Bool {
        let message = error.localizedDescription
        return message.contains("HTTP 401")
            || message.contains("HTTP 403")
            || message.contains("401")
            || message.contains("403")
            || message.contains("鉴权未通过")
            || message.contains("访问被拒绝")
    }

    private func scheduleCloudSyncSettingsAutoPersist() {
        pendingCloudSyncSettingsPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.saveCloudSyncSettings(showBanner: false)
            if self.cloudSyncEnabled {
                self.triggerOpportunisticCloudSyncIfNeeded(force: true)
            }
        }
        pendingCloudSyncSettingsPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: workItem)
    }

    func setCloudSyncEnabled(_ isEnabled: Bool) {
        cloudSyncEnabled = isEnabled
        if isEnabled, !isCloudSyncSecretAccessDenied {
            isSyncAuthPaused = false
            lastSyncErrorMessage = nil
        }
        saveCloudSyncSettings(showBanner: true)
        updateAutoCloudSyncPollTimer()
        recomputeSyncBadgeState()
        if isEnabled, !isCloudSyncSecretAccessDenied {
            triggerOpportunisticCloudSyncIfNeeded(force: true)
        }
    }

    func saveCloudSyncSettings(showBanner: Bool = true) {
        pendingCloudSyncSettingsPersistWorkItem?.cancel()
        pendingCloudSyncSettingsPersistWorkItem = nil
        let trimmedApiKey = cloudSyncApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try settingsRepository.setCloudSyncEnabled(cloudSyncEnabled)
            try settingsRepository.setCloudSyncEndpoint(cloudSyncEndpoint)
            // Never wipe a Keychain-locked legacy credential when the user saves unrelated
            // settings (e.g. toggling auto-sync or editing the URL) while the field appears blank.
            if !(isCloudSyncSecretAccessDenied && trimmedApiKey.isEmpty) {
                try settingsRepository.setCloudSyncApiKey(trimmedApiKey)
                if !trimmedApiKey.isEmpty {
                    isCloudSyncSecretAccessDenied = false
                    isSyncAuthPaused = false
                }
            }
            if !isCloudSyncSecretAccessDenied {
                if let endpointError = cloudSyncEndpointValidationError {
                    cloudSyncConnectionHealthy = false
                    lastSyncErrorMessage = endpointError
                    cloudSyncConnectionStatus = "同步地址不受安全策略允许"
                } else if lastSyncErrorMessage != nil && cloudSyncConnectionStatus == "同步地址不受安全策略允许" {
                    cloudSyncConnectionHealthy = nil
                    lastSyncErrorMessage = nil
                    cloudSyncConnectionStatus = "未检测"
                }
            }
            updateAutoCloudSyncPollTimer()
            recomputeSyncBadgeState()
            if showBanner {
                bannerMessage = "云端同步配置已保存。"
            }
        } catch {
            PPLogger.app.error("Failed to save cloud sync settings: \(error.localizedDescription)")
            if showBanner {
                bannerMessage = "保存云端同步配置失败，请重试。"
            }
        }
    }

    var mobileSyncEndpointWarning: String? {
        let trimmed = cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        if !(lower.hasPrefix("http://") || lower.hasPrefix("https://")) {
            return "当前同步地址是 Mac 本地文件路径，手机无法直接访问。请部署并填入 https:// 同步服务地址后再配对手机。"
        }
        if lower.contains("://127.0.0.1") || lower.contains("://localhost") || lower.contains("://0.0.0.0") || lower.contains("://[::1]") {
            return "当前地址指向本机回环 (localhost / 127.0.0.1)，手机扫码后无法直连；请改填已配置 TLS 的 https:// 域名地址。"
        }
        if lower.hasPrefix("http://") {
            return "非本机同步禁止明文 http:// 传输；请为同步服务配置反向代理或有效证书并改用 https:// 地址。"
        }
        return nil
    }

    func makeMobileSyncBundleJSON(pretty: Bool = false) -> String? {
        let trimmedEndpoint = cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            return nil
        }
        let payload: [String: Any] = [
            "endpoint": trimmedEndpoint,
            "apiKey": cloudSyncApiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            "autoSync": true
        ]
        var options: JSONSerialization.WritingOptions = [.sortedKeys]
        if pretty {
            options.insert(.prettyPrinted)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: options),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    func openMobilePairingQRSheet() {
        let trimmedEndpoint = cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty else {
            bannerMessage = "请先填写同步地址后再打开手机扫码配对。"
            return
        }
        saveCloudSyncSettings(showBanner: false)
        isShowingMobilePairingQR = true
    }

    func generateNewCloudSyncToken() {
        let randomPart = (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(28)
        let token = "pp_live_\(randomPart)"
        cloudSyncApiKey = token
        saveCloudSyncSettings(showBanner: false)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
        bannerMessage = "已生成 Token 并复制到剪贴板。"
    }

    func copyMobileSyncBundleToClipboard() {
        saveCloudSyncSettings(showBanner: false)
        guard let text = makeMobileSyncBundleJSON(pretty: true) else {
            bannerMessage = "请先填写同步地址后再复制手机端配置。"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        bannerMessage = "已复制手机配对配置，可在手机端「设置 → 粘贴剪贴板配置」一键生效。"
    }

    func copyOpenSourceDeployCommand() {
        let command = "cd server && sudo PP_SYNC_PORT=18787 ./deploy-systemd.sh"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        bannerMessage = "已复制部署命令：\(command)"
    }

    func testCloudSyncConnection() {
        guard let cloudSyncService else {
            bannerMessage = "云端同步服务未初始化。"
            return
        }
        let trimmedApiKey = cloudSyncApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCloudSyncSecretAccessDenied && trimmedApiKey.isEmpty {
            let msg = "应用升级后系统钥匙串拒绝自动读取旧 Token，请重新粘贴访问令牌并保存后再测试连接。"
            cloudSyncConnectionHealthy = false
            lastSyncErrorMessage = msg
            cloudSyncConnectionStatus = "凭据需重新确认"
            bannerMessage = msg
            recomputeSyncBadgeState()
            return
        }
        isSyncAuthPaused = false
        lastSyncErrorMessage = nil
        saveCloudSyncSettings()
        let endpoint = cloudSyncEndpoint
        let apiKey = cloudSyncApiKey
        cloudSyncConnectionStatus = "正在检测连接…"
        activeConnectionTestTask?.cancel()
        activeConnectionTestTask = Task { @MainActor [weak self] in
            do {
                let report = try await cloudSyncService.testConnection(endpoint: endpoint, apiKey: apiKey)
                guard let self, !Task.isCancelled else { return }
                let ok = report.isReachable && report.authenticated
                self.cloudSyncConnectionHealthy = ok
                self.cloudSyncConnectionStatus = report.summaryText
                if ok {
                    self.isSyncAuthPaused = false
                    self.lastSyncErrorMessage = nil
                    self.updateAutoCloudSyncPollTimer()
                } else if !report.authenticated {
                    self.isSyncAuthPaused = true
                    self.lastSyncErrorMessage = report.summaryText
                    self.updateAutoCloudSyncPollTimer()
                }
                self.recomputeSyncBadgeState()
                self.bannerMessage = report.summaryText
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.cloudSyncConnectionHealthy = false
                self.lastSyncErrorMessage = error.localizedDescription
                if Self.isAuthenticationError(error) {
                    self.isSyncAuthPaused = true
                    self.updateAutoCloudSyncPollTimer()
                }
                self.recomputeSyncBadgeState()
                self.cloudSyncConnectionStatus = "连接异常：\(error.localizedDescription)"
                self.bannerMessage = "测试连接失败：\(error.localizedDescription)"
            }
        }
    }

    func chooseCloudSyncFileLocation() {
        presentSavePanel(
            title: "选择云端网盘 / iCloud 同步文件路径",
            fileName: "PromptPanel-CloudSync.json",
            contentTypes: [.json]
        ) { [weak self] url in
            guard let self else { return }
            self.cloudSyncEndpoint = url.path
            self.cloudSyncEnabled = true
            self.saveCloudSyncSettings()
        }
    }

    func syncCloudNow(mode: CloudSyncActionMode = .smartBidirectional) {
        guard let cloudSyncService else {
            bannerMessage = "云端同步服务未初始化。"
            return
        }
        guard !isCloudSyncInFlight else {
            bannerMessage = "云端同步正在进行中，请稍候。"
            return
        }
        guard activeMaintenanceTask == nil else {
            bannerMessage = "请等待“\(activeMaintenanceTask ?? "当前操作")”结束后再试。"
            return
        }
        pendingAutoCloudSyncWorkItem?.cancel()
        pendingAutoCloudSyncWorkItem = nil
        let trimmedApiKey = cloudSyncApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if isCloudSyncSecretAccessDenied && trimmedApiKey.isEmpty {
            let msg = "应用升级后系统钥匙串拒绝自动读取旧 Token，请重新粘贴访问令牌并保存后再执行同步。"
            cloudSyncConnectionHealthy = false
            isSyncAuthPaused = true
            lastSyncErrorMessage = msg
            cloudSyncConnectionStatus = "凭据需重新确认"
            bannerMessage = msg
            recomputeSyncBadgeState()
            return
        }
        isSyncAuthPaused = false
        lastSyncErrorMessage = nil
        saveCloudSyncSettings(showBanner: false)
        let endpoint = cloudSyncEndpoint
        let apiKey = cloudSyncApiKey
        let label: String = {
            switch mode {
            case .smartBidirectional: return "正在执行云端双向同步…"
            case .pullOnly: return "正在拉取云端更新并合并…"
            case .forcePushLocal: return "正在强制推送本机快照覆盖云端…"
            }
        }()
        isCloudSyncInFlight = true
        activeMaintenanceTask = label
        bannerMessage = label
        activeCloudSyncTask = Task { @MainActor [weak self] in
            defer {
                self?.isCloudSyncInFlight = false
                self?.activeMaintenanceTask = nil
                self?.activeCloudSyncTask = nil
            }
            do {
                let report = try await cloudSyncService.syncWithReport(
                    endpoint: endpoint,
                    apiKey: apiKey,
                    actionMode: mode,
                    forceFullSync: true,
                    isAutoSync: false
                )
                guard let self, !Task.isCancelled else { return }
                self.isApplyingCloudSyncChanges = true
                defer { self.isApplyingCloudSyncChanges = false }
                self.cloudSyncConnectionHealthy = true
                self.isSyncAuthPaused = false
                self.lastSyncErrorMessage = nil
                self.lastSyncReport = report
                self.refreshCloudSyncState()
                self.updateAutoCloudSyncPollTimer()
                self.refreshOperationalStatus()
                self.notifyProjectsChanged()
                NotificationCenter.default.post(name: .entriesDidChange, object: nil)
                self.refreshSelectedEntryVersions()
                self.refreshRecentSoftDeletedEntries()
                self.bannerMessage = report.summaryText
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.cloudSyncConnectionHealthy = false
                self.lastSyncErrorMessage = error.localizedDescription
                if Self.isAuthenticationError(error) {
                    self.isSyncAuthPaused = true
                    self.updateAutoCloudSyncPollTimer()
                }
                self.recomputeSyncBadgeState()
                self.bannerMessage = error.localizedDescription
            }
        }
    }

    func pullCloudOnly() {
        syncCloudNow(mode: .pullOnly)
    }

    func forcePushLocalToCloud() {
        syncCloudNow(mode: .forcePushLocal)
    }

    func refreshRecentSoftDeletedEntries() {
        guard let cloudSyncService else {
            if !recentSoftDeletedEntries.isEmpty {
                recentSoftDeletedEntries = []
            }
            return
        }
        entriesLoadQueue.async { [weak self] in
            let items = (try? cloudSyncService.fetchRecentSoftDeletedEntries(withinDays: 30)) ?? []
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.recentSoftDeletedEntries != items {
                    self.recentSoftDeletedEntries = items
                }
            }
        }
    }

    func restoreSoftDeletedEntries(ids: [String]) {
        let uniqueIds = Array(Set(ids))
        guard !uniqueIds.isEmpty, let cloudSyncService else { return }
        do {
            let restored = try cloudSyncService.restoreSoftDeletedEntries(ids: uniqueIds)
            if restored > 0 {
                notifyProjectsChanged()
                NotificationCenter.default.post(name: .entriesDidChange, object: nil)
                refreshProjectEntryCounts()
                refreshCloudSyncState()
                refreshRecentSoftDeletedEntries()
                scheduleAutoCloudSyncIfNeeded()
                bannerMessage = "已从回收站恢复 \(restored) 条词条。"
            } else {
                bannerMessage = "未找到可恢复的词条。"
            }
        } catch {
            PPLogger.entry.error("Failed to restore soft-deleted entries: \(error.localizedDescription)")
            bannerMessage = "恢复词条失败：\(error.localizedDescription)"
        }
    }

    func recoverDeletedAndPushToCloud() {
        guard let cloudSyncService else {
            bannerMessage = "云端同步服务未初始化。"
            return
        }
        guard !isCloudSyncInFlight else {
            bannerMessage = "云端同步正在进行中，请稍候。"
            return
        }
        guard activeMaintenanceTask == nil else {
            bannerMessage = "请等待“\(activeMaintenanceTask ?? "当前操作")”结束后再试。"
            return
        }
        pendingAutoCloudSyncWorkItem?.cancel()
        pendingAutoCloudSyncWorkItem = nil
        saveCloudSyncSettings()
        let endpoint = cloudSyncEndpoint
        let apiKey = cloudSyncApiKey
        let label = "正在恢复本地误删记录并回填云端…"
        isCloudSyncInFlight = true
        activeMaintenanceTask = label
        bannerMessage = label
        activeCloudSyncTask = Task { @MainActor [weak self] in
            defer {
                self?.isCloudSyncInFlight = false
                self?.activeMaintenanceTask = nil
                self?.activeCloudSyncTask = nil
            }
            do {
                let result = try await cloudSyncService.recoverDeletedAndSync(endpoint: endpoint, apiKey: apiKey)
                guard let self, !Task.isCancelled else { return }
                self.isApplyingCloudSyncChanges = true
                defer { self.isApplyingCloudSyncChanges = false }
                if result.syncSummary != nil {
                    self.cloudSyncConnectionHealthy = true
                }
                self.refreshCloudSyncState()
                self.refreshOperationalStatus()
                self.notifyProjectsChanged()
                NotificationCenter.default.post(name: .entriesDidChange, object: nil)
                self.refreshSelectedEntryVersions()
                if result.syncSummary != nil {
                    self.bannerMessage = "已恢复本地已删分组 \(result.projectsRestored) 个、词条 \(result.entriesRestored) 条，并已完整回推至云端。"
                } else {
                    self.bannerMessage = "已恢复本地已删分组 \(result.projectsRestored) 个、词条 \(result.entriesRestored) 条。"
                }
            } catch is CancellationError {
                return
            } catch {
                guard let self else { return }
                self.bannerMessage = error.localizedDescription
            }
        }
    }

    private func updateAutoCloudSyncPollTimer() {
        let trimmedEndpoint = cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cloudSyncEnabled, !trimmedEndpoint.isEmpty, cloudSyncService != nil, !isSyncAuthPaused else {
            autoCloudSyncPollTimer?.cancel()
            autoCloudSyncPollTimer = nil
            return
        }
        guard autoCloudSyncPollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 45, repeating: 45, leeway: .seconds(5))
        timer.setEventHandler { [weak self] in
            self?.triggerOpportunisticCloudSyncIfNeeded(minIntervalSeconds: 30)
        }
        timer.resume()
        autoCloudSyncPollTimer = timer
    }

    private func refreshPendingSyncStateAsync() {
        guard let cloudSyncService else { return }
        statusQueue.async { [weak self] in
            guard let pending = try? cloudSyncService.pendingSyncState() else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.hasPendingLocalChanges != pending.hasPendingLocalChanges {
                    self.hasPendingLocalChanges = pending.hasPendingLocalChanges
                }
                if self.pendingLocalDelta != pending.pendingDelta {
                    self.pendingLocalDelta = pending.pendingDelta
                }
                if let rev = pending.lastSyncedRevision, self.cloudRemoteRevision != rev {
                    self.cloudRemoteRevision = rev
                }
                self.recomputeSyncBadgeState()
            }
        }
    }

    private var hasActiveDirtyInlineDraft: Bool {
        guard !inlineDraftEntryId.isEmpty,
              let entry = entries.first(where: { $0.id == inlineDraftEntryId })
                  ?? (try? entryRepository.fetchById(inlineDraftEntryId)) else {
            return false
        }
        return hasUnsavedInlineChanges(for: entry)
            || inlineAutoSaveState == .pending
            || inlineAutoSaveState == .saving
            || inlineAutoSaveState == .invalid
    }

    func triggerOpportunisticCloudSyncIfNeeded(force: Bool = false, minIntervalSeconds: TimeInterval = 18) {
        guard cloudSyncEnabled,
              !isSyncAuthPaused,
              !isApplyingCloudSyncChanges,
              !isCloudSyncInFlight,
              activeMaintenanceTask == nil,
              let cloudSyncService else {
            return
        }
        if !force, hasActiveDirtyInlineDraft {
            return
        }
        let endpoint = cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastOpportunisticCloudSyncAt) < minIntervalSeconds {
            return
        }
        lastOpportunisticCloudSyncAt = now
        performSilentCloudSync(cloudSyncService: cloudSyncService, endpoint: endpoint, apiKey: cloudSyncApiKey)
    }

    private func performSilentCloudSync(cloudSyncService: CloudSyncService, endpoint: String, apiKey: String) {
        guard activeMaintenanceTask == nil, !isCloudSyncInFlight, !isSyncAuthPaused else { return }
        isCloudSyncInFlight = true
        lastOpportunisticCloudSyncAt = Date()
        activeCloudSyncTask = Task { @MainActor [weak self] in
            defer {
                self?.isCloudSyncInFlight = false
                self?.activeCloudSyncTask = nil
            }
            do {
                let report = try await cloudSyncService.syncWithReport(
                    endpoint: endpoint,
                    apiKey: apiKey,
                    actionMode: .smartBidirectional,
                    forceFullSync: false,
                    isAutoSync: true
                )
                guard let self, !Task.isCancelled else { return }
                self.isSyncAuthPaused = false
                self.lastSyncErrorMessage = nil
                self.cloudSyncConnectionHealthy = true
                self.lastSyncReport = report
                self.refreshCloudSyncState()
                let hasPulledChanges = report.pulledProjectsCreated > 0
                    || report.pulledProjectsUpdated > 0
                    || report.pulledEntriesCreated > 0
                    || report.pulledEntriesUpdated > 0
                    || report.pulledDeletionsCount > 0
                    || report.orphansMigrated > 0
                if hasPulledChanges {
                    self.isApplyingCloudSyncChanges = true
                    defer { self.isApplyingCloudSyncChanges = false }
                    self.notifyProjectsChanged()
                    NotificationCenter.default.post(name: .entriesDidChange, object: nil)
                    self.refreshSelectedEntryVersions()
                    self.refreshRecentSoftDeletedEntries()
                }
                if report.protectedEntriesCount > 0 || report.protectedProjectsCount > 0 {
                    self.refreshOperationalStatus()
                    self.bannerMessage = "防丢保护已触发：已拦截云端异常删除 \(report.protectedEntriesCount) 条词条/\(report.protectedProjectsCount) 个分组，并从本地自动恢复云端数据。"
                }
            } catch is CancellationError {
                return
            } catch {
                PPLogger.app.error("Auto cloud sync failed: \(error.localizedDescription)")
                guard let self else { return }
                self.cloudSyncConnectionHealthy = false
                self.lastSyncErrorMessage = error.localizedDescription
                if Self.isAuthenticationError(error) {
                    self.isSyncAuthPaused = true
                    self.updateAutoCloudSyncPollTimer()
                    self.bannerMessage = "云端同步鉴权失败（\(error.localizedDescription)），已暂停自动轮询，请检查同步 Token 后重试。"
                }
                self.recomputeSyncBadgeState()
            }
        }
    }

    private func scheduleAutoCloudSyncIfNeeded() {
        refreshPendingSyncStateAsync()
        guard cloudSyncEnabled,
              !isSyncAuthPaused,
              !isApplyingCloudSyncChanges,
              let cloudSyncService else {
            return
        }
        let endpoint = cloudSyncEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty else { return }
        let apiKey = cloudSyncApiKey

        pendingAutoCloudSyncWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.performSilentCloudSync(cloudSyncService: cloudSyncService, endpoint: endpoint, apiKey: apiKey)
        }
        pendingAutoCloudSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: workItem)
    }

    func flushPendingChangesBeforeTermination() {
        _ = commitPendingInlineChangesIfNeeded()
        if pendingCloudSyncSettingsPersistWorkItem != nil {
            saveCloudSyncSettings(showBanner: false)
        }
        cancelPendingBackgroundTasks()
    }

    func cancelPendingBackgroundTasks() {
        pendingEntriesRefreshWorkItem?.cancel()
        pendingEntriesRefreshWorkItem = nil
        pendingReferenceSearchWorkItem?.cancel()
        pendingReferenceSearchWorkItem = nil
        pendingVersionRefreshWorkItem?.cancel()
        pendingVersionRefreshWorkItem = nil
        pendingInlineAutoSaveWorkItem?.cancel()
        pendingInlineAutoSaveWorkItem = nil
        pendingAutoCloudSyncWorkItem?.cancel()
        pendingAutoCloudSyncWorkItem = nil
        pendingCloudSyncSettingsPersistWorkItem?.cancel()
        pendingCloudSyncSettingsPersistWorkItem = nil
        autoCloudSyncPollTimer?.cancel()
        autoCloudSyncPollTimer = nil
        activeCloudSyncTask?.cancel()
        activeCloudSyncTask = nil
        activeConnectionTestTask?.cancel()
        activeConnectionTestTask = nil
    }

    // MARK: - Off-main maintenance plumbing

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
        maintenanceQueue.async { [weak self] in
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

    private func beginPanel(_ panel: NSSavePanel, completion: @escaping (URL) -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            MainActor.assumeIsolated {
                guard response == .OK, let url = panel.url else { return }
                completion(url)
            }
        }

        if let window = hostWindowProvider(), window.isVisible {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    private static let fileTimestampFormatter = ISO8601DateFormatter()

    private static func fileTimestamp() -> String {
        fileTimestampFormatter.string(from: Date())
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

    func setCurrentProject(_ projectId: String) {
        persistCurrentProject(projectId)
        if let project = projects.first(where: { $0.id == projectId }) {
            bannerMessage = "当前项目已切换为 \(project.name)。"
        }
    }

    func cycleCurrentProject(step: Int) {
        guard step != 0 else { return }
        let candidates = switchableProjects.isEmpty
            ? ((try? projectRepository.fetchAll(includeArchived: false)) ?? [])
            : switchableProjects
        guard !candidates.isEmpty else { return }
        let activeId = currentProjectId.isEmpty ? appState.effectiveProjectId : currentProjectId
        let currentIndex = candidates.firstIndex(where: { $0.id == activeId }) ?? 0
        let count = candidates.count
        let normalizedStep = ((step % count) + count) % count
        let nextIndex = (currentIndex + normalizedStep) % count
        let nextProject = candidates[nextIndex]
        if nextProject.id != activeId {
            setCurrentProject(nextProject.id)
        }
    }

    func setCurrentProjectToSelected() {
        guard let project = selectedProject else {
            bannerMessage = "请先选择一个具体项目。"
            return
        }
        persistCurrentProject(project.id)
        bannerMessage = "当前项目已切换为 \(project.name)。"
    }

    func startCreateProject(kind: Project.GroupKind = .project) {
        projectDraft = ProjectDraft(existingProject: nil, defaultKind: kind)
    }

    func startRenameSelectedProject() {
        guard let project = selectedProject else {
            bannerMessage = "请先选择要重命名的项目或分类。"
            return
        }
        projectDraft = ProjectDraft(existingProject: project, defaultKind: project.groupKind)
    }

    func saveProjectDraft() -> Bool {
        guard var draft = projectDraft else {
            return false
        }

        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.name.isEmpty else {
            bannerMessage = "名称不能为空。"
            return false
        }

        do {
            if let existingProject = draft.existingProject {
                try projectRepository.rename(
                    id: existingProject.id,
                    newName: draft.name,
                    groupKind: draft.groupKind
                )
                bannerMessage = "已保存「\(draft.name)」。"
            } else {
                let project = Project(name: draft.name, groupKind: draft.groupKind)
                try projectRepository.create(project)
                selectedProjectId = project.id
                bannerMessage = "已创建\(draft.groupKind.displayName)「\(draft.name)」。"
            }

            projectDraft = nil
            notifyProjectsChanged()
            return true
        } catch RepositoryError.duplicateProjectName(let existingName) {
            bannerMessage = "已存在同名分组「\(existingName)」，请使用其他名称。"
            return false
        } catch RepositoryError.emptyProjectName {
            bannerMessage = "名称不能为空。"
            return false
        } catch RepositoryError.cannotRenameSystemProject {
            bannerMessage = "系统内置分组不可重命名。"
            return false
        } catch {
            PPLogger.project.error("Failed to save project draft: \(error.localizedDescription)")
            bannerMessage = "保存失败，请重试。"
            return false
        }
    }

    func toggleArchiveProject(_ project: Project) {
        guard !project.isSystemProtected else {
            bannerMessage = "系统内置分组不可归档。"
            return
        }
        let targetState = !project.isArchived
        do {
            try projectRepository.setArchived(id: project.id, isArchived: targetState)
            if targetState && appState.currentProjectId == project.id {
                persistCurrentProject(appState.defaultProjectId)
            }
            notifyProjectsChanged()
            bannerMessage = targetState ? "项目「\(project.name)」已归档（词条与版本历史已留存）。" : "项目「\(project.name)」已取消归档。"
        } catch {
            PPLogger.project.error("Failed to toggle project archive state: \(error.localizedDescription)")
            bannerMessage = "更新归档状态失败，请重试。"
        }
    }

    func setProjectGroupKind(_ project: Project, kind: Project.GroupKind) {
        guard !project.isSystemProtected else {
            bannerMessage = "系统内置分组不可更改类型。"
            return
        }
        do {
            try projectRepository.setGroupKind(id: project.id, groupKind: kind)
            notifyProjectsChanged()
            bannerMessage = "已将「\(project.name)」标记为\(kind.displayName)。"
        } catch {
            PPLogger.project.error("Failed to set project group kind: \(error.localizedDescription)")
            bannerMessage = "更改分组标记失败，请重试。"
        }
    }

    func requestDeleteSelectedProject() {
        guard let project = selectedProject else {
            bannerMessage = "请先选择要删除的项目。"
            return
        }
        requestDeleteProject(project)
    }

    /// Requests deletion confirmation for a specific project (e.g. from sidebar context menu)
    /// without mutating `selectedProjectId` before the user confirms.
    func requestDeleteProject(_ project: Project) {
        guard !project.isSystemProtected else {
            bannerMessage = project.isDefault ? "通用项目不能删除。" : "系统内置分组不能删除。"
            return
        }

        do {
            let entryCount = try projectRepository.entryCount(forProjectId: project.id)
            let activeTargets = (try? projectRepository.fetchActiveTargetProjects(excluding: project.id))
                ?? targetProjects(excluding: project.id)
            let defaultTargetId = activeTargets.first(where: { $0.id == appState.defaultProjectId })?.id
                ?? activeTargets.first?.id
                ?? ""
            if entryCount > 0 && defaultTargetId.isEmpty {
                bannerMessage = "没有可用的活跃迁移目标。"
                return
            }
            deleteProjectState = ProjectDeletionState(
                project: project,
                entryCount: entryCount,
                targetProjectId: defaultTargetId
            )
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
            let replacementId: String?
            if state.entryCount == 0 {
                try projectRepository.delete(id: state.project.id)
                replacementId = appState.defaultProjectId
                bannerMessage = "项目「\(state.project.name)」已删除。"
            } else {
                try projectRepository.migrateAndDelete(fromId: state.project.id, toId: state.targetProjectId)
                replacementId = state.targetProjectId
                bannerMessage = "项目已删除，词条已迁移。"
            }
            handleProjectDeletionFallback(deletedProjectId: state.project.id, replacementProjectId: replacementId)
            deleteProjectState = nil
            notifyProjectsChanged()
            if state.entryCount > 0 {
                NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            }
            return true
        } catch RepositoryError.cannotMigrateToArchivedProject {
            bannerMessage = "不能将词条迁移到已归档项目。"
            return false
        } catch {
            PPLogger.project.error("Failed to migrate and delete project: \(error.localizedDescription)")
            bannerMessage = "项目删除失败，请重试。"
            return false
        }
    }

    static func deriveEntryTitle(from content: String, fallback: String = "未命名词条") -> String {
        let firstLine = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? fallback
        return String(firstLine.prefix(36))
    }

    static func extractQuickCaptureContentAndTags(from rawText: String) -> (content: String, tags: [String]) {
        let trimmedRaw = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            return ("", [])
        }

        var collectedTags: [String] = []
        var cleanedLines: [String] = []

        for line in trimmedRaw.components(separatedBy: .newlines) {
            var lineWords: [String] = []
            for tokenSub in line.split(whereSeparator: \.isWhitespace) {
                let token = String(tokenSub)
                if token.hasPrefix("#"), token.count > 1 {
                    let body = token.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: ",，、;；"))
                    if !body.isEmpty, !body.allSatisfy({ $0 == "#" }) {
                        collectedTags.append(String(body.prefix(10)))
                        continue
                    }
                }
                lineWords.append(token)
            }
            let reconstructedLine = lineWords.joined(separator: " ")
            if !reconstructedLine.isEmpty || line.trimmingCharacters(in: .whitespaces).isEmpty {
                cleanedLines.append(reconstructedLine)
            }
        }

        let cleanedContent = cleanedLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let finalContent = cleanedContent.isEmpty ? trimmedRaw : cleanedContent
        return (finalContent, Entry.normalizeTags(collectedTags))
    }

    func startCreateEntry(preferredType: Constants.EntryType? = nil) {
        let resolvedCurrentId = currentProjectId.isEmpty ? appState.effectiveProjectId : currentProjectId
        let defaultProjectId = selectedProjectId == Self.allProjectsSelection ? resolvedCurrentId : selectedProjectId
        let isInboxTarget = defaultProjectId == Constants.inboxProjectId
            || defaultProjectId == inboxProject?.id
            || selectedProjectId == Constants.inboxProjectId
            || selectedProjectId == inboxProject?.id
        let resolvedType: Constants.EntryType = {
            if let preferredType {
                return preferredType
            }
            if let activeKind = entryKindFilter, let parsed = Constants.EntryType(rawValue: activeKind) {
                return parsed
            }
            if isInboxTarget {
                return .note
            }
            return .prompt
        }()
        entryDraft = EntryDraft(
            existingEntry: nil,
            defaultProjectId: defaultProjectId,
            defaultType: resolvedType.rawValue
        )
    }

    func startEditEntry(_ entry: Entry) {
        entryDraft = EntryDraft(existingEntry: entry, defaultProjectId: entry.projectId)
    }

    func saveEntryDraft() -> Bool {
        guard let draft = entryDraft else {
            return false
        }

        let trimmedContent = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            bannerMessage = "词条内容不能为空。"
            return false
        }
        let rawTrimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTitle = rawTrimmedTitle.isEmpty
            ? Self.deriveEntryTitle(from: draft.content)
            : rawTrimmedTitle

        do {
            let parsedTags = draft.parsedTags
            if let existingEntry = draft.existingEntry {
                let updated = Entry(
                    id: existingEntry.id,
                    projectId: draft.projectId,
                    title: effectiveTitle,
                    content: draft.content,
                    type: draft.type,
                    isPinned: draft.isPinned,
                    isCompleted: existingEntry.isCompleted,
                    sortOrder: draft.sortOrder,
                    useCount: existingEntry.useCount,
                    lastUsedAt: existingEntry.lastUsedAt,
                    createdAt: existingEntry.createdAt,
                    updatedAt: Date(),
                    deletedAt: existingEntry.deletedAt,
                    sourceEntryId: existingEntry.sourceEntryId,
                    tags: parsedTags
                )
                try entryRepository.update(updated)
                lastInlineVersionSnapshotAtByEntryId[updated.id] = Date()
                if let idx = entries.firstIndex(where: { $0.id == updated.id }) {
                    entries[idx] = updated
                    refreshEntryFacets()
                    refreshDisplayedEntries()
                }
                if inlineDraftEntryId == updated.id {
                    syncInlineDraft(with: updated, force: true)
                }
                bannerMessage = "词条已更新。"
            } else {
                let entry = Entry(
                    projectId: draft.projectId,
                    title: effectiveTitle,
                    content: draft.content,
                    type: draft.type,
                    isPinned: draft.isPinned,
                    sortOrder: draft.sortOrder,
                    tags: parsedTags
                )
                try entryRepository.create(entry)
                if selectedProjectId == Self.allProjectsSelection || selectedProjectId == entry.projectId {
                    entries.insert(entry, at: 0)
                    refreshEntryFacets()
                    refreshDisplayedEntries()
                }
                selectedEntryId = entry.id
                requestProgrammaticScroll(anchor: .top)
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

    @discardableResult
    func submitQuickCapture(text: String? = nil, type: Constants.EntryType = .note) -> Entry? {
        let rawInput = (text ?? quickCaptureText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawInput.isEmpty else {
            return nil
        }

        let (cleanedContent, extractedTags) = Self.extractQuickCaptureContentAndTags(from: rawInput)
        guard !cleanedContent.isEmpty else {
            return nil
        }

        let targetProjectId = quickCaptureTargetProjectId
        guard !targetProjectId.isEmpty else {
            bannerMessage = "未找到可用的目标分组。"
            return nil
        }

        let fallbackTitle = type == .todo ? "待办事项" : "随手速记"
        let title = Self.deriveEntryTitle(from: cleanedContent, fallback: fallbackTitle)
        let newEntry = Entry(
            projectId: targetProjectId,
            title: title,
            content: cleanedContent,
            type: type.rawValue,
            tags: extractedTags
        )

        do {
            try entryRepository.create(newEntry, changeNote: "快速速记")
            if text == nil || quickCaptureText.trimmingCharacters(in: .whitespacesAndNewlines) == rawInput {
                quickCaptureText = ""
            }
            if let activeKind = entryKindFilter, activeKind != newEntry.type {
                entryKindFilter = nil
            }
            if selectedProjectId == Self.allProjectsSelection || selectedProjectId == targetProjectId {
                entries.insert(newEntry, at: 0)
                refreshEntryFacets()
                refreshDisplayedEntries()
            }
            selectedEntryId = newEntry.id
            requestProgrammaticScroll(anchor: .top)
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            let destName = quickCaptureDestinationName
            let kindLabel = type == .todo ? "待办" : "便签"
            bannerMessage = "已记\(kindLabel)至「\(destName)」：\(title)"
            return newEntry
        } catch {
            PPLogger.entry.error("Failed to submit quick capture: \(error.localizedDescription)")
            bannerMessage = "速记保存失败，请重试。"
            return nil
        }
    }

    @discardableResult
    func quickJotFromClipboard(type: Constants.EntryType = .note) -> Entry? {
        guard let rawText = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawText.isEmpty else {
            bannerMessage = "当前剪贴板中没有可用的文本内容。"
            return nil
        }
        return submitQuickCapture(text: rawText, type: type)
    }

    @discardableResult
    func clearCompletedEntriesInVisibleScope() -> Int {
        if selectedProjectId != Self.allProjectsSelection {
            do {
                let deletedCount = try entryRepository.deleteCompleted(projectId: selectedProjectId)
                guard deletedCount > 0 else {
                    bannerMessage = "当前分组没有已完成记录。"
                    return 0
                }
                if deletedCount >= 3 {
                    cloudSyncService?.armAllowMassDeleteForNextSync()
                }
                entries.removeAll { $0.isCompleted && $0.projectId == selectedProjectId }
                refreshEntryFacets()
                refreshDisplayedEntries()
                NotificationCenter.default.post(name: .entriesDidChange, object: nil)
                bannerMessage = "已清理 \(deletedCount) 条已完成记录。"
                return deletedCount
            } catch {
                PPLogger.entry.error("Failed to clear completed entries in project \(self.selectedProjectId): \(error.localizedDescription)")
                bannerMessage = "清理已完成记录失败，请重试。"
                return 0
            }
        }

        let archivedIds = Set(archivedProjects.map(\.id))
        do {
            let deletedCount = try entryRepository.deleteCompleted(
                projectId: nil,
                excludeArchivedProjects: !archivedIds.isEmpty
            )
            guard deletedCount > 0 else {
                bannerMessage = "当前分组没有已完成记录。"
                return 0
            }
            if deletedCount >= 3 {
                cloudSyncService?.armAllowMassDeleteForNextSync()
            }
            if archivedIds.isEmpty {
                entries.removeAll(where: \.isCompleted)
            } else {
                entries.removeAll { $0.isCompleted && !archivedIds.contains($0.projectId) }
            }
            refreshEntryFacets()
            refreshDisplayedEntries()
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            bannerMessage = "已清理 \(deletedCount) 条已完成记录。"
            return deletedCount
        } catch {
            PPLogger.entry.error("Failed to clear all completed entries: \(error.localizedDescription)")
            bannerMessage = "清理已完成记录失败，请重试。"
            return 0
        }
    }

    func requestDeleteEntry(_ entry: Entry) {
        entryPendingDeletion = entry
    }

    func updateEntryProject(_ entry: Entry, toProjectId targetProjectId: String) {
        let latest = flushAndResolveLatestEntry(entry)
        guard latest.projectId != targetProjectId else { return }
        var updated = latest
        updated.projectId = targetProjectId
        updated.updatedAt = Date()
        do {
            try entryRepository.update(updated, recordVersion: false)
            if inlineDraftEntryId == updated.id {
                isSyncingInlineDraftProgrammatically = true
                inlineDraftProjectId = targetProjectId
                isSyncingInlineDraftProgrammatically = false
            }
            if selectedProjectId != Self.allProjectsSelection && selectedProjectId != targetProjectId {
                entries.removeAll { $0.id == updated.id }
            } else if let idx = entries.firstIndex(where: { $0.id == updated.id }) {
                entries[idx] = updated
            }
            refreshEntryFacets()
            refreshDisplayedEntries()
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            bannerMessage = "已移至「\(projectName(for: targetProjectId))」。"
        } catch {
            PPLogger.entry.error("Failed to update entry project: \(error.localizedDescription)")
            bannerMessage = "更改归属分组失败，请重试。"
        }
    }

    @discardableResult
    func moveEntries(withIds ids: [String], toProjectId targetProjectId: String) -> Int {
        let uniqueIds = Array(Set(ids))
        guard !uniqueIds.isEmpty else { return 0 }
        if !inlineDraftEntryId.isEmpty, uniqueIds.contains(inlineDraftEntryId) {
            commitPendingInlineChangesIfNeeded(forEntryId: inlineDraftEntryId)
        }
        if uniqueIds.count == 1,
           let singleId = uniqueIds.first,
           let entry = entries.first(where: { $0.id == singleId }) ?? (try? entryRepository.fetchById(singleId)) {
            guard entry.projectId != targetProjectId else { return 0 }
            updateEntryProject(entry, toProjectId: targetProjectId)
            return 1
        }

        let movedCount = (try? entryRepository.moveEntries(ids: uniqueIds, toProjectId: targetProjectId)) ?? 0
        if movedCount > 0 {
            let movedIdSet = Set(uniqueIds)
            if !inlineDraftEntryId.isEmpty, movedIdSet.contains(inlineDraftEntryId) {
                isSyncingInlineDraftProgrammatically = true
                inlineDraftProjectId = targetProjectId
                isSyncingInlineDraftProgrammatically = false
            }
            if selectedProjectId != Self.allProjectsSelection && selectedProjectId != targetProjectId {
                entries.removeAll { movedIdSet.contains($0.id) }
            } else {
                let now = Date()
                for idx in entries.indices where movedIdSet.contains(entries[idx].id) {
                    entries[idx].projectId = targetProjectId
                    entries[idx].updatedAt = now
                }
            }
            refreshEntryFacets()
            refreshDisplayedEntries()
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            bannerMessage = "已将 \(movedCount) 条内容移至「\(projectName(for: targetProjectId))」。"
        }
        return movedCount
    }

    func updateEntryType(_ entry: Entry, toType newType: String) {
        let latest = flushAndResolveLatestEntry(entry)
        guard latest.type != newType else { return }
        var updated = latest
        updated.type = newType
        updated.updatedAt = Date()
        do {
            try entryRepository.update(updated, recordVersion: false)
            if inlineDraftEntryId == updated.id {
                isSyncingInlineDraftProgrammatically = true
                inlineDraftType = newType
                isSyncingInlineDraftProgrammatically = false
            }
            if let idx = entries.firstIndex(where: { $0.id == updated.id }) {
                entries[idx] = updated
                refreshEntryFacets()
                refreshDisplayedEntries()
            }
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            let displayName = Constants.EntryType.resolve(newType).displayName
            bannerMessage = "已设为「\(displayName)」。"
        } catch {
            PPLogger.entry.error("Failed to update entry type: \(error.localizedDescription)")
            bannerMessage = "更改词条类型失败，请重试。"
        }
    }

    func toggleEntryCompleted(_ entry: Entry) {
        let latest = flushAndResolveLatestEntry(entry)
        let nextState = !latest.isCompleted
        do {
            try entryRepository.setCompleted(id: latest.id, isCompleted: nextState)
            if inlineDraftEntryId == latest.id {
                isSyncingInlineDraftProgrammatically = true
                inlineDraftIsCompleted = nextState
                isSyncingInlineDraftProgrammatically = false
            }
            if let idx = entries.firstIndex(where: { $0.id == latest.id }) {
                entries[idx].isCompleted = nextState
                entries[idx].updatedAt = Date()
                refreshEntryFacets()
                refreshDisplayedEntries()
            }
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            bannerMessage = nextState ? "已标记为完成：\(latest.title)" : "已恢复为待办：\(latest.title)"
        } catch {
            PPLogger.entry.error("Failed to toggle entry completed state: \(error.localizedDescription)")
            bannerMessage = "更新完成状态失败，请重试。"
        }
    }

    @discardableResult
    func saveInlineEntry(
        _ entry: Entry,
        title: String,
        content: String,
        projectId: String,
        type: String,
        isPinned: Bool,
        isCompleted: Bool,
        tagsText: String,
        changeNote: String? = nil,
        isAutoSave: Bool = false
    ) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else {
            if !isAutoSave {
                bannerMessage = "标题和内容都不能为空。"
            } else {
                inlineAutoSaveState = .invalid
            }
            return false
        }

        let parsedTags = Entry.normalizeTags(
            tagsText
                .components(separatedBy: CharacterSet(charactersIn: ",，、"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )

        let didChangeContent = entry.title != trimmedTitle || entry.content != content
        let projectChanged = entry.projectId != projectId
        let shouldRecordVersion = shouldRecordInlineVersionSnapshot(
            for: entry.id,
            isAutoSave: isAutoSave,
            didChangeContent: didChangeContent
        )
        do {
            let saveResult = try entryRepository.updateEditableFields(
                id: entry.id,
                title: trimmedTitle,
                content: content,
                type: type,
                projectId: projectId,
                tags: parsedTags,
                isPinned: isPinned,
                isCompleted: isCompleted,
                changeNote: changeNote,
                recordVersion: shouldRecordVersion
            )
            let updated: Entry
            switch saveResult {
            case .deletedOrMissing:
                pendingInlineAutoSaveWorkItem?.cancel()
                pendingInlineAutoSaveWorkItem = nil
                inlineAutoSaveState = .idle
                bannerMessage = "该词条已在其他位置或云端同步中删除，无法继续保存。"
                NotificationCenter.default.post(name: .entriesDidChange, object: nil)
                return false
            case .updated(let persisted):
                updated = persisted
            }
            if shouldRecordVersion && didChangeContent {
                inlineSessionVersionedEntryId = updated.id
                recordInlineVersionSnapshotTimestamp(for: updated.id)
            }

            let hadEntryInMemory: Bool
            if selectedProjectId != Self.allProjectsSelection && selectedProjectId != updated.projectId {
                let countBefore = entries.count
                entries.removeAll { $0.id == updated.id }
                hadEntryInMemory = entries.count != countBefore
            } else if let idx = entries.firstIndex(where: { $0.id == updated.id }) {
                entries[idx] = updated
                hadEntryInMemory = true
            } else {
                hadEntryInMemory = false
            }

            inlineAutoSaveState = .saved
            if !isAutoSave {
                syncInlineDraft(with: updated, force: true, preserveSavedState: true)
                bannerMessage = didChangeContent ? "已保存修改并留存历史版本。" : "已保存词条属性修改。"
            }

            if hadEntryInMemory {
                refreshEntryFacets()
                let newDisplayed = sortedVisibleEntries()
                if displayedEntries != newDisplayed {
                    displayedEntries = newDisplayed
                }
                if let selectedEntryId, !displayedEntries.contains(where: { $0.id == selectedEntryId }) {
                    self.selectedEntryId = displayedEntries.first?.id
                }
                postEntriesDidChangeSkippingSelfReload(projectChanged: projectChanged)
            } else {
                NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            }

            if shouldRecordVersion && didChangeContent {
                refreshSelectedEntryVersions(immediate: true)
            }
            return true
        } catch {
            PPLogger.entry.error("Failed to save inline entry: \(error.localizedDescription)")
            if !isAutoSave {
                bannerMessage = "保存修改失败，请重试。"
            }
            return false
        }
    }

    private func recordInlineVersionSnapshotTimestamp(for entryId: String, now: Date = Date()) {
        lastInlineVersionSnapshotAtByEntryId[entryId] = now
        if lastInlineVersionSnapshotAtByEntryId.count > Self.maxInlineVersionSnapshotCacheCount {
            let excess = lastInlineVersionSnapshotAtByEntryId.count - Self.maxInlineVersionSnapshotCacheCount
            let oldest = lastInlineVersionSnapshotAtByEntryId.sorted { $0.value < $1.value }.prefix(excess)
            for (staleId, _) in oldest {
                lastInlineVersionSnapshotAtByEntryId.removeValue(forKey: staleId)
            }
        }
    }

    private func shouldRecordInlineVersionSnapshot(
        for entryId: String,
        isAutoSave: Bool,
        didChangeContent: Bool
    ) -> Bool {
        guard didChangeContent else { return false }
        guard isAutoSave else { return true }
        if inlineSessionVersionedEntryId != entryId {
            return true
        }
        guard let lastSnapshot = lastInlineVersionSnapshotAtByEntryId[entryId] else {
            return true
        }
        return Date().timeIntervalSince(lastSnapshot) >= Self.inlineVersionSnapshotInterval
    }

    private func postEntriesDidChangeSkippingSelfReload(projectChanged: Bool) {
        suppressSelfEntriesReloadCount += 1
        defer { suppressSelfEntriesReloadCount -= 1 }
        NotificationCenter.default.post(name: .entriesDidChange, object: nil)
        if projectChanged {
            refreshProjectEntryCounts()
        }
        refreshReferenceEntries()
        scheduleAutoCloudSyncIfNeeded()
    }

    func restoreEntryVersion(_ version: EntryVersion) {
        pendingInlineAutoSaveWorkItem?.cancel()
        pendingInlineAutoSaveWorkItem = nil
        do {
            let restored = try entryRepository.restoreVersion(versionId: version.id)
            if let idx = entries.firstIndex(where: { $0.id == restored.id }) {
                entries[idx] = restored
            }
            selectedEntryId = restored.id
            syncInlineDraft(with: restored, force: true)
            inlineAutoSaveState = .idle
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            refreshSelectedEntryVersions(immediate: true)
            bannerMessage = "已恢复至历史版本 v\(version.versionNumber)。"
        } catch {
            PPLogger.entry.error("Failed to restore entry version: \(error.localizedDescription)")
            bannerMessage = "恢复历史版本失败，请重试。"
        }
    }

    @discardableResult
    func cloneEntry(_ entry: Entry, toProjectId targetProjectId: String) -> Entry? {
        let latest = flushAndResolveLatestEntry(entry)
        do {
            let cloned = try entryRepository.cloneEntry(id: latest.id, toProjectId: targetProjectId)
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            let targetName = projectName(for: targetProjectId)
            bannerMessage = "已将「\(latest.title)」复制到「\(targetName)」。"
            return cloned
        } catch {
            PPLogger.entry.error("Failed to clone entry: \(error.localizedDescription)")
            bannerMessage = "复制词条到目标分组失败，请重试。"
            return nil
        }
    }

    func createQuickEntryFromClipboard(intoProjectId targetProjectId: String, type: Constants.EntryType = .prompt) {
        guard let rawText = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawText.isEmpty else {
            bannerMessage = "当前剪贴板中没有可用的文本内容。"
            return
        }
        let title = Self.deriveEntryTitle(from: rawText, fallback: "剪贴板快贴")
        let newEntry = Entry(
            projectId: targetProjectId,
            title: title,
            content: rawText,
            type: type.rawValue
        )
        do {
            try entryRepository.create(newEntry, changeNote: "从剪贴板创建")
            if selectedProjectId == Self.allProjectsSelection || selectedProjectId == targetProjectId {
                entries.insert(newEntry, at: 0)
                refreshEntryFacets()
                refreshDisplayedEntries()
            }
            selectedEntryId = newEntry.id
            requestProgrammaticScroll(anchor: .top)
            NotificationCenter.default.post(name: .entriesDidChange, object: nil)
            bannerMessage = "已从剪贴板创建词条：\(title)"
        } catch {
            PPLogger.entry.error("Failed to create entry from clipboard: \(error.localizedDescription)")
            bannerMessage = "从剪贴板创建失败，请重试。"
        }
    }

    func openReferenceWindow() {
        onOpenReferenceWindow?()
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

        updaterService.$phase
            .combineLatest(updaterService.$canCheckForUpdates)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.refreshUpdaterStatus()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .projectsDidChange)
            .sink { [weak self] _ in
                self?.loadProjects()
                self?.scheduleEntriesRefresh(delayMs: 0)
                self?.scheduleAutoCloudSyncIfNeeded()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .entriesDidChange)
            .sink { [weak self] _ in
                guard let self, self.suppressSelfEntriesReloadCount == 0 else { return }
                self.scheduleEntriesRefresh(delayMs: 0)
                self.refreshProjectEntryCounts()
                self.refreshReferenceEntries()
                self.scheduleAutoCloudSyncIfNeeded()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .entryUsageDidChange)
            .sink { [weak self] _ in
                guard let self else { return }
                self.scheduleEntriesRefresh(delayMs: 0)
                self.refreshReferenceEntries()
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
            cachedActiveTargetProjects = (try? projectRepository.fetchActiveTargetProjects()) ?? nonArchivedProjects
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
            cachedActiveTargetProjects = []
            projectNamesById = [:]
            selectedProjectId = Self.allProjectsSelection
            bannerMessage = "加载项目列表失败。"
        }
    }

    private func scheduleEntriesRefresh(delayMs: Int, pruneStaleFilters: Bool = false) {
        pendingEntriesRefreshWorkItem?.cancel()
        pendingEntriesRefreshWorkItem = nil

        let selectedProjectId = self.selectedProjectId
        let (cleanedQuery, inlineTagFilter) = QuickPanelViewModel.extractTagFilter(from: self.entrySearchText)
        let entrySearchText = cleanedQuery
        let allProjectsSelection = Self.allProjectsSelection
        let entryRepository = self.entryRepository
        let entriesLoadQueue = self.entriesLoadQueue

        entriesRefreshGeneration += 1
        let generation = entriesRefreshGeneration

        let runLoad: @Sendable () -> Void = { [weak self] in
            entriesLoadQueue.async {
                let result: Result<[Entry], Error>
                do {
                    let entries: [Entry]
                    if selectedProjectId == allProjectsSelection {
                        if entrySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, inlineTagFilter == nil {
                            entries = try entryRepository.fetchAll(excludeArchivedProjects: true)
                        } else {
                            entries = try entryRepository.searchAll(
                                query: entrySearchText,
                                tag: inlineTagFilter,
                                excludeArchivedProjects: true,
                                limit: nil
                            )
                        }
                    } else if entrySearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, inlineTagFilter == nil {
                        entries = try entryRepository.fetchByProject(selectedProjectId)
                    } else {
                        entries = try entryRepository.search(
                            query: entrySearchText,
                            projectIds: [selectedProjectId],
                            tag: inlineTagFilter,
                            limit: nil
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
                        if pruneStaleFilters {
                            self.isBatchingEntryFilterUpdate = true
                            if let kind = self.entryKindFilter,
                               !entries.contains(where: { $0.type == kind }) {
                                self.entryKindFilter = nil
                            }
                            if let tag = self.entryTagFilter,
                               !entries.contains(where: { entry in
                                   entry.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
                               }) {
                                self.entryTagFilter = nil
                            }
                            self.isBatchingEntryFilterUpdate = false
                        }
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

        if delayMs <= 0 {
            runLoad()
        } else {
            let workItem = DispatchWorkItem(block: runLoad)
            pendingEntriesRefreshWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs), execute: workItem)
        }
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
