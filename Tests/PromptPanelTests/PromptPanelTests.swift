import Foundation
import GRDB
import SQLite3
import SwiftUI
@testable import PromptPanel
import KeyboardShortcuts

#if canImport(XCTest)
import XCTest

final class PromptPanelTests: XCTestCase {
    func testConstantsExist() {
        XCTAssertEqual(Constants.appName, "PromptPanel")
        XCTAssertEqual(Constants.bundleIdentifier, "com.promptpanel.app")
        XCTAssertEqual(Constants.defaultProjectName, "通用项目")
        XCTAssertEqual(Constants.panelWindowSize.width, Constants.panelContentSize.width + Constants.panelContentInsets.left + Constants.panelContentInsets.right)
        XCTAssertEqual(Constants.panelWindowSize.height, Constants.panelContentSize.height + Constants.panelContentInsets.top + Constants.panelContentInsets.bottom)
    }

    func testEntryLevelResolvesBoundaries() {
        // Locks the leveling thresholds so future churn doesn't silently
        // shift the visual tiers (rookie → master) users see in the UI.
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: -5), .rookie)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 0),   .rookie)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 1),   .bronze)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 3),   .bronze)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 4),   .silver)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 9),   .silver)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 10),  .gold)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 24),  .gold)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 25),  .platinum)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 59),  .platinum)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 60),  .diamond)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 149), .diamond)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 150), .master)
        XCTAssertEqual(Constants.EntryLevel.resolve(useCount: 9999), .master)
    }

    func testEntrySortModeRoundTripsThroughSettings() throws {
        // The sort dropdown writes through SettingsRepository; on next launch
        // MainWindowViewModel hydrates from it. Lock the round-trip so a typo
        // in the SettingsKey or rawValue can't silently reset users to .uses.
        let databaseManager = try makeDatabaseManager()
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)

        XCTAssertNil(try settingsRepository.getEntrySortMode())
        XCTAssertEqual(MainWindowViewModel.EntrySortMode.resolve(nil), .uses)

        try settingsRepository.setEntrySortMode(MainWindowViewModel.EntrySortMode.byLevel.rawValue)
        let stored = try settingsRepository.getEntrySortMode()
        XCTAssertEqual(MainWindowViewModel.EntrySortMode.resolve(stored), .byLevel)

        // Garbage values fall back to default rather than crashing.
        XCTAssertEqual(MainWindowViewModel.EntrySortMode.resolve("not_a_mode"), .uses)
    }

    @MainActor
    func testByLevelSortGroupsEntriesByTierThenUseCount() throws {
        // .byLevel is the "color blocks group together" mode: entries in the
        // same EntryLevel tier sit adjacent regardless of exact useCount, with
        // higher tiers first. .uses, by contrast, is strictly numeric.
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let loginItemService = LoginItemService()
        let updaterService = UpdaterService()
        let storageMaintenanceService = StorageMaintenanceService(
            dbQueue: databaseManager.dbQueue,
            logRepository: logRepository,
            databaseURL: databaseManager.databaseURL
        )
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let earlier = now.addingTimeInterval(-86_400)
        // Two gold-tier entries (10–24 uses) and one platinum (25–59). The gold
        // pair has a higher count on the *older* entry — this is what makes the
        // .uses vs .byLevel distinction observable.
        let goldHigh = Entry(id: "gold-high", projectId: defaultProject.id, title: "Gold High", content: "x", useCount: 24, lastUsedAt: earlier, updatedAt: earlier)
        let goldLow = Entry(id: "gold-low", projectId: defaultProject.id, title: "Gold Low", content: "x", useCount: 10, lastUsedAt: now, updatedAt: now)
        let platinum = Entry(id: "platinum", projectId: defaultProject.id, title: "Platinum", content: "x", useCount: 25, lastUsedAt: earlier, updatedAt: earlier)
        try entryRepository.create(goldHigh)
        try entryRepository.create(goldLow)
        try entryRepository.create(platinum)

        let viewModel = MainWindowViewModel(
            appState: appState,
            projectRepository: projectRepository,
            entryRepository: entryRepository,
            settingsRepository: settingsRepository,
            logRepository: logRepository,
            permissionService: permissionService,
            loginItemService: loginItemService,
            storageMaintenanceService: storageMaintenanceService,
            updaterService: updaterService,
            launchRecoveryReport: nil
        )

        viewModel.load()
        let loadDeadline = Date().addingTimeInterval(1)
        while viewModel.displayedEntries.count != 3 && Date() < loadDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        // .uses: strictly by number → 25 > 24 > 10. Recency is only a tiebreak.
        XCTAssertEqual(viewModel.displayedEntries.map(\.id), [platinum.id, goldHigh.id, goldLow.id])

        viewModel.entrySortMode = .byLevel
        // .byLevel: platinum (highest tier) first, then within the gold tier
        // the *more recent* entry wins — even though goldHigh has 24 uses vs
        // goldLow's 10, goldLow was used more recently.
        XCTAssertEqual(viewModel.displayedEntries.map(\.id), [platinum.id, goldLow.id, goldHigh.id])

        // Persistence side-effect: didSet should have written the new mode.
        XCTAssertEqual(
            MainWindowViewModel.EntrySortMode.resolve(try settingsRepository.getEntrySortMode()),
            .byLevel
        )
    }

    func testDatabaseSeedsDefaultProjectAndCurrentProject() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)

        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        XCTAssertEqual(defaultProject.name, Constants.defaultProjectName)
        XCTAssertEqual(try settingsRepository.getCurrentProjectId(), defaultProject.id)
    }

    func testProjectsFetchAllKeepsDefaultProjectFirstThenSortsByName() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())

        try projectRepository.create(Project(name: "000 Alpha"))
        try projectRepository.create(Project(name: "ZZZ Later"))

        let projects = try projectRepository.fetchAll()

        XCTAssertEqual(projects.first?.id, defaultProject.id)
        XCTAssertEqual(projects.dropFirst().map(\.name), ["000 Alpha", "ZZZ Later"])
    }

    @MainActor
    func testResolveCurrentProjectSelectionFallsBackToDefaultWhenPersistedProjectIsDangling() {
        let defaultProjectId = UUID().uuidString

        let resolution = AppDelegate.resolveCurrentProjectSelection(
            persistedCurrentProjectId: "missing-project",
            defaultProjectId: defaultProjectId,
            currentProjectExists: { $0 == defaultProjectId }
        )

        XCTAssertEqual(resolution.projectId, defaultProjectId)
        XCTAssertTrue(resolution.needsPersistence)
        XCTAssertNotNil(resolution.repairReason)
    }

    @MainActor
    func testResolveCurrentProjectSelectionKeepsValidPersistedProject() {
        let currentProjectId = UUID().uuidString
        let defaultProjectId = UUID().uuidString

        let resolution = AppDelegate.resolveCurrentProjectSelection(
            persistedCurrentProjectId: currentProjectId,
            defaultProjectId: defaultProjectId,
            currentProjectExists: { $0 == currentProjectId }
        )

        XCTAssertEqual(resolution.projectId, currentProjectId)
        XCTAssertFalse(resolution.needsPersistence)
        XCTAssertNil(resolution.repairReason)
    }

    func testPanelPinnedSettingRoundTrips() throws {
        let databaseManager = try makeDatabaseManager()
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)

        XCTAssertFalse(try settingsRepository.isPanelPinned())

        try settingsRepository.setPanelPinned(true)
        XCTAssertTrue(try settingsRepository.isPanelPinned())

        try settingsRepository.setPanelPinned(false)
        XCTAssertFalse(try settingsRepository.isPanelPinned())
    }

    func testPanelContentSizeSettingRoundTripsWithNormalization() throws {
        let databaseManager = try makeDatabaseManager()
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)

        XCTAssertEqual(try settingsRepository.getPanelContentSize(), Constants.panelContentSize)

        try settingsRepository.setPanelContentSize(NSSize(width: 820, height: 520))
        XCTAssertEqual(try settingsRepository.getPanelContentSize(), NSSize(width: 820, height: 520))

        try settingsRepository.setPanelContentSize(NSSize(width: 2000, height: 100))
        XCTAssertEqual(try settingsRepository.getPanelContentSize(), NSSize(width: Constants.panelMaxContentSize.width, height: Constants.panelMinContentSize.height))
    }

    func testPanelWindowOriginSettingRoundTrips() throws {
        let databaseManager = try makeDatabaseManager()
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)

        XCTAssertNil(try settingsRepository.getPanelWindowOrigin())

        try settingsRepository.setPanelWindowOrigin(NSPoint(x: 321.4, y: 456.6))
        XCTAssertEqual(try settingsRepository.getPanelWindowOrigin(), NSPoint(x: 321, y: 457))
    }

    func testMixedEntriesPreferCurrentProjectWhenSortKeysEqual() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)

        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        let currentProject = Project(name: "Current")
        try projectRepository.create(currentProject)

        let now = Date()
        try entryRepository.create(
            Entry(
                projectId: defaultProject.id,
                title: "共享标题",
                content: "通用内容",
                sortOrder: 10,
                useCount: 4,
                lastUsedAt: now,
                createdAt: now,
                updatedAt: now
            )
        )
        try entryRepository.create(
            Entry(
                projectId: currentProject.id,
                title: "共享标题",
                content: "当前内容",
                sortOrder: 10,
                useCount: 4,
                lastUsedAt: now,
                createdAt: now,
                updatedAt: now
            )
        )

        let result = try entryRepository.fetchMixed(
            currentProjectId: currentProject.id,
            defaultProjectId: defaultProject.id
        )

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first?.projectId, currentProject.id)
        XCTAssertEqual(result.last?.projectId, defaultProject.id)
    }

    func testMixedEntriesUseUpdatedAtAsFinalTieBreaker() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)

        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        let currentProject = Project(name: "Current")
        try projectRepository.create(currentProject)

        let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
        let newDate = oldDate.addingTimeInterval(60)
        let oldEntry = Entry(
            projectId: currentProject.id,
            title: "Old",
            content: "old",
            sortOrder: 0,
            useCount: 0,
            lastUsedAt: nil,
            createdAt: oldDate,
            updatedAt: oldDate
        )
        let newEntry = Entry(
            projectId: currentProject.id,
            title: "New",
            content: "new",
            sortOrder: 0,
            useCount: 0,
            lastUsedAt: nil,
            createdAt: newDate,
            updatedAt: newDate
        )
        try entryRepository.create(oldEntry)
        try entryRepository.create(newEntry)

        let result = try entryRepository.fetchMixed(
            currentProjectId: currentProject.id,
            defaultProjectId: defaultProject.id
        )

        XCTAssertEqual(result.map(\.id), [newEntry.id, oldEntry.id])
    }

    func testEntriesUseStableIdTieBreakerAcrossReadPaths() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)

        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let laterIdEntry = Entry(
            id: "tie-b",
            projectId: defaultProject.id,
            title: "Tie Sample",
            content: "stable tie sample",
            sortOrder: 0,
            useCount: 0,
            lastUsedAt: nil,
            createdAt: now,
            updatedAt: now
        )
        let earlierIdEntry = Entry(
            id: "tie-a",
            projectId: defaultProject.id,
            title: "Tie Sample",
            content: "stable tie sample",
            sortOrder: 0,
            useCount: 0,
            lastUsedAt: nil,
            createdAt: now,
            updatedAt: now
        )
        try entryRepository.create(laterIdEntry)
        try entryRepository.create(earlierIdEntry)

        XCTAssertEqual(try entryRepository.fetchByProject(defaultProject.id).map(\.id), ["tie-a", "tie-b"])
        XCTAssertEqual(try entryRepository.fetchAll().map(\.id), ["tie-a", "tie-b"])
        XCTAssertEqual(
            try entryRepository.fetchMixed(
                currentProjectId: defaultProject.id,
                defaultProjectId: defaultProject.id
            ).map(\.id),
            ["tie-a", "tie-b"]
        )
        XCTAssertEqual(
            try entryRepository.search(query: "Tie", projectIds: [defaultProject.id]).map(\.id),
            ["tie-a", "tie-b"]
        )
    }

    func testMigrateAndDeleteMovesEntriesToTargetProject() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)

        let sourceProject = Project(name: "Source")
        let targetProject = Project(name: "Target")
        try projectRepository.create(sourceProject)
        try projectRepository.create(targetProject)

        let entry = Entry(projectId: sourceProject.id, title: "Snippet", content: "echo hello")
        try entryRepository.create(entry)

        try projectRepository.migrateAndDelete(fromId: sourceProject.id, toId: targetProject.id)

        XCTAssertNil(try projectRepository.fetchById(sourceProject.id))
        let migratedEntry = try XCTUnwrap(entryRepository.fetchById(entry.id))
        XCTAssertEqual(migratedEntry.projectId, targetProject.id)
    }

    func testDeletingDefaultProjectFails() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())

        XCTAssertThrowsError(try projectRepository.delete(id: defaultProject.id)) { error in
            guard case RepositoryError.cannotDeleteDefault = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDeletingNonEmptyProjectFailsWithEntryCount() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)

        let project = Project(name: "Occupied")
        try projectRepository.create(project)
        try entryRepository.create(Entry(projectId: project.id, title: "Snippet", content: "echo hello"))

        XCTAssertThrowsError(try projectRepository.delete(id: project.id)) { error in
            guard case RepositoryError.projectNotEmpty(let count) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(count, 1)
        }
    }

    func testEntrySearchServiceReturnsDefaultOnlyWhenDefaultProjectIsActive() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        let searchService = EntrySearchService(entryRepository: entryRepository)

        try entryRepository.create(Entry(projectId: defaultProject.id, title: "Common", content: "Shared content"))

        let results = try searchService.search(
            query: "",
            currentProjectId: defaultProject.id,
            defaultProjectId: defaultProject.id
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.projectId, defaultProject.id)
    }

    func testEntrySearchServiceReturnsMixedResultsForCurrentAndDefaultProjects() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        let currentProject = Project(name: "Current")
        try projectRepository.create(currentProject)
        let searchService = EntrySearchService(entryRepository: entryRepository)

        try entryRepository.create(Entry(projectId: defaultProject.id, title: "Common", content: "Shared content"))
        try entryRepository.create(Entry(projectId: currentProject.id, title: "Current", content: "Current content"))

        let results = try searchService.search(
            query: "",
            currentProjectId: currentProject.id,
            defaultProjectId: defaultProject.id
        )

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(Set(results.map(\.projectId)), Set([defaultProject.id, currentProject.id]))
    }

    func testEntrySearchEscapesQuotedTokens() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        let searchService = EntrySearchService(entryRepository: entryRepository)

        try entryRepository.create(
            Entry(
                projectId: defaultProject.id,
                title: #"He said "hello""#,
                content: "Quoted content"
            )
        )

        let results = try searchService.search(
            query: #""hello""#,
            currentProjectId: defaultProject.id,
            defaultProjectId: defaultProject.id
        )

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, #"He said "hello""#)
    }

    func testExecutionLogPersistsFailureReasonAndDiagnostics() throws {
        let databaseManager = try makeDatabaseManager()
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)

        let log = ExecutionLog(
            entryId: "entry-1",
            projectId: "project-1",
            frontAppBundleId: "com.apple.Safari",
            observedAppBundleId: Bundle.main.bundleIdentifier,
            hasAccessibility: true,
            clipboardSuccess: true,
            pasteAttempted: false,
            pasteSuccess: false,
            result: Constants.ExecutionResult.clipboardOnly.rawValue,
            triggerSource: Constants.ExecutionTrigger.keyboardSubmit.rawValue,
            failureReason: Constants.ExecutionFailureReason.targetAppNotRestored.rawValue,
            targetAppRestoreDurationMs: 86,
            totalDurationMs: 143
        )

        try logRepository.record(log)
        let recentLogs = try logRepository.fetchRecent(limit: 10)
        let persisted = try XCTUnwrap(recentLogs.first)

        XCTAssertEqual(persisted.failureReason, Constants.ExecutionFailureReason.targetAppNotRestored.rawValue)
        XCTAssertEqual(persisted.triggerSource, Constants.ExecutionTrigger.keyboardSubmit.rawValue)
        XCTAssertEqual(persisted.targetAppRestoreDurationMs, 86)
        XCTAssertEqual(persisted.totalDurationMs, 143)
        XCTAssertEqual(persisted.observedAppBundleId, Bundle.main.bundleIdentifier)
    }

    @MainActor
    func testExecuteServiceLogsAccessibilityFallback() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        let entry = Entry(projectId: defaultProject.id, title: "Prompt", content: "Copy me")
        try entryRepository.create(entry)
        let pasteDispatcher = FakePasteDispatcher(result: .dispatched)

        let service = ExecuteService(
            clipboardService: FakeClipboardWriter(success: true),
            pasteService: pasteDispatcher,
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: FakePermissionProvider(isAccessibilityGranted: false),
            targetApplicationProvider: { "com.google.Chrome" },
            currentFrontApplicationProvider: { "com.google.Chrome" }
        )

        service.execute(entry: entry, currentProjectId: defaultProject.id, triggerSource: .keyboardSubmit)
        let persisted = try waitForRecentExecutionLog(logRepository)

        XCTAssertEqual(persisted.result, Constants.ExecutionResult.clipboardOnly.rawValue)
        XCTAssertEqual(persisted.failureReason, Constants.ExecutionFailureReason.accessibilityNotGranted.rawValue)
        XCTAssertEqual(persisted.triggerSource, Constants.ExecutionTrigger.keyboardSubmit.rawValue)
        XCTAssertFalse(persisted.pasteAttempted)
        XCTAssertEqual(pasteDispatcher.attemptCount, 0)
    }

    @MainActor
    func testExecuteServiceLogsTargetRestoreMismatchBeforePaste() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        let entry = Entry(projectId: defaultProject.id, title: "Prompt", content: "Copy me")
        try entryRepository.create(entry)
        let pasteDispatcher = FakePasteDispatcher(result: .dispatched)

        let service = ExecuteService(
            clipboardService: FakeClipboardWriter(success: true),
            pasteService: pasteDispatcher,
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: FakePermissionProvider(isAccessibilityGranted: true),
            targetApplicationProvider: { "com.google.Chrome" },
            currentFrontApplicationProvider: { "com.apple.finder" }
        )

        service.execute(entry: entry, currentProjectId: defaultProject.id, triggerSource: .keyboardSubmit)
        let persisted = try waitForRecentExecutionLog(logRepository, timeout: 2)

        XCTAssertEqual(persisted.result, Constants.ExecutionResult.clipboardOnly.rawValue)
        XCTAssertEqual(persisted.failureReason, Constants.ExecutionFailureReason.targetAppNotRestored.rawValue)
        XCTAssertEqual(persisted.observedAppBundleId, "com.apple.finder")
        XCTAssertEqual(persisted.triggerSource, Constants.ExecutionTrigger.keyboardSubmit.rawValue)
        XCTAssertNotNil(persisted.targetAppRestoreDurationMs)
        XCTAssertEqual(pasteDispatcher.attemptCount, 0)
    }

    @MainActor
    func testExecuteServiceLogsPasteEventCreationFallback() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        let entry = Entry(projectId: defaultProject.id, title: "Prompt", content: "Copy me")
        try entryRepository.create(entry)
        let pasteDispatcher = FakePasteDispatcher(result: .eventCreationFailed)

        let service = ExecuteService(
            clipboardService: FakeClipboardWriter(success: true),
            pasteService: pasteDispatcher,
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: FakePermissionProvider(isAccessibilityGranted: true),
            targetApplicationProvider: { "com.google.Chrome" },
            currentFrontApplicationProvider: { "com.google.Chrome" }
        )

        service.execute(entry: entry, currentProjectId: defaultProject.id, triggerSource: .pointerClick)
        let persisted = try waitForRecentExecutionLog(logRepository)

        XCTAssertEqual(persisted.result, Constants.ExecutionResult.clipboardOnly.rawValue)
        XCTAssertEqual(persisted.failureReason, Constants.ExecutionFailureReason.pasteEventCreationFailed.rawValue)
        XCTAssertEqual(persisted.triggerSource, Constants.ExecutionTrigger.pointerClick.rawValue)
        XCTAssertTrue(persisted.pasteAttempted)
        XCTAssertFalse(persisted.pasteSuccess)
        XCTAssertEqual(pasteDispatcher.attemptCount, 1)
    }

    @MainActor
    func testExecuteServiceIgnoresConcurrentDuplicateExecutionRequests() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        let entry = Entry(projectId: defaultProject.id, title: "Prompt", content: "Copy me")
        try entryRepository.create(entry)
        let pasteDispatcher = FakePasteDispatcher(result: .dispatched)

        let service = ExecuteService(
            clipboardService: FakeClipboardWriter(success: true),
            pasteService: pasteDispatcher,
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: FakePermissionProvider(isAccessibilityGranted: true),
            targetApplicationProvider: { "com.google.Chrome" },
            currentFrontApplicationProvider: { "com.google.Chrome" }
        )

        service.execute(entry: entry, currentProjectId: defaultProject.id, triggerSource: .keyboardSubmit)
        service.execute(entry: entry, currentProjectId: defaultProject.id, triggerSource: .pointerClick)

        _ = try waitForRecentExecutionLog(logRepository)
        let recentLogs = try logRepository.fetchRecent(limit: 10)
        let persistedEntry = try XCTUnwrap(try entryRepository.fetchById(entry.id))

        XCTAssertEqual(recentLogs.count, 1)
        XCTAssertEqual(recentLogs.first?.triggerSource, Constants.ExecutionTrigger.keyboardSubmit.rawValue)
        XCTAssertEqual(pasteDispatcher.attemptCount, 1)
        XCTAssertEqual(persistedEntry.useCount, 1)
    }

    @MainActor
    func testHotkeyServiceInvokesToggleAndStartsTrace() {
        let registrar = FakeHotkeyRegistrar()
        let tracker = PanelOpenTracker()
        var toggleCount = 0

        let service = HotkeyService(
            onTogglePanel: { toggleCount += 1 },
            registrar: registrar,
            panelOpenTracker: tracker
        )

        service.start()
        registrar.trigger(.togglePanel)

        XCTAssertEqual(toggleCount, 1)
        XCTAssertNotNil(tracker.currentTrace)
    }

    @MainActor
    func testHotkeyServiceMigratesLegacyDefaultShortcut() {
        let registrar = FakeHotkeyRegistrar()
        let migrationDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let legacyShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
        let originalShortcut = KeyboardShortcuts.Name.togglePanel.shortcut
        defer {
            KeyboardShortcuts.setShortcut(originalShortcut, for: .togglePanel)
        }

        KeyboardShortcuts.setShortcut(legacyShortcut, for: .togglePanel)
        migrationDefaults.removeObject(forKey: "toggle_panel_shortcut_migrated_to_option_2")

        let service = HotkeyService(
            onTogglePanel: {},
            registrar: registrar,
            panelOpenTracker: nil,
            userDefaults: migrationDefaults
        )

        service.start()

        XCTAssertEqual(KeyboardShortcuts.Name.togglePanel.shortcut, KeyboardShortcuts.Shortcut(.two, modifiers: [.option]))
        XCTAssertTrue(migrationDefaults.bool(forKey: "toggle_panel_shortcut_migrated_to_option_2"))
    }

    @MainActor
    func testHotkeyServiceMigratesPreviousPreferredShortcutToNewDefault() {
        let registrar = FakeHotkeyRegistrar()
        let migrationDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let previousPreferredShortcut = KeyboardShortcuts.Shortcut(.p, modifiers: [.option, .shift])
        let originalShortcut = KeyboardShortcuts.Name.togglePanel.shortcut
        defer {
            KeyboardShortcuts.setShortcut(originalShortcut, for: .togglePanel)
        }

        KeyboardShortcuts.setShortcut(previousPreferredShortcut, for: .togglePanel)
        migrationDefaults.removeObject(forKey: "toggle_panel_shortcut_migrated_to_option_2")

        let service = HotkeyService(
            onTogglePanel: {},
            registrar: registrar,
            panelOpenTracker: nil,
            userDefaults: migrationDefaults
        )

        service.start()

        XCTAssertEqual(KeyboardShortcuts.Name.togglePanel.shortcut, KeyboardShortcuts.Shortcut(.two, modifiers: [.option]))
        XCTAssertTrue(migrationDefaults.bool(forKey: "toggle_panel_shortcut_migrated_to_option_2"))
    }

    func testAppLaunchCoordinatorReturnsNilWhenOnlyCurrentProcessExists() {
        XCTAssertNil(
            AppLaunchCoordinator.duplicateProcessIdentifier(
                currentProcessIdentifier: 42,
                runningProcessIdentifiers: [42]
            )
        )
    }

    func testAppLaunchCoordinatorReturnsExistingProcessWhenDuplicateExists() {
        XCTAssertEqual(
            AppLaunchCoordinator.duplicateProcessIdentifier(
                currentProcessIdentifier: 42,
                runningProcessIdentifiers: [42, 7, 7]
            ),
            7
        )
    }

    func testAppLaunchCoordinatorSkipsDuplicateCheckWhenOverrideIsEnabled() {
        XCTAssertTrue(
            AppLaunchCoordinator.shouldSkipDuplicateCheck(
                environment: [AppLaunchCoordinator.allowExistingInstanceEnvironmentKey: "1"]
            )
        )
        XCTAssertFalse(AppLaunchCoordinator.shouldSkipDuplicateCheck(environment: [:]))
    }

    func testAppLaunchCoordinatorReturnsNilWhenDuplicateExitsDuringSettleWindow() {
        var samples = [
            [pid_t(42), pid_t(7)],
            [pid_t(42)]
        ]

        let result = AppLaunchCoordinator.duplicateProcessIdentifierAfterSettling(
            currentProcessIdentifier: 42,
            timeoutMs: 20,
            pollIntervalMs: 1,
            runningProcessIdentifiersProvider: {
                let next = samples.first ?? [pid_t(42)]
                if samples.isEmpty == false {
                    samples.removeFirst()
                }
                return next
            },
            sleep: { _ in }
        )

        XCTAssertNil(result)
    }

    func testAppLaunchCoordinatorReturnsDuplicateWhenItPersistsPastSettleWindow() {
        let result = AppLaunchCoordinator.duplicateProcessIdentifierAfterSettling(
            currentProcessIdentifier: 42,
            timeoutMs: 0,
            pollIntervalMs: 1,
            runningProcessIdentifiersProvider: { [42, 7] },
            sleep: { _ in }
        )

        XCTAssertEqual(result, 7)
    }

    @MainActor
    func testPanelActivationPolicyPromotesAppWhenAnyWindowIsVisible() {
        XCTAssertEqual(
            PanelService.desiredActivationPolicy(isPanelVisible: true, isMainWindowVisible: false),
            .regular
        )
        XCTAssertEqual(
            PanelService.desiredActivationPolicy(isPanelVisible: false, isMainWindowVisible: true),
            .regular
        )
        XCTAssertEqual(
            PanelService.desiredActivationPolicy(isPanelVisible: false, isMainWindowVisible: false),
            .accessory
        )
    }

    @MainActor
    func testQuickPanelPrepareForPresentationResetsStateAndRequestsFocus() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        let currentProject = Project(name: "Current")
        try projectRepository.create(currentProject)
        try settingsRepository.setCurrentProjectId(currentProject.id)
        appState.currentProjectId = currentProject.id

        let executeService = ExecuteService(
            clipboardService: ClipboardService(),
            pasteService: PasteService(),
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: permissionService,
            targetApplicationProvider: { nil },
            currentFrontApplicationProvider: { nil }
        )

        let viewModel = QuickPanelViewModel(
            appState: appState,
            projectRepository: projectRepository,
            settingsRepository: settingsRepository,
            searchService: EntrySearchService(entryRepository: entryRepository),
            executeService: executeService,
            permissionService: permissionService,
            panelOpenTracker: PanelOpenTracker(),
            onClosePanel: {}
        )

        viewModel.query = "old-query"
        viewModel.selectedIndex = 4
        let previousFocusToken = viewModel.focusToken

        viewModel.prepareForPresentation()

        XCTAssertEqual(viewModel.query, "")
        XCTAssertEqual(viewModel.selectedIndex, 0)
        XCTAssertEqual(viewModel.currentProjectId, currentProject.id)
        XCTAssertEqual(viewModel.focusToken, previousFocusToken + 1)
        XCTAssertFalse(viewModel.isExecutionReady)
        XCTAssertFalse(viewModel.projects.isEmpty)
    }

    @MainActor
    func testMainWindowCurrentProjectUpdatesAfterSelectingNewCurrentProject() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let loginItemService = LoginItemService()
        let updaterService = UpdaterService()
        let storageMaintenanceService = StorageMaintenanceService(
            dbQueue: databaseManager.dbQueue,
            logRepository: logRepository,
            databaseURL: databaseManager.databaseURL
        )
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        let currentProject = Project(name: "Current")
        try projectRepository.create(currentProject)

        let viewModel = MainWindowViewModel(
            appState: appState,
            projectRepository: projectRepository,
            entryRepository: entryRepository,
            settingsRepository: settingsRepository,
            logRepository: logRepository,
            permissionService: permissionService,
            loginItemService: loginItemService,
            storageMaintenanceService: storageMaintenanceService,
            updaterService: updaterService,
            launchRecoveryReport: nil
        )

        viewModel.load()
        viewModel.selectedProjectId = currentProject.id
        viewModel.setCurrentProjectToSelected()

        XCTAssertEqual(viewModel.currentProjectId, currentProject.id)
        XCTAssertEqual(appState.currentProjectId, currentProject.id)
        XCTAssertEqual(try settingsRepository.getCurrentProjectId(), currentProject.id)
        XCTAssertEqual(viewModel.bannerMessage, "当前项目已切换为 \(currentProject.name)。")
    }

    @MainActor
    func testMainWindowSelectedEntryFollowsVisibleFilters() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let loginItemService = LoginItemService()
        let updaterService = UpdaterService()
        let storageMaintenanceService = StorageMaintenanceService(
            dbQueue: databaseManager.dbQueue,
            logRepository: logRepository,
            databaseURL: databaseManager.databaseURL
        )
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        let promptEntry = Entry(
            projectId: defaultProject.id,
            title: "Prompt Entry",
            content: "prompt",
            type: Constants.EntryType.prompt.rawValue
        )
        let codeEntry = Entry(
            projectId: defaultProject.id,
            title: "Code Entry",
            content: "code",
            type: Constants.EntryType.code.rawValue
        )
        try entryRepository.create(promptEntry)
        try entryRepository.create(codeEntry)

        let viewModel = MainWindowViewModel(
            appState: appState,
            projectRepository: projectRepository,
            entryRepository: entryRepository,
            settingsRepository: settingsRepository,
            logRepository: logRepository,
            permissionService: permissionService,
            loginItemService: loginItemService,
            storageMaintenanceService: storageMaintenanceService,
            updaterService: updaterService,
            launchRecoveryReport: nil
        )

        viewModel.load()
        let loadDeadline = Date().addingTimeInterval(1)
        while viewModel.entries.count != 2 && Date() < loadDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        viewModel.selectedEntryId = promptEntry.id
        XCTAssertEqual(viewModel.selectedEntry?.id, promptEntry.id)

        viewModel.toggleEntryKindFilter(.code)

        XCTAssertEqual(viewModel.displayedEntries.map(\.id), [codeEntry.id])
        XCTAssertEqual(viewModel.selectedEntry?.id, codeEntry.id)
    }

    @MainActor
    func testMainWindowDisplayedEntriesCacheUpdatesWhenSortModeChanges() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let loginItemService = LoginItemService()
        let updaterService = UpdaterService()
        let storageMaintenanceService = StorageMaintenanceService(
            dbQueue: databaseManager.dbQueue,
            logRepository: logRepository,
            databaseURL: databaseManager.databaseURL
        )
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let alphaEntry = Entry(
            id: "entry-alpha",
            projectId: defaultProject.id,
            title: "Alpha",
            content: "alpha",
            useCount: 1,
            lastUsedAt: now,
            updatedAt: now
        )
        let zetaEntry = Entry(
            id: "entry-zeta",
            projectId: defaultProject.id,
            title: "Zeta",
            content: "zeta",
            useCount: 10,
            lastUsedAt: now,
            updatedAt: now
        )
        try entryRepository.create(alphaEntry)
        try entryRepository.create(zetaEntry)

        let viewModel = MainWindowViewModel(
            appState: appState,
            projectRepository: projectRepository,
            entryRepository: entryRepository,
            settingsRepository: settingsRepository,
            logRepository: logRepository,
            permissionService: permissionService,
            loginItemService: loginItemService,
            storageMaintenanceService: storageMaintenanceService,
            updaterService: updaterService,
            launchRecoveryReport: nil
        )

        viewModel.load()
        let loadDeadline = Date().addingTimeInterval(1)
        while viewModel.displayedEntries.count != 2 && Date() < loadDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(viewModel.displayedEntries.map(\.id), [zetaEntry.id, alphaEntry.id])

        viewModel.entrySortMode = .alpha

        XCTAssertEqual(viewModel.displayedEntries.map(\.id), [alphaEntry.id, zetaEntry.id])
    }

    @MainActor
    func testQuickPanelClearsResultsWhileAsyncSearchIsPending() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        try entryRepository.create(Entry(projectId: defaultProject.id, title: "Alpha", content: "Alpha body"))
        try entryRepository.create(Entry(projectId: defaultProject.id, title: "Beta", content: "Beta body"))

        let executeService = ExecuteService(
            clipboardService: ClipboardService(),
            pasteService: PasteService(),
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: permissionService,
            targetApplicationProvider: { nil },
            currentFrontApplicationProvider: { nil }
        )

        let viewModel = QuickPanelViewModel(
            appState: appState,
            projectRepository: projectRepository,
            settingsRepository: settingsRepository,
            searchService: EntrySearchService(entryRepository: entryRepository),
            executeService: executeService,
            permissionService: permissionService,
            panelOpenTracker: PanelOpenTracker(),
            onClosePanel: {}
        )

        viewModel.prepareForPresentation()
        let loadDeadline = Date().addingTimeInterval(1)
        while viewModel.entries.count != 2 && Date() < loadDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        XCTAssertEqual(viewModel.entries.count, 2)

        viewModel.query = "Alpha"

        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertNil(viewModel.selectedEntry)
    }

    @MainActor
    func testQuickPanelPointerClickExecutesVisibleEntryImmediately() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        let firstEntry = Entry(
            id: "entry-first",
            projectId: defaultProject.id,
            title: "First",
            content: "first body",
            sortOrder: 20
        )
        let secondEntry = Entry(
            id: "entry-second",
            projectId: defaultProject.id,
            title: "Second",
            content: "second body",
            sortOrder: 10
        )
        try entryRepository.create(firstEntry)
        try entryRepository.create(secondEntry)

        let pasteDispatcher = FakePasteDispatcher(result: .dispatched)
        let executeService = ExecuteService(
            clipboardService: FakeClipboardWriter(success: true),
            pasteService: pasteDispatcher,
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: FakePermissionProvider(isAccessibilityGranted: true),
            targetApplicationProvider: { nil },
            currentFrontApplicationProvider: { nil }
        )

        let viewModel = QuickPanelViewModel(
            appState: appState,
            projectRepository: projectRepository,
            settingsRepository: settingsRepository,
            searchService: EntrySearchService(entryRepository: entryRepository),
            executeService: executeService,
            permissionService: permissionService,
            panelOpenTracker: PanelOpenTracker(),
            onClosePanel: {}
        )

        viewModel.prepareForPresentation()
        let loadDeadline = Date().addingTimeInterval(3)
        while viewModel.entries.count != 2 && Date() < loadDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(Set(viewModel.entries.map(\.id)), Set([firstEntry.id, secondEntry.id]))
        XCTAssertFalse(viewModel.isExecutionReady)

        let secondEntryIndex = try XCTUnwrap(viewModel.entries.firstIndex { $0.id == secondEntry.id })
        viewModel.executeEntry(at: secondEntryIndex, triggerSource: .pointerClick)
        let persisted = try waitForRecentExecutionLog(logRepository)

        XCTAssertEqual(persisted.entryId, secondEntry.id)
        XCTAssertEqual(persisted.triggerSource, Constants.ExecutionTrigger.pointerClick.rawValue)
        XCTAssertEqual(persisted.result, Constants.ExecutionResult.success.rawValue)
        XCTAssertEqual(pasteDispatcher.attemptCount, 1)
    }

    func testQuickPanelRankingRespectsManualSortOrderBeforeUsage() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let highUsageEntry = Entry(
            id: "high-usage",
            projectId: "project-current",
            title: "High Usage",
            content: "x",
            sortOrder: 0,
            useCount: 99,
            lastUsedAt: now,
            updatedAt: now
        )
        let manualTopEntry = Entry(
            id: "manual-top",
            projectId: "project-current",
            title: "Manual Top",
            content: "x",
            sortOrder: 10,
            useCount: 1,
            lastUsedAt: now.addingTimeInterval(-60),
            updatedAt: now.addingTimeInterval(-60)
        )

        let sorted = QuickPanelViewModel.applyPanelRankingSort(
            [highUsageEntry, manualTopEntry],
            currentProjectId: "project-current"
        )

        XCTAssertEqual(sorted.map(\.id), [manualTopEntry.id, highUsageEntry.id])
    }

    @MainActor
    func testQuickPanelDoesNotUnlockExecutionWhenSearchFieldFocusFails() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        let executeService = ExecuteService(
            clipboardService: ClipboardService(),
            pasteService: PasteService(),
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: permissionService,
            targetApplicationProvider: { nil },
            currentFrontApplicationProvider: { nil }
        )

        let viewModel = QuickPanelViewModel(
            appState: appState,
            projectRepository: projectRepository,
            settingsRepository: settingsRepository,
            searchService: EntrySearchService(entryRepository: entryRepository),
            executeService: executeService,
            permissionService: permissionService,
            panelOpenTracker: PanelOpenTracker(),
            onClosePanel: {}
        )

        viewModel.prepareForPresentation()
        viewModel.handleSearchFieldFocus(PanelFocusResult(token: viewModel.focusToken, succeeded: false))

        RunLoop.main.run(until: Date().addingTimeInterval(0.12))

        XCTAssertFalse(viewModel.isExecutionReady)
    }

    @MainActor
    func testQuickPanelExecutionUnlocksAfterManualFocusRecovery() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        let executeService = ExecuteService(
            clipboardService: ClipboardService(),
            pasteService: PasteService(),
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: permissionService,
            targetApplicationProvider: { nil },
            currentFrontApplicationProvider: { nil }
        )

        let viewModel = QuickPanelViewModel(
            appState: appState,
            projectRepository: projectRepository,
            settingsRepository: settingsRepository,
            searchService: EntrySearchService(entryRepository: entryRepository),
            executeService: executeService,
            permissionService: permissionService,
            panelOpenTracker: PanelOpenTracker(),
            onClosePanel: {}
        )

        viewModel.prepareForPresentation()
        let focusToken = viewModel.focusToken
        viewModel.handleSearchFieldFocus(PanelFocusResult(token: focusToken, succeeded: false))
        viewModel.handleSearchFieldFocus(
            PanelFocusResult(token: focusToken, succeeded: true, attempt: Constants.panelFocusMaxAttempts)
        )

        RunLoop.main.run(until: Date().addingTimeInterval(0.12))

        XCTAssertTrue(viewModel.isExecutionReady)
    }

    @MainActor
    func testQuickPanelExecutionUnlocksAfterFocusResolution() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        let executeService = ExecuteService(
            clipboardService: ClipboardService(),
            pasteService: PasteService(),
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: permissionService,
            targetApplicationProvider: { nil },
            currentFrontApplicationProvider: { nil }
        )

        let viewModel = QuickPanelViewModel(
            appState: appState,
            projectRepository: projectRepository,
            settingsRepository: settingsRepository,
            searchService: EntrySearchService(entryRepository: entryRepository),
            executeService: executeService,
            permissionService: permissionService,
            panelOpenTracker: PanelOpenTracker(),
            onClosePanel: {}
        )

        viewModel.prepareForPresentation()
        XCTAssertFalse(viewModel.isExecutionReady)

        let expectation = XCTestExpectation(description: "execution unlock")
        viewModel.handleSearchFieldFocus(PanelFocusResult(token: viewModel.focusToken, succeeded: true))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(viewModel.isExecutionReady)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1)
    }

    @MainActor
    func testTargetApplicationRestoreMismatchRequiresConfirmedDifferentBundleId() {
        XCTAssertFalse(
            ExecuteService.isTargetApplicationRestoreMismatch(
                expectedBundleId: "com.example.target",
                observedBundleId: nil
            )
        )
        XCTAssertFalse(
            ExecuteService.isTargetApplicationRestoreMismatch(
                expectedBundleId: nil,
                observedBundleId: "com.example.target"
            )
        )
        XCTAssertTrue(
            ExecuteService.isTargetApplicationRestoreMismatch(
                expectedBundleId: "com.example.target",
                observedBundleId: "com.example.other"
            )
        )
    }

    @MainActor
    func testQuickPanelRetryFocusAfterActivationStabilizedRequestsAnotherFocusCycle() throws {
        let databaseManager = try makeDatabaseManager()
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
        let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let permissionService = PermissionService()
        let appState = AppState()
        let defaultProject = try XCTUnwrap(projectRepository.fetchDefault())
        appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

        let executeService = ExecuteService(
            clipboardService: ClipboardService(),
            pasteService: PasteService(),
            entryRepository: entryRepository,
            logRepository: logRepository,
            permissionService: permissionService,
            targetApplicationProvider: { nil },
            currentFrontApplicationProvider: { nil }
        )

        let viewModel = QuickPanelViewModel(
            appState: appState,
            projectRepository: projectRepository,
            settingsRepository: settingsRepository,
            searchService: EntrySearchService(entryRepository: entryRepository),
            executeService: executeService,
            permissionService: permissionService,
            panelOpenTracker: PanelOpenTracker(),
            onClosePanel: {}
        )

        viewModel.prepareForPresentation()
        let initialFocusToken = viewModel.focusToken
        viewModel.handleSearchFieldFocus(PanelFocusResult(token: initialFocusToken, succeeded: true))
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertTrue(viewModel.isExecutionReady)

        viewModel.retryFocusAfterActivationStabilized()

        XCTAssertEqual(viewModel.focusToken, initialFocusToken + 1)
        XCTAssertFalse(viewModel.isExecutionReady)
    }

    @MainActor
    func testPanelOpenTrackerRecordsDurations() throws {
        let tracker = PanelOpenTracker()

        tracker.markHotkeyTriggered()
        tracker.markPanelShown()
        tracker.markSearchFieldFocused(PanelFocusResult(token: 1, succeeded: true))

        let trace = try XCTUnwrap(tracker.currentTrace)
        XCTAssertNotNil(trace.hotkeyToPanelShownMs)
        XCTAssertNotNil(trace.hotkeyToSearchFieldFocusedMs)
    }

    @MainActor
    func testPanelActivationActionRetriesUntilMaxAttempts() {
        let unstableSnapshot = PanelActivationSnapshot(
            appIsActive: false,
            panelIsVisible: true,
            panelIsKey: false
        )
        let stableSnapshot = PanelActivationSnapshot(
            appIsActive: true,
            panelIsVisible: true,
            panelIsKey: true
        )

        XCTAssertEqual(
            PanelService.activationAction(snapshot: unstableSnapshot, attempt: 0, maxAttempts: 3),
            .retry(nextAttempt: 1)
        )
        XCTAssertEqual(
            PanelService.activationAction(snapshot: unstableSnapshot, attempt: 3, maxAttempts: 3),
            .failed
        )
        XCTAssertEqual(
            PanelService.activationAction(snapshot: stableSnapshot, attempt: 1, maxAttempts: 3),
            .stable
        )
    }

    @MainActor
    func testPanelVisibilityCoordinatorTransitions() {
        let coordinator = PanelVisibilityCoordinator()

        XCTAssertEqual(coordinator.toggleAction(), .show)
        XCTAssertTrue(coordinator.beginShow())
        coordinator.finishShow()
        XCTAssertEqual(coordinator.state, .visible)
        XCTAssertEqual(coordinator.toggleAction(), .hide)
        XCTAssertTrue(coordinator.beginHide())
        coordinator.finishHide()
        XCTAssertEqual(coordinator.state, .hidden)
    }

    func testQuickPanelWindowCanBecomeKeyAndMain() {
        let panel = QuickPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )

        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.canBecomeMain)
    }

    @MainActor
    func testQuickPanelHostingViewAcceptsFirstMouse() {
        let hostingView = QuickPanelHostingView(rootView: EmptyView())

        XCTAssertTrue(hostingView.acceptsFirstMouse(for: nil))
    }

    func testDatabaseManagerRecoversFromCorruptedStore() throws {
        let brokenDatabaseURL = try makeTemporaryDatabaseURL()

        try Data("not a sqlite database".utf8).write(to: brokenDatabaseURL)

        let databaseManager = try DatabaseManager(url: brokenDatabaseURL)
        let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)

        XCTAssertNotNil(databaseManager.launchRecoveryReport)
        XCTAssertNotNil(try projectRepository.fetchDefault())
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: databaseManager.launchRecoveryReport?.quarantinedFilesDirectoryURL
                    .appendingPathComponent(brokenDatabaseURL.lastPathComponent)
                    .path ?? ""
            )
        )
    }

    func testDatabaseManagerDoesNotQuarantineStoreWhenMigrationFails() throws {
        let databaseURL = try makeTemporaryDatabaseURL()

        let queue = try DatabaseQueue(path: databaseURL.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE execution_logs (
                    id TEXT PRIMARY KEY NOT NULL,
                    entry_id TEXT NOT NULL,
                    project_id TEXT NOT NULL,
                    front_app_bundle_id TEXT,
                    observed_app_bundle_id TEXT,
                    has_accessibility INTEGER NOT NULL,
                    clipboard_success INTEGER NOT NULL,
                    paste_attempted INTEGER NOT NULL,
                    paste_success INTEGER NOT NULL,
                    result TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """)
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT PRIMARY KEY NOT NULL)")
            try db.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES (?)", arguments: ["v1_create_tables"])
        }

        XCTAssertThrowsError(try DatabaseManager(url: databaseURL)) { error in
            guard case DatabaseManager.InitializationError.migrationFailedPreservingStore = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: Constants.recoveryDirectory(for: databaseURL).path))
    }

    func testDatabaseManagerDoesNotQuarantineStoreWhenDatabaseIsLocked() throws {
        let databaseURL = try makeTemporaryDatabaseURL()

        var lockingConnection: OpaquePointer?
        defer {
            if let lockingConnection {
                sqlite3_exec(lockingConnection, "ROLLBACK TRANSACTION", nil, nil, nil)
                sqlite3_close(lockingConnection)
            }
        }
        XCTAssertEqual(sqlite3_open(databaseURL.path, &lockingConnection), SQLITE_OK)
        let sqlite = try XCTUnwrap(lockingConnection)
        var errorMessage: UnsafeMutablePointer<CChar>?
        let beginResult = sqlite3_exec(sqlite, "BEGIN EXCLUSIVE TRANSACTION", nil, nil, &errorMessage)
        let beginError = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(errorMessage)
        XCTAssertEqual(beginResult, SQLITE_OK, beginError)

        XCTAssertThrowsError(try DatabaseManager(url: databaseURL)) { error in
            guard case DatabaseManager.InitializationError.storeBusyPreservingStore = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: Constants.recoveryDirectory(for: databaseURL).path))
    }

    func testStorageMaintenanceKeepsManualBackupsBeyondAutomaticRetention() throws {
        let databaseManager = try makeDatabaseManager()
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let maintenanceService = StorageMaintenanceService(
            dbQueue: databaseManager.dbQueue,
            logRepository: logRepository,
            databaseURL: databaseManager.databaseURL
        )

        let backupTarget = Constants.automaticBackupRetentionCount + 2
        for _ in 0..<backupTarget {
            _ = try maintenanceService.createManualBackup()
        }

        let snapshot = try maintenanceService.healthSnapshot()
        XCTAssertEqual(snapshot.backupCount, backupTarget)
        XCTAssertNotNil(snapshot.latestBackupURL)
    }

    func testLaunchMaintenanceDoesNotCreateExtraBackupAfterRecentManualBackup() throws {
        let databaseManager = try makeDatabaseManager()
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let maintenanceService = StorageMaintenanceService(
            dbQueue: databaseManager.dbQueue,
            logRepository: logRepository,
            databaseURL: databaseManager.databaseURL
        )

        let manualBackupURL = try maintenanceService.createManualBackup()
        let beforeSnapshot = try maintenanceService.healthSnapshot()

        _ = try maintenanceService.performLaunchMaintenance()

        let afterSnapshot = try maintenanceService.healthSnapshot()
        XCTAssertEqual(afterSnapshot.backupCount, beforeSnapshot.backupCount)
        XCTAssertEqual(afterSnapshot.latestBackupURL?.lastPathComponent, manualBackupURL.lastPathComponent)
    }

    func testFreshDatabaseDoesNotCreateUnusedTagsIndex() throws {
        let databaseManager = try makeDatabaseManager()
        let indexNames = try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA index_list('entries')")
                .compactMap { row in row["name"] as String? }
        }

        XCTAssertFalse(indexNames.contains("index_entries_on_tags"))
    }

    func testMigrationsDropLegacyTagsIndex() throws {
        let databaseURL = try makeTemporaryDatabaseURL()

        let queue = try DatabaseQueue(path: databaseURL.path)
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE entries (
                    id TEXT PRIMARY KEY NOT NULL,
                    project_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    content TEXT NOT NULL,
                    type TEXT NOT NULL,
                    is_pinned INTEGER NOT NULL,
                    sort_order INTEGER NOT NULL,
                    use_count INTEGER NOT NULL,
                    last_used_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    tags TEXT NOT NULL DEFAULT '[]'
                )
                """)
            try db.execute(sql: "CREATE INDEX index_entries_on_tags ON entries(tags)")
            try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT PRIMARY KEY NOT NULL)")
            for identifier in [
                "v1_create_tables",
                "v2_execution_log_diagnostics",
                "v3_execution_log_interaction_diagnostics",
                "v4_entry_tags"
            ] {
                try db.execute(
                    sql: "INSERT INTO grdb_migrations(identifier) VALUES (?)",
                    arguments: [identifier]
                )
            }
        }

        let databaseManager = try DatabaseManager(url: databaseURL)
        let indexNames = try databaseManager.dbQueue.read { db in
            try Row.fetchAll(db, sql: "PRAGMA index_list('entries')")
                .compactMap { row in row["name"] as String? }
        }

        XCTAssertFalse(indexNames.contains("index_entries_on_tags"))
    }

    func testLogCleanupRemovesOnlyExpiredEntries() throws {
        let databaseManager = try makeDatabaseManager()
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)

        try logRepository.record(
            ExecutionLog(
                entryId: "recent",
                projectId: "project-1",
                hasAccessibility: true,
                clipboardSuccess: true,
                pasteAttempted: true,
                pasteSuccess: true,
                result: Constants.ExecutionResult.success.rawValue,
                createdAt: Date()
            )
        )
        try logRepository.record(
            ExecutionLog(
                entryId: "expired",
                projectId: "project-1",
                hasAccessibility: true,
                clipboardSuccess: true,
                pasteAttempted: false,
                pasteSuccess: false,
                result: Constants.ExecutionResult.clipboardOnly.rawValue,
                createdAt: Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? .distantPast
            )
        )

        try logRepository.cleanup(olderThanDays: 30)
        let remaining = try logRepository.fetchRecent(limit: 10)

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.entryId, "recent")
    }

    func testHealthSummaryCountsResultsAcrossOutcomes() throws {
        let databaseManager = try makeDatabaseManager()
        let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
        let now = Date()

        try logRepository.record(
            ExecutionLog(
                entryId: "success",
                projectId: "project-1",
                hasAccessibility: true,
                clipboardSuccess: true,
                pasteAttempted: true,
                pasteSuccess: true,
                result: Constants.ExecutionResult.success.rawValue,
                createdAt: now
            )
        )
        try logRepository.record(
            ExecutionLog(
                entryId: "clipboard-only",
                projectId: "project-1",
                hasAccessibility: false,
                clipboardSuccess: true,
                pasteAttempted: false,
                pasteSuccess: false,
                result: Constants.ExecutionResult.clipboardOnly.rawValue,
                createdAt: now
            )
        )
        try logRepository.record(
            ExecutionLog(
                entryId: "failed",
                projectId: "project-1",
                hasAccessibility: true,
                clipboardSuccess: false,
                pasteAttempted: false,
                pasteSuccess: false,
                result: Constants.ExecutionResult.failed.rawValue,
                createdAt: now
            )
        )

        let summary = try logRepository.fetchHealthSummary(
            since: Calendar.current.date(byAdding: .day, value: -7, to: now) ?? .distantPast
        )

        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertEqual(summary.successCount, 1)
        XCTAssertEqual(summary.clipboardOnlyCount, 1)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertNotNil(summary.latestExecutionAt)
        XCTAssertNotNil(summary.latestFailureAt)
    }

    func testLibraryJSONExportImportRoundTripsProjectsAndEntries() throws {
        let sourceDatabase = try makeDatabaseManager()
        let sourceProjects = ProjectRepository(dbQueue: sourceDatabase.dbQueue)
        let sourceEntries = EntryRepository(dbQueue: sourceDatabase.dbQueue)
        let sourceLogs = LogRepository(dbQueue: sourceDatabase.dbQueue)
        let sourceMaintenance = StorageMaintenanceService(
            dbQueue: sourceDatabase.dbQueue,
            logRepository: sourceLogs,
            databaseURL: sourceDatabase.databaseURL
        )
        let project = Project(id: "project-json", name: "JSON Project")
        let entry = Entry(
            id: "entry-json",
            projectId: project.id,
            title: "JSON Prompt",
            content: "Write a release note.",
            isPinned: true,
            useCount: 7,
            tags: ["release", "notes"]
        )
        try sourceProjects.create(project)
        try sourceEntries.create(entry)

        let exportURL = try makeTemporaryDatabaseURL()
            .deletingLastPathComponent()
            .appendingPathComponent("library.json")
        let sourceService = LibraryTransferService(
            projectRepository: sourceProjects,
            entryRepository: sourceEntries,
            storageMaintenanceService: sourceMaintenance
        )
        try sourceService.exportJSON(to: exportURL)

        let targetDatabase = try makeDatabaseManager()
        let targetProjects = ProjectRepository(dbQueue: targetDatabase.dbQueue)
        let targetEntries = EntryRepository(dbQueue: targetDatabase.dbQueue)
        let targetLogs = LogRepository(dbQueue: targetDatabase.dbQueue)
        let targetMaintenance = StorageMaintenanceService(
            dbQueue: targetDatabase.dbQueue,
            logRepository: targetLogs,
            databaseURL: targetDatabase.databaseURL
        )
        let targetService = LibraryTransferService(
            projectRepository: targetProjects,
            entryRepository: targetEntries,
            storageMaintenanceService: targetMaintenance
        )

        let summary = try targetService.importJSON(from: exportURL)
        let importedProject = try XCTUnwrap(targetProjects.fetchById(project.id))
        let importedEntry = try XCTUnwrap(targetEntries.fetchById(entry.id))

        XCTAssertEqual(summary.projectsCreated, 1)
        XCTAssertEqual(summary.entriesCreated, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(summary.backupURL).path))
        XCTAssertEqual(importedProject.name, project.name)
        XCTAssertEqual(importedEntry.title, entry.title)
        XCTAssertEqual(importedEntry.projectId, project.id)
        XCTAssertEqual(importedEntry.tags, ["release", "notes"])
    }

    func testLibraryJSONImportRollsBackPartialWritesWhenEntryInsertFails() throws {
        let targetDatabase = try makeDatabaseManager()
        let targetProjects = ProjectRepository(dbQueue: targetDatabase.dbQueue)
        let targetEntries = EntryRepository(dbQueue: targetDatabase.dbQueue)
        let targetLogs = LogRepository(dbQueue: targetDatabase.dbQueue)
        let targetMaintenance = StorageMaintenanceService(
            dbQueue: targetDatabase.dbQueue,
            logRepository: targetLogs,
            databaseURL: targetDatabase.databaseURL
        )
        let targetService = LibraryTransferService(
            projectRepository: targetProjects,
            entryRepository: targetEntries,
            storageMaintenanceService: targetMaintenance
        )
        try targetDatabase.dbQueue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_test_entry_import
                BEFORE INSERT ON entries
                WHEN new.id = 'entry-fail'
                BEGIN
                    SELECT RAISE(ABORT, 'forced import failure');
                END
                """)
        }

        let importedProject = Project(id: "project-rollback", name: "Rollback Project")
        let failingEntry = Entry(
            id: "entry-fail",
            projectId: importedProject.id,
            title: "Should Fail",
            content: "This insert is blocked by the test trigger."
        )
        let payload = PromptPanelLibraryExport(
            formatVersion: PromptPanelLibraryExport.currentFormatVersion,
            exportedAt: Date(),
            projects: [importedProject],
            entries: [failingEntry]
        )
        let importURL = try makeTemporaryDatabaseURL()
            .deletingLastPathComponent()
            .appendingPathComponent("rollback-import.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(payload).write(to: importURL)

        XCTAssertThrowsError(try targetService.importJSON(from: importURL))

        XCTAssertNil(try targetProjects.fetchById(importedProject.id))
        XCTAssertNil(try targetEntries.fetchById(failingEntry.id))
    }

    func testLibraryMarkdownExportImportRoundTripsPromptContent() throws {
        let sourceDatabase = try makeDatabaseManager()
        let sourceProjects = ProjectRepository(dbQueue: sourceDatabase.dbQueue)
        let sourceEntries = EntryRepository(dbQueue: sourceDatabase.dbQueue)
        let sourceLogs = LogRepository(dbQueue: sourceDatabase.dbQueue)
        let sourceMaintenance = StorageMaintenanceService(
            dbQueue: sourceDatabase.dbQueue,
            logRepository: sourceLogs,
            databaseURL: sourceDatabase.databaseURL
        )
        let project = Project(id: "project-markdown", name: "Markdown Project")
        let entry = Entry(
            id: "entry-markdown",
            projectId: project.id,
            title: "Markdown Prompt",
            content: "Keep this code fence:\n```swift\nprint(\"ok\")\n```",
            type: Constants.EntryType.prompt.rawValue,
            tags: ["markdown"]
        )
        try sourceProjects.create(project)
        try sourceEntries.create(entry)

        let exportURL = try makeTemporaryDatabaseURL()
            .deletingLastPathComponent()
            .appendingPathComponent("library.md")
        let sourceService = LibraryTransferService(
            projectRepository: sourceProjects,
            entryRepository: sourceEntries,
            storageMaintenanceService: sourceMaintenance
        )
        try sourceService.exportMarkdown(to: exportURL)

        let targetDatabase = try makeDatabaseManager()
        let targetProjects = ProjectRepository(dbQueue: targetDatabase.dbQueue)
        let targetEntries = EntryRepository(dbQueue: targetDatabase.dbQueue)
        let targetLogs = LogRepository(dbQueue: targetDatabase.dbQueue)
        let targetMaintenance = StorageMaintenanceService(
            dbQueue: targetDatabase.dbQueue,
            logRepository: targetLogs,
            databaseURL: targetDatabase.databaseURL
        )
        let targetService = LibraryTransferService(
            projectRepository: targetProjects,
            entryRepository: targetEntries,
            storageMaintenanceService: targetMaintenance
        )

        let summary = try targetService.importMarkdown(from: exportURL)
        let importedEntry = try XCTUnwrap(targetEntries.fetchById(entry.id))

        XCTAssertEqual(summary.projectsCreated, 1)
        XCTAssertEqual(summary.entriesCreated, 1)
        XCTAssertEqual(try XCTUnwrap(targetProjects.fetchById(project.id)).name, project.name)
        XCTAssertEqual(importedEntry.content, entry.content)
        XCTAssertEqual(importedEntry.type, Constants.EntryType.prompt.rawValue)
        XCTAssertEqual(importedEntry.tags, ["markdown"])
    }

    func testReleaseReadinessBuildOnlyModeDoesNotRequireTestRunner() throws {
        let script = try readRepositoryText("scripts/release-readiness.sh")

        XCTAssertTrue(script.contains("Running swift test in build-only validation mode"))
        XCTAssertTrue(script.contains("swift build --package-path \"$PACKAGE_ROOT\" --build-tests"))
    }

    func testReleaseReadinessExercisesBackupRestoreDrill() throws {
        let script = try readRepositoryText("scripts/release-readiness.sh")

        XCTAssertTrue(script.contains("Verifying backup restore path"))
        XCTAssertTrue(script.contains("\"${REPO_ROOT}/scripts/restore-backup.sh\" --target-dir \"$RESTORE_APP_SUPPORT_DIR\" \"$LATEST_BACKUP_PATH\""))
        XCTAssertTrue(script.contains("Restored database integrity check failed"))
    }

    func testReleaseReadinessVerifiesArchiveForBuiltAppVersion() throws {
        let script = try readRepositoryText("scripts/release-readiness.sh")

        XCTAssertTrue(script.contains("CFBundleShortVersionString"))
        XCTAssertTrue(script.contains("CFBundleVersion"))
        XCTAssertTrue(script.contains("ZIP_PATH=\"${OUTPUT_ROOT}/PromptPanel-${SHORT_VERSION}+${BUILD_VERSION}-macos.zip\""))
        XCTAssertFalse(script.contains("ZIP_MATCHES=("))
    }

    func testBuildAppRejectsPartialSparkleConfiguration() throws {
        let script = try readRepositoryText("scripts/build-app.sh")

        XCTAssertTrue(script.contains("Sparkle feed URL was provided, but SUPublicEDKey is missing."))
        XCTAssertTrue(script.contains("Sparkle public key was provided, but SUFeedURL is missing."))
    }

    func testBuildAppStripsExtendedAttributesBeforeSigning() throws {
        let script = try readRepositoryText("scripts/build-app.sh")

        let stripCallRange = try XCTUnwrap(script.range(of: "strip_extended_attributes \"$APP_PATH\""))
        let appSignRange = try XCTUnwrap(script.range(of: "codesign_path \"${APP_PATH}\" runtime on"))

        XCTAssertTrue(script.contains("xattr -cr \"$target_path\""))
        XCTAssertLessThan(stripCallRange.lowerBound, appSignRange.lowerBound)
    }

    func testRestoreBackupStagesValidatedCopyBeforeMovingCurrentDatabase() throws {
        let script = try readRepositoryText("scripts/restore-backup.sh")

        let stageCopyRange = try XCTUnwrap(script.range(of: "cp \"$BACKUP_SOURCE\" \"$STAGED_DATABASE_PATH\""))
        let preserveCurrentRange = try XCTUnwrap(script.range(of: "mv \"$SOURCE_PATH\" \"${RECOVERY_DIR}/\""))
        let restoreStagedRange = try XCTUnwrap(script.range(of: "mv \"$STAGED_DATABASE_PATH\" \"$DATABASE_PATH\""))

        XCTAssertTrue(script.contains("STAGING_DIR=\"${TARGET_APP_SUPPORT_DIR}/Recovery/manual-restore-staging-${TIMESTAMP}\""))
        XCTAssertTrue(script.contains("STAGED_INTEGRITY_RESULT="))
        XCTAssertFalse(script.contains("cp \"$BACKUP_SOURCE\" \"$DATABASE_PATH\""))
        XCTAssertLessThan(stageCopyRange.lowerBound, preserveCurrentRange.lowerBound)
        XCTAssertLessThan(preserveCurrentRange.lowerBound, restoreStagedRange.lowerBound)
    }

    private func waitForRecentExecutionLog(
        _ logRepository: LogRepository,
        timeout: TimeInterval = 1
    ) throws -> ExecutionLog {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let log = try logRepository.fetchRecent(limit: 1).first {
                return log
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        throw NSError(domain: "PromptPanelTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Timed out waiting for execution log"
        ])
    }
}

#elseif canImport(Testing)
import Testing

@Test
func constantsExist() {
    #expect(Constants.appName == "PromptPanel")
    #expect(Constants.bundleIdentifier == "com.promptpanel.app")
    #expect(Constants.defaultProjectName == "通用项目")
    #expect(Constants.panelWindowSize.width == Constants.panelContentSize.width + Constants.panelContentInsets.left + Constants.panelContentInsets.right)
    #expect(Constants.panelWindowSize.height == Constants.panelContentSize.height + Constants.panelContentInsets.top + Constants.panelContentInsets.bottom)
}

@Test
func databaseSeedsDefaultProjectAndCurrentProject() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)

    let defaultProject = try #require(projectRepository.fetchDefault())
    #expect(defaultProject.name == Constants.defaultProjectName)
    #expect(try settingsRepository.getCurrentProjectId() == defaultProject.id)
}

@Test
func projectsFetchAllKeepsDefaultProjectFirstThenSortsByName() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let defaultProject = try #require(projectRepository.fetchDefault())

    try projectRepository.create(Project(name: "000 Alpha"))
    try projectRepository.create(Project(name: "ZZZ Later"))

    let projects = try projectRepository.fetchAll()

    #expect(projects.first?.id == defaultProject.id)
    #expect(projects.dropFirst().map(\.name) == ["000 Alpha", "ZZZ Later"])
}

@Test
func resolveCurrentProjectSelectionFallsBackToDefaultWhenPersistedProjectIsDangling() throws {
    let defaultProjectId = UUID().uuidString

    let resolution = try AppDelegate.resolveCurrentProjectSelection(
        persistedCurrentProjectId: "missing-project",
        defaultProjectId: defaultProjectId,
        currentProjectExists: { $0 == defaultProjectId }
    )

    #expect(resolution.projectId == defaultProjectId)
    #expect(resolution.needsPersistence)
    #expect(resolution.repairReason != nil)
}

@Test
func resolveCurrentProjectSelectionKeepsValidPersistedProject() throws {
    let currentProjectId = UUID().uuidString
    let defaultProjectId = UUID().uuidString

    let resolution = try AppDelegate.resolveCurrentProjectSelection(
        persistedCurrentProjectId: currentProjectId,
        defaultProjectId: defaultProjectId,
        currentProjectExists: { $0 == currentProjectId }
    )

    #expect(resolution.projectId == currentProjectId)
    #expect(!resolution.needsPersistence)
    #expect(resolution.repairReason == nil)
}

@Test
func panelContentSizeSettingRoundTripsWithNormalization() throws {
    let databaseManager = try makeDatabaseManager()
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)

    #expect(try settingsRepository.getPanelContentSize() == Constants.panelContentSize)

    try settingsRepository.setPanelContentSize(NSSize(width: 820, height: 520))
    #expect(try settingsRepository.getPanelContentSize() == NSSize(width: 820, height: 520))

    try settingsRepository.setPanelContentSize(NSSize(width: 2000, height: 100))
    #expect(try settingsRepository.getPanelContentSize() == NSSize(width: Constants.panelMaxContentSize.width, height: Constants.panelMinContentSize.height))
}

@Test
func panelWindowOriginSettingRoundTrips() throws {
    let databaseManager = try makeDatabaseManager()
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)

    #expect(try settingsRepository.getPanelWindowOrigin() == nil)

    try settingsRepository.setPanelWindowOrigin(NSPoint(x: 321.4, y: 456.6))
    #expect(try settingsRepository.getPanelWindowOrigin() == NSPoint(x: 321, y: 457))
}

@Test
func mixedEntriesPreferCurrentProjectWhenSortKeysEqual() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)

    let defaultProject = try #require(projectRepository.fetchDefault())
    let currentProject = Project(name: "Current")
    try projectRepository.create(currentProject)

    let now = Date()
    try entryRepository.create(
        Entry(
            projectId: defaultProject.id,
            title: "共享标题",
            content: "通用内容",
            sortOrder: 10,
            useCount: 4,
            lastUsedAt: now,
            createdAt: now,
            updatedAt: now
        )
    )
    try entryRepository.create(
        Entry(
            projectId: currentProject.id,
            title: "共享标题",
            content: "当前内容",
            sortOrder: 10,
            useCount: 4,
            lastUsedAt: now,
            createdAt: now,
            updatedAt: now
        )
    )

    let result = try entryRepository.fetchMixed(
        currentProjectId: currentProject.id,
        defaultProjectId: defaultProject.id
    )

    #expect(result.count == 2)
    #expect(result.first?.projectId == currentProject.id)
    #expect(result.last?.projectId == defaultProject.id)
}

@Test
func mixedEntriesUseUpdatedAtAsFinalTieBreaker() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)

    let defaultProject = try #require(projectRepository.fetchDefault())
    let currentProject = Project(name: "Current")
    try projectRepository.create(currentProject)

    let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
    let newDate = oldDate.addingTimeInterval(60)
    let oldEntry = Entry(
        projectId: currentProject.id,
        title: "Old",
        content: "old",
        sortOrder: 0,
        useCount: 0,
        lastUsedAt: nil,
        createdAt: oldDate,
        updatedAt: oldDate
    )
    let newEntry = Entry(
        projectId: currentProject.id,
        title: "New",
        content: "new",
        sortOrder: 0,
        useCount: 0,
        lastUsedAt: nil,
        createdAt: newDate,
        updatedAt: newDate
    )
    try entryRepository.create(oldEntry)
    try entryRepository.create(newEntry)

    let result = try entryRepository.fetchMixed(
        currentProjectId: currentProject.id,
        defaultProjectId: defaultProject.id
    )

    #expect(result.map(\.id) == [newEntry.id, oldEntry.id])
}

@Test
func entriesUseStableIdTieBreakerAcrossReadPaths() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)

    let defaultProject = try #require(projectRepository.fetchDefault())
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let laterIdEntry = Entry(
        id: "tie-b",
        projectId: defaultProject.id,
        title: "Tie Sample",
        content: "stable tie sample",
        sortOrder: 0,
        useCount: 0,
        lastUsedAt: nil,
        createdAt: now,
        updatedAt: now
    )
    let earlierIdEntry = Entry(
        id: "tie-a",
        projectId: defaultProject.id,
        title: "Tie Sample",
        content: "stable tie sample",
        sortOrder: 0,
        useCount: 0,
        lastUsedAt: nil,
        createdAt: now,
        updatedAt: now
    )
    try entryRepository.create(laterIdEntry)
    try entryRepository.create(earlierIdEntry)

    #expect(try entryRepository.fetchByProject(defaultProject.id).map(\.id) == ["tie-a", "tie-b"])
    #expect(try entryRepository.fetchAll().map(\.id) == ["tie-a", "tie-b"])
    #expect(
        try entryRepository.fetchMixed(
            currentProjectId: defaultProject.id,
            defaultProjectId: defaultProject.id
        ).map(\.id) == ["tie-a", "tie-b"]
    )
    #expect(
        try entryRepository.search(query: "Tie", projectIds: [defaultProject.id]).map(\.id) == ["tie-a", "tie-b"]
    )
}

@Test
func migrateAndDeleteMovesEntriesToTargetProject() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)

    let sourceProject = Project(name: "Source")
    let targetProject = Project(name: "Target")
    try projectRepository.create(sourceProject)
    try projectRepository.create(targetProject)

    let entry = Entry(projectId: sourceProject.id, title: "Snippet", content: "echo hello")
    try entryRepository.create(entry)

    try projectRepository.migrateAndDelete(fromId: sourceProject.id, toId: targetProject.id)

    #expect(try projectRepository.fetchById(sourceProject.id) == nil)
    let migratedEntry = try #require(entryRepository.fetchById(entry.id))
    #expect(migratedEntry.projectId == targetProject.id)
}

@Test
func deletingDefaultProjectFails() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let defaultProject = try #require(projectRepository.fetchDefault())

    do {
        try projectRepository.delete(id: defaultProject.id)
        Issue.record("Expected deleting the default project to fail.")
    } catch {
        guard case RepositoryError.cannotDeleteDefault = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
    }
}

@Test
func deletingNonEmptyProjectFailsWithEntryCount() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)

    let project = Project(name: "Occupied")
    try projectRepository.create(project)
    try entryRepository.create(Entry(projectId: project.id, title: "Snippet", content: "echo hello"))

    do {
        try projectRepository.delete(id: project.id)
        Issue.record("Expected deleting a non-empty project to fail.")
    } catch {
        guard case RepositoryError.projectNotEmpty(let count) = error else {
            Issue.record("Unexpected error: \(error)")
            return
        }
        #expect(count == 1)
    }
}

@Test
func entrySearchServiceReturnsDefaultOnlyWhenDefaultProjectIsActive() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
    let defaultProject = try #require(projectRepository.fetchDefault())
    let searchService = EntrySearchService(entryRepository: entryRepository)

    try entryRepository.create(Entry(projectId: defaultProject.id, title: "Common", content: "Shared content"))

    let results = try searchService.search(
        query: "",
        currentProjectId: defaultProject.id,
        defaultProjectId: defaultProject.id
    )

    #expect(results.count == 1)
    #expect(results.first?.projectId == defaultProject.id)
}

@Test
func entrySearchServiceReturnsMixedResultsForCurrentAndDefaultProjects() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
    let defaultProject = try #require(projectRepository.fetchDefault())
    let currentProject = Project(name: "Current")
    try projectRepository.create(currentProject)
    let searchService = EntrySearchService(entryRepository: entryRepository)

    try entryRepository.create(Entry(projectId: defaultProject.id, title: "Common", content: "Shared content"))
    try entryRepository.create(Entry(projectId: currentProject.id, title: "Current", content: "Current content"))

    let results = try searchService.search(
        query: "",
        currentProjectId: currentProject.id,
        defaultProjectId: defaultProject.id
    )

    #expect(results.count == 2)
    #expect(Set(results.map(\.projectId)) == Set([defaultProject.id, currentProject.id]))
}

@Test
func executionLogPersistsFailureReasonAndDiagnostics() throws {
    let databaseManager = try makeDatabaseManager()
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)

    let log = ExecutionLog(
        entryId: "entry-1",
        projectId: "project-1",
        frontAppBundleId: "com.apple.Safari",
        observedAppBundleId: Bundle.main.bundleIdentifier,
        hasAccessibility: true,
        clipboardSuccess: true,
        pasteAttempted: false,
        pasteSuccess: false,
        result: Constants.ExecutionResult.clipboardOnly.rawValue,
        failureReason: Constants.ExecutionFailureReason.targetAppNotRestored.rawValue,
        totalDurationMs: 143
    )

    try logRepository.record(log)
    let recentLogs = try logRepository.fetchRecent(limit: 10)
    let persisted = try #require(recentLogs.first)

    #expect(persisted.failureReason == Constants.ExecutionFailureReason.targetAppNotRestored.rawValue)
    #expect(persisted.totalDurationMs == 143)
    #expect(persisted.observedAppBundleId == Bundle.main.bundleIdentifier)
}

@MainActor
@Test
func hotkeyServiceInvokesToggleAndStartsTrace() {
    let registrar = FakeHotkeyRegistrar()
    let tracker = PanelOpenTracker()
    var toggleCount = 0

    let service = HotkeyService(
        onTogglePanel: { toggleCount += 1 },
        registrar: registrar,
        panelOpenTracker: tracker
    )

    service.start()
    registrar.trigger(.togglePanel)

    #expect(toggleCount == 1)
    #expect(tracker.currentTrace != nil)
}

@MainActor
@Test
func hotkeyServiceMigratesLegacyDefaultShortcut() {
    let registrar = FakeHotkeyRegistrar()
    let migrationDefaults = UserDefaults(suiteName: UUID().uuidString)!
    let legacyShortcut = KeyboardShortcuts.Shortcut(.space, modifiers: [.option])
    let originalShortcut = KeyboardShortcuts.Name.togglePanel.shortcut
    defer {
        KeyboardShortcuts.setShortcut(originalShortcut, for: .togglePanel)
    }

    KeyboardShortcuts.setShortcut(legacyShortcut, for: .togglePanel)
    migrationDefaults.removeObject(forKey: "toggle_panel_shortcut_migrated_to_option_2")

    let service = HotkeyService(
        onTogglePanel: {},
        registrar: registrar,
        panelOpenTracker: nil,
        userDefaults: migrationDefaults
    )

    service.start()

    #expect(KeyboardShortcuts.Name.togglePanel.shortcut == KeyboardShortcuts.Shortcut(.two, modifiers: [.option]))
    #expect(migrationDefaults.bool(forKey: "toggle_panel_shortcut_migrated_to_option_2"))
}

@MainActor
@Test
func hotkeyServiceMigratesPreviousPreferredShortcutToNewDefault() {
    let registrar = FakeHotkeyRegistrar()
    let migrationDefaults = UserDefaults(suiteName: UUID().uuidString)!
    let previousPreferredShortcut = KeyboardShortcuts.Shortcut(.p, modifiers: [.option, .shift])
    let originalShortcut = KeyboardShortcuts.Name.togglePanel.shortcut
    defer {
        KeyboardShortcuts.setShortcut(originalShortcut, for: .togglePanel)
    }

    KeyboardShortcuts.setShortcut(previousPreferredShortcut, for: .togglePanel)
    migrationDefaults.removeObject(forKey: "toggle_panel_shortcut_migrated_to_option_2")

    let service = HotkeyService(
        onTogglePanel: {},
        registrar: registrar,
        panelOpenTracker: nil,
        userDefaults: migrationDefaults
    )

    service.start()

    #expect(KeyboardShortcuts.Name.togglePanel.shortcut == KeyboardShortcuts.Shortcut(.two, modifiers: [.option]))
    #expect(migrationDefaults.bool(forKey: "toggle_panel_shortcut_migrated_to_option_2"))
}

@Test
func appLaunchCoordinatorReturnsNilWhenOnlyCurrentProcessExists() {
    #expect(
        AppLaunchCoordinator.duplicateProcessIdentifier(
            currentProcessIdentifier: 42,
            runningProcessIdentifiers: [42]
        ) == nil
    )
}

@Test
func appLaunchCoordinatorReturnsExistingProcessWhenDuplicateExists() {
    #expect(
        AppLaunchCoordinator.duplicateProcessIdentifier(
            currentProcessIdentifier: 42,
            runningProcessIdentifiers: [42, 7, 7]
        ) == 7
    )
}

@Test
func appLaunchCoordinatorSkipsDuplicateCheckWhenOverrideIsEnabled() {
    #expect(
        AppLaunchCoordinator.shouldSkipDuplicateCheck(
            environment: [AppLaunchCoordinator.allowExistingInstanceEnvironmentKey: "1"]
        )
    )
    #expect(!AppLaunchCoordinator.shouldSkipDuplicateCheck(environment: [:]))
}

@Test
func appLaunchCoordinatorReturnsNilWhenDuplicateExitsDuringSettleWindow() {
    var samples = [
        [pid_t(42), pid_t(7)],
        [pid_t(42)]
    ]

    let result = AppLaunchCoordinator.duplicateProcessIdentifierAfterSettling(
        currentProcessIdentifier: 42,
        timeoutMs: 20,
        pollIntervalMs: 1,
        runningProcessIdentifiersProvider: {
            let next = samples.first ?? [pid_t(42)]
            if !samples.isEmpty {
                samples.removeFirst()
            }
            return next
        },
        sleep: { _ in }
    )

    #expect(result == nil)
}

@Test
func appLaunchCoordinatorReturnsDuplicateWhenItPersistsPastSettleWindow() {
    let result = AppLaunchCoordinator.duplicateProcessIdentifierAfterSettling(
        currentProcessIdentifier: 42,
        timeoutMs: 0,
        pollIntervalMs: 1,
        runningProcessIdentifiersProvider: { [42, 7] },
        sleep: { _ in }
    )

    #expect(result == 7)
}

@MainActor
@Test
func quickPanelPrepareForPresentationResetsStateAndRequestsFocus() throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let permissionService = PermissionService()
    let appState = AppState()
    let defaultProject = try #require(projectRepository.fetchDefault())
    appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

    let currentProject = Project(name: "Current")
    try projectRepository.create(currentProject)
    try settingsRepository.setCurrentProjectId(currentProject.id)
    appState.currentProjectId = currentProject.id

    let executeService = ExecuteService(
        clipboardService: ClipboardService(),
        pasteService: PasteService(),
        entryRepository: entryRepository,
        logRepository: logRepository,
        permissionService: permissionService,
        targetApplicationProvider: { nil },
        currentFrontApplicationProvider: { nil }
    )

    let viewModel = QuickPanelViewModel(
        appState: appState,
        projectRepository: projectRepository,
        settingsRepository: settingsRepository,
        searchService: EntrySearchService(entryRepository: entryRepository),
        executeService: executeService,
        permissionService: permissionService,
        panelOpenTracker: PanelOpenTracker(),
        onClosePanel: {}
    )

    viewModel.query = "old-query"
    viewModel.selectedIndex = 4
    let previousFocusToken = viewModel.focusToken

    viewModel.prepareForPresentation()

    #expect(viewModel.query == "")
    #expect(viewModel.selectedIndex == 0)
    #expect(viewModel.currentProjectId == currentProject.id)
    #expect(viewModel.focusToken == previousFocusToken + 1)
    #expect(viewModel.isExecutionReady == false)
    #expect(!viewModel.projects.isEmpty)
}

@MainActor
@Test
func mainWindowSelectedEntryFollowsVisibleFilters() async throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let permissionService = PermissionService()
    let loginItemService = LoginItemService()
    let updaterService = UpdaterService()
    let storageMaintenanceService = StorageMaintenanceService(
        dbQueue: databaseManager.dbQueue,
        logRepository: logRepository,
        databaseURL: databaseManager.databaseURL
    )
    let appState = AppState()
    let defaultProject = try #require(projectRepository.fetchDefault())
    appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

    let promptEntry = Entry(
        projectId: defaultProject.id,
        title: "Prompt Entry",
        content: "prompt",
        type: Constants.EntryType.prompt.rawValue
    )
    let codeEntry = Entry(
        projectId: defaultProject.id,
        title: "Code Entry",
        content: "code",
        type: Constants.EntryType.code.rawValue
    )
    try entryRepository.create(promptEntry)
    try entryRepository.create(codeEntry)

    let viewModel = MainWindowViewModel(
        appState: appState,
        projectRepository: projectRepository,
        entryRepository: entryRepository,
        settingsRepository: settingsRepository,
        logRepository: logRepository,
        permissionService: permissionService,
        loginItemService: loginItemService,
        storageMaintenanceService: storageMaintenanceService,
        updaterService: updaterService,
        launchRecoveryReport: nil
    )

    viewModel.load()
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while viewModel.entries.count != 2 && clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }

    viewModel.selectedEntryId = promptEntry.id
    #expect(viewModel.selectedEntry?.id == promptEntry.id)

    viewModel.toggleEntryKindFilter(.code)

    #expect(viewModel.displayedEntries.map(\.id) == [codeEntry.id])
    #expect(viewModel.selectedEntry?.id == codeEntry.id)
}

@MainActor
@Test
func mainWindowDisplayedEntriesCacheUpdatesWhenSortModeChanges() async throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let permissionService = PermissionService()
    let loginItemService = LoginItemService()
    let updaterService = UpdaterService()
    let storageMaintenanceService = StorageMaintenanceService(
        dbQueue: databaseManager.dbQueue,
        logRepository: logRepository,
        databaseURL: databaseManager.databaseURL
    )
    let appState = AppState()
    let defaultProject = try #require(projectRepository.fetchDefault())
    appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let alphaEntry = Entry(
        id: "entry-alpha",
        projectId: defaultProject.id,
        title: "Alpha",
        content: "alpha",
        useCount: 1,
        lastUsedAt: now,
        updatedAt: now
    )
    let zetaEntry = Entry(
        id: "entry-zeta",
        projectId: defaultProject.id,
        title: "Zeta",
        content: "zeta",
        useCount: 10,
        lastUsedAt: now,
        updatedAt: now
    )
    try entryRepository.create(alphaEntry)
    try entryRepository.create(zetaEntry)

    let viewModel = MainWindowViewModel(
        appState: appState,
        projectRepository: projectRepository,
        entryRepository: entryRepository,
        settingsRepository: settingsRepository,
        logRepository: logRepository,
        permissionService: permissionService,
        loginItemService: loginItemService,
        storageMaintenanceService: storageMaintenanceService,
        updaterService: updaterService,
        launchRecoveryReport: nil
    )

    viewModel.load()
    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while viewModel.displayedEntries.count != 2 && clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(viewModel.displayedEntries.map(\.id) == [zetaEntry.id, alphaEntry.id])

    viewModel.entrySortMode = .alpha

    #expect(viewModel.displayedEntries.map(\.id) == [alphaEntry.id, zetaEntry.id])
}

@MainActor
@Test
func quickPanelClearsResultsWhileAsyncSearchIsPending() async throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let permissionService = PermissionService()
    let appState = AppState()
    let defaultProject = try #require(projectRepository.fetchDefault())
    appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

    try entryRepository.create(Entry(projectId: defaultProject.id, title: "Alpha", content: "Alpha body"))
    try entryRepository.create(Entry(projectId: defaultProject.id, title: "Beta", content: "Beta body"))

    let executeService = ExecuteService(
        clipboardService: ClipboardService(),
        pasteService: PasteService(),
        entryRepository: entryRepository,
        logRepository: logRepository,
        permissionService: permissionService,
        targetApplicationProvider: { nil },
        currentFrontApplicationProvider: { nil }
    )

    let viewModel = QuickPanelViewModel(
        appState: appState,
        projectRepository: projectRepository,
        settingsRepository: settingsRepository,
        searchService: EntrySearchService(entryRepository: entryRepository),
        executeService: executeService,
        permissionService: permissionService,
        panelOpenTracker: PanelOpenTracker(),
        onClosePanel: {}
    )

    viewModel.prepareForPresentation()

    let clock = ContinuousClock()
    let deadline = clock.now + .seconds(1)
    while viewModel.entries.count != 2 && clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }

    #expect(viewModel.entries.count == 2)

    viewModel.query = "Alpha"

    #expect(viewModel.entries.isEmpty)
    #expect(viewModel.selectedEntry == nil)
}

@MainActor
@Test
func quickPanelDoesNotUnlockExecutionWhenSearchFieldFocusFails() async throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let permissionService = PermissionService()
    let appState = AppState()
    let defaultProject = try #require(projectRepository.fetchDefault())
    appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

    let executeService = ExecuteService(
        clipboardService: ClipboardService(),
        pasteService: PasteService(),
        entryRepository: entryRepository,
        logRepository: logRepository,
        permissionService: permissionService,
        targetApplicationProvider: { nil },
        currentFrontApplicationProvider: { nil }
    )

    let viewModel = QuickPanelViewModel(
        appState: appState,
        projectRepository: projectRepository,
        settingsRepository: settingsRepository,
        searchService: EntrySearchService(entryRepository: entryRepository),
        executeService: executeService,
        permissionService: permissionService,
        panelOpenTracker: PanelOpenTracker(),
        onClosePanel: {}
    )

    viewModel.prepareForPresentation()
    viewModel.handleSearchFieldFocus(PanelFocusResult(token: viewModel.focusToken, succeeded: false))
    try await Task.sleep(for: .milliseconds(100))

    #expect(viewModel.isExecutionReady == false)
}

@MainActor
@Test
func quickPanelExecutionUnlocksAfterManualFocusRecovery() async throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let permissionService = PermissionService()
    let appState = AppState()
    let defaultProject = try #require(projectRepository.fetchDefault())
    appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

    let executeService = ExecuteService(
        clipboardService: ClipboardService(),
        pasteService: PasteService(),
        entryRepository: entryRepository,
        logRepository: logRepository,
        permissionService: permissionService,
        targetApplicationProvider: { nil },
        currentFrontApplicationProvider: { nil }
    )

    let viewModel = QuickPanelViewModel(
        appState: appState,
        projectRepository: projectRepository,
        settingsRepository: settingsRepository,
        searchService: EntrySearchService(entryRepository: entryRepository),
        executeService: executeService,
        permissionService: permissionService,
        panelOpenTracker: PanelOpenTracker(),
        onClosePanel: {}
    )

    viewModel.prepareForPresentation()
    let focusToken = viewModel.focusToken
    viewModel.handleSearchFieldFocus(PanelFocusResult(token: focusToken, succeeded: false))
    viewModel.handleSearchFieldFocus(
        PanelFocusResult(token: focusToken, succeeded: true, attempt: Constants.panelFocusMaxAttempts)
    )
    try await Task.sleep(for: .milliseconds(120))

    #expect(viewModel.isExecutionReady == true)
}

@MainActor
@Test
func quickPanelExecutionUnlocksAfterFocusResolution() async throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let permissionService = PermissionService()
    let appState = AppState()
    let defaultProject = try #require(projectRepository.fetchDefault())
    appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

    let executeService = ExecuteService(
        clipboardService: ClipboardService(),
        pasteService: PasteService(),
        entryRepository: entryRepository,
        logRepository: logRepository,
        permissionService: permissionService,
        targetApplicationProvider: { nil },
        currentFrontApplicationProvider: { nil }
    )

    let viewModel = QuickPanelViewModel(
        appState: appState,
        projectRepository: projectRepository,
        settingsRepository: settingsRepository,
        searchService: EntrySearchService(entryRepository: entryRepository),
        executeService: executeService,
        permissionService: permissionService,
        panelOpenTracker: PanelOpenTracker(),
        onClosePanel: {}
    )

    viewModel.prepareForPresentation()
    #expect(viewModel.isExecutionReady == false)

    viewModel.handleSearchFieldFocus(PanelFocusResult(token: viewModel.focusToken, succeeded: true))
    try await Task.sleep(for: .milliseconds(100))

    #expect(viewModel.isExecutionReady == true)
}

@Test
func targetApplicationRestoreMismatchRequiresConfirmedDifferentBundleId() {
    #expect(
        ExecuteService.isTargetApplicationRestoreMismatch(
            expectedBundleId: "com.example.target",
            observedBundleId: nil
        ) == false
    )
    #expect(
        ExecuteService.isTargetApplicationRestoreMismatch(
            expectedBundleId: nil,
            observedBundleId: "com.example.target"
        ) == false
    )
    #expect(
        ExecuteService.isTargetApplicationRestoreMismatch(
            expectedBundleId: "com.example.target",
            observedBundleId: "com.example.other"
        ) == true
    )
}

@MainActor
@Test
func quickPanelRetryFocusAfterActivationStabilizedRequestsAnotherFocusCycle() async throws {
    let databaseManager = try makeDatabaseManager()
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)
    let entryRepository = EntryRepository(dbQueue: databaseManager.dbQueue)
    let settingsRepository = SettingsRepository(dbQueue: databaseManager.dbQueue)
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let permissionService = PermissionService()
    let appState = AppState()
    let defaultProject = try #require(projectRepository.fetchDefault())
    appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

    let executeService = ExecuteService(
        clipboardService: ClipboardService(),
        pasteService: PasteService(),
        entryRepository: entryRepository,
        logRepository: logRepository,
        permissionService: permissionService,
        targetApplicationProvider: { nil },
        currentFrontApplicationProvider: { nil }
    )

    let viewModel = QuickPanelViewModel(
        appState: appState,
        projectRepository: projectRepository,
        settingsRepository: settingsRepository,
        searchService: EntrySearchService(entryRepository: entryRepository),
        executeService: executeService,
        permissionService: permissionService,
        panelOpenTracker: PanelOpenTracker(),
        onClosePanel: {}
    )

    viewModel.prepareForPresentation()
    let initialFocusToken = viewModel.focusToken
    viewModel.handleSearchFieldFocus(PanelFocusResult(token: initialFocusToken, succeeded: true))
    try await Task.sleep(for: .milliseconds(120))
    #expect(viewModel.isExecutionReady == true)

    viewModel.retryFocusAfterActivationStabilized()

    #expect(viewModel.focusToken == initialFocusToken + 1)
    #expect(viewModel.isExecutionReady == false)
}

@MainActor
@Test
func panelOpenTrackerRecordsDurations() {
    let tracker = PanelOpenTracker()

    tracker.markHotkeyTriggered()
    tracker.markPanelShown()
    tracker.markSearchFieldFocused(PanelFocusResult(token: 1, succeeded: true))

    let trace = tracker.currentTrace
    #expect(trace != nil)
    #expect(trace?.hotkeyToPanelShownMs != nil)
    #expect(trace?.hotkeyToSearchFieldFocusedMs != nil)
}

@Test
func panelActivationActionRetriesUntilMaxAttempts() {
    let unstableSnapshot = PanelActivationSnapshot(
        appIsActive: false,
        panelIsVisible: true,
        panelIsKey: false
    )
    let stableSnapshot = PanelActivationSnapshot(
        appIsActive: true,
        panelIsVisible: true,
        panelIsKey: true
    )

    #expect(
        PanelService.activationAction(snapshot: unstableSnapshot, attempt: 0, maxAttempts: 3)
            == .retry(nextAttempt: 1)
    )
    #expect(
        PanelService.activationAction(snapshot: unstableSnapshot, attempt: 3, maxAttempts: 3)
            == .failed
    )
    #expect(
        PanelService.activationAction(snapshot: stableSnapshot, attempt: 1, maxAttempts: 3)
            == .stable
    )
}

@Test
func panelFocusRequiresActiveKeyWindowBeforeUnlockingExecution() {
    #expect(
        PanelFocusResult.interactionReady(
            appIsActive: true,
            windowIsVisible: true,
            windowIsKey: true,
            firstResponderMatches: true,
            hasEditor: false
        )
    )
    #expect(
        !PanelFocusResult.interactionReady(
            appIsActive: false,
            windowIsVisible: true,
            windowIsKey: true,
            firstResponderMatches: true,
            hasEditor: true
        )
    )
    #expect(
        !PanelFocusResult.interactionReady(
            appIsActive: true,
            windowIsVisible: true,
            windowIsKey: false,
            firstResponderMatches: true,
            hasEditor: true
        )
    )
}

@Test
func activationPolicyIsRegularWhenPanelIsVisible() {
    #expect(
        PanelService.desiredActivationPolicy(
            isPanelVisible: true,
            isMainWindowVisible: false
        ) == .regular
    )
}

@Test
func activationPolicyFallsBackToAccessoryOnlyWhenNoForegroundWindowIsVisible() {
    #expect(
        PanelService.desiredActivationPolicy(
            isPanelVisible: false,
            isMainWindowVisible: true
        ) == .regular
    )
    #expect(
        PanelService.desiredActivationPolicy(
            isPanelVisible: false,
            isMainWindowVisible: false
        ) == .accessory
    )
}

@Test
func panelVisibilityCoordinatorTransitions() {
    let coordinator = PanelVisibilityCoordinator()

    #expect(coordinator.toggleAction() == .show)
    #expect(coordinator.beginShow())
    coordinator.finishShow()
    #expect(coordinator.state == .visible)
    #expect(coordinator.toggleAction() == .hide)
    #expect(coordinator.beginHide())
    coordinator.finishHide()
    #expect(coordinator.state == .hidden)
}

@Test
func quickPanelWindowCanBecomeKeyAndMain() {
    let panel = QuickPanelWindow(
        contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )

    #expect(panel.canBecomeKey)
    #expect(panel.canBecomeMain)
}

@Test
func databaseManagerRecoversFromCorruptedStore() throws {
    let brokenDatabaseURL = try makeTemporaryDatabaseURL()

    try Data("not a sqlite database".utf8).write(to: brokenDatabaseURL)

    let databaseManager = try DatabaseManager(url: brokenDatabaseURL)
    let projectRepository = ProjectRepository(dbQueue: databaseManager.dbQueue)

    #expect(databaseManager.launchRecoveryReport != nil)
    #expect(try projectRepository.fetchDefault() != nil)

    let recoveredFileURL = databaseManager.launchRecoveryReport?.quarantinedFilesDirectoryURL
        .appendingPathComponent(brokenDatabaseURL.lastPathComponent)
    #expect(FileManager.default.fileExists(atPath: recoveredFileURL?.path ?? ""))
}

@Test
func databaseManagerDoesNotQuarantineStoreWhenDatabaseIsLocked() throws {
    let databaseURL = try makeTemporaryDatabaseURL()

    var lockingConnection: OpaquePointer?
    defer {
        if let lockingConnection {
            sqlite3_exec(lockingConnection, "ROLLBACK TRANSACTION", nil, nil, nil)
            sqlite3_close(lockingConnection)
        }
    }
    #expect(sqlite3_open(databaseURL.path, &lockingConnection) == SQLITE_OK)
    let sqlite = try #require(lockingConnection)
    var errorMessage: UnsafeMutablePointer<CChar>?
    let beginResult = sqlite3_exec(sqlite, "BEGIN EXCLUSIVE TRANSACTION", nil, nil, &errorMessage)
    sqlite3_free(errorMessage)
    #expect(beginResult == SQLITE_OK)

    do {
        _ = try DatabaseManager(url: databaseURL)
        Issue.record("Expected a storeBusyPreservingStore error, but initialization succeeded.")
    } catch let error as DatabaseManager.InitializationError {
        switch error {
        case .storeBusyPreservingStore:
            break
        default:
            Issue.record("Unexpected initialization error: \(error)")
        }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    #expect(!FileManager.default.fileExists(atPath: Constants.recoveryDirectory(for: databaseURL).path))
}

@Test
func storageMaintenanceKeepsManualBackupsBeyondAutomaticRetention() throws {
    let databaseManager = try makeDatabaseManager()
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let maintenanceService = StorageMaintenanceService(
        dbQueue: databaseManager.dbQueue,
        logRepository: logRepository,
        databaseURL: databaseManager.databaseURL
    )

    let backupTarget = Constants.automaticBackupRetentionCount + 2
    for _ in 0..<backupTarget {
        _ = try maintenanceService.createManualBackup()
    }

    let snapshot = try maintenanceService.healthSnapshot()
    #expect(snapshot.backupCount == backupTarget)
    #expect(snapshot.latestBackupURL != nil)
}

@Test
func launchMaintenanceDoesNotCreateExtraBackupAfterRecentManualBackup() throws {
    let databaseManager = try makeDatabaseManager()
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let maintenanceService = StorageMaintenanceService(
        dbQueue: databaseManager.dbQueue,
        logRepository: logRepository,
        databaseURL: databaseManager.databaseURL
    )

    let manualBackupURL = try maintenanceService.createManualBackup()
    let beforeSnapshot = try maintenanceService.healthSnapshot()

    _ = try maintenanceService.performLaunchMaintenance()

    let afterSnapshot = try maintenanceService.healthSnapshot()
    #expect(afterSnapshot.backupCount == beforeSnapshot.backupCount)
    #expect(afterSnapshot.latestBackupURL?.lastPathComponent == manualBackupURL.lastPathComponent)
}

@Test
func freshDatabaseDoesNotCreateUnusedTagsIndex() throws {
    let databaseManager = try makeDatabaseManager()
    let indexNames = try databaseManager.dbQueue.read { db in
        try Row.fetchAll(db, sql: "PRAGMA index_list('entries')")
            .compactMap { row in row["name"] as String? }
    }

    #expect(!indexNames.contains("index_entries_on_tags"))
}

@Test
func migrationsDropLegacyTagsIndex() throws {
    let databaseURL = try makeTemporaryDatabaseURL()

    let queue = try DatabaseQueue(path: databaseURL.path)
    try queue.write { db in
        try db.execute(sql: """
            CREATE TABLE entries (
                id TEXT PRIMARY KEY NOT NULL,
                project_id TEXT NOT NULL,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                type TEXT NOT NULL,
                is_pinned INTEGER NOT NULL,
                sort_order INTEGER NOT NULL,
                use_count INTEGER NOT NULL,
                last_used_at TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                tags TEXT NOT NULL DEFAULT '[]'
            )
            """)
        try db.execute(sql: "CREATE INDEX index_entries_on_tags ON entries(tags)")
        try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT PRIMARY KEY NOT NULL)")
        for identifier in [
            "v1_create_tables",
            "v2_execution_log_diagnostics",
            "v3_execution_log_interaction_diagnostics",
            "v4_entry_tags"
        ] {
            try db.execute(
                sql: "INSERT INTO grdb_migrations(identifier) VALUES (?)",
                arguments: [identifier]
            )
        }
    }

    let databaseManager = try DatabaseManager(url: databaseURL)
    let indexNames = try databaseManager.dbQueue.read { db in
        try Row.fetchAll(db, sql: "PRAGMA index_list('entries')")
            .compactMap { row in row["name"] as String? }
    }

    #expect(!indexNames.contains("index_entries_on_tags"))
}

@Test
func logCleanupRemovesOnlyExpiredEntries() throws {
    let databaseManager = try makeDatabaseManager()
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)

    try logRepository.record(
        ExecutionLog(
            entryId: "recent",
            projectId: "project-1",
            hasAccessibility: true,
            clipboardSuccess: true,
            pasteAttempted: true,
            pasteSuccess: true,
            result: Constants.ExecutionResult.success.rawValue,
            createdAt: Date()
        )
    )
    try logRepository.record(
        ExecutionLog(
            entryId: "expired",
            projectId: "project-1",
            hasAccessibility: true,
            clipboardSuccess: true,
            pasteAttempted: false,
            pasteSuccess: false,
            result: Constants.ExecutionResult.clipboardOnly.rawValue,
            createdAt: Calendar.current.date(byAdding: .day, value: -45, to: Date()) ?? .distantPast
        )
    )

    try logRepository.cleanup(olderThanDays: 30)
    let remaining = try logRepository.fetchRecent(limit: 10)

    #expect(remaining.count == 1)
    #expect(remaining.first?.entryId == "recent")
}

@Test
func healthSummaryCountsResultsAcrossOutcomes() throws {
    let databaseManager = try makeDatabaseManager()
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let now = Date()

    try logRepository.record(
        ExecutionLog(
            entryId: "success",
            projectId: "project-1",
            hasAccessibility: true,
            clipboardSuccess: true,
            pasteAttempted: true,
            pasteSuccess: true,
            result: Constants.ExecutionResult.success.rawValue,
            createdAt: now
        )
    )
    try logRepository.record(
        ExecutionLog(
            entryId: "clipboard-only",
            projectId: "project-1",
            hasAccessibility: false,
            clipboardSuccess: true,
            pasteAttempted: false,
            pasteSuccess: false,
            result: Constants.ExecutionResult.clipboardOnly.rawValue,
            createdAt: now
        )
    )
    try logRepository.record(
        ExecutionLog(
            entryId: "failed",
            projectId: "project-1",
            hasAccessibility: true,
            clipboardSuccess: false,
            pasteAttempted: false,
            pasteSuccess: false,
            result: Constants.ExecutionResult.failed.rawValue,
            createdAt: now
        )
    )

    let summary = try logRepository.fetchHealthSummary(
        since: Calendar.current.date(byAdding: .day, value: -7, to: now) ?? .distantPast
    )

    #expect(summary.totalCount == 3)
    #expect(summary.successCount == 1)
    #expect(summary.clipboardOnlyCount == 1)
    #expect(summary.failedCount == 1)
    #expect(summary.latestExecutionAt != nil)
    #expect(summary.latestFailureAt != nil)
}

@Test
func releaseReadinessBuildOnlyModeDoesNotRequireTestRunner() throws {
    let script = try readRepositoryText("scripts/release-readiness.sh")

    #expect(script.contains("Running swift test in build-only validation mode"))
    #expect(script.contains("swift build --package-path \"$PACKAGE_ROOT\" --build-tests"))
}

@Test
func releaseReadinessExercisesBackupRestoreDrill() throws {
    let script = try readRepositoryText("scripts/release-readiness.sh")

    #expect(script.contains("Verifying backup restore path"))
    #expect(script.contains("\"${REPO_ROOT}/scripts/restore-backup.sh\" --target-dir \"$RESTORE_APP_SUPPORT_DIR\" \"$LATEST_BACKUP_PATH\""))
    #expect(script.contains("Restored database integrity check failed"))
}

@Test
func releaseReadinessVerifiesArchiveForBuiltAppVersion() throws {
    let script = try readRepositoryText("scripts/release-readiness.sh")

    #expect(script.contains("CFBundleShortVersionString"))
    #expect(script.contains("CFBundleVersion"))
    #expect(script.contains("ZIP_PATH=\"${OUTPUT_ROOT}/PromptPanel-${SHORT_VERSION}+${BUILD_VERSION}-macos.zip\""))
    #expect(!script.contains("ZIP_MATCHES=("))
}

@Test
func buildAppRejectsPartialSparkleConfiguration() throws {
    let script = try readRepositoryText("scripts/build-app.sh")

    #expect(script.contains("Sparkle feed URL was provided, but SUPublicEDKey is missing."))
    #expect(script.contains("Sparkle public key was provided, but SUFeedURL is missing."))
}

@Test
func buildAppStripsExtendedAttributesBeforeSigning() throws {
    let script = try readRepositoryText("scripts/build-app.sh")

    let stripCallRange = try #require(script.range(of: "strip_extended_attributes \"$APP_PATH\""))
    let appSignRange = try #require(script.range(of: "codesign_path \"${APP_PATH}\" runtime on"))

    #expect(script.contains("xattr -cr \"$target_path\""))
    #expect(stripCallRange.lowerBound < appSignRange.lowerBound)
}

@Test
func restoreBackupStagesValidatedCopyBeforeMovingCurrentDatabase() throws {
    let script = try readRepositoryText("scripts/restore-backup.sh")

    let stageCopyRange = try #require(script.range(of: "cp \"$BACKUP_SOURCE\" \"$STAGED_DATABASE_PATH\""))
    let preserveCurrentRange = try #require(script.range(of: "mv \"$SOURCE_PATH\" \"${RECOVERY_DIR}/\""))
    let restoreStagedRange = try #require(script.range(of: "mv \"$STAGED_DATABASE_PATH\" \"$DATABASE_PATH\""))

    #expect(script.contains("STAGING_DIR=\"${TARGET_APP_SUPPORT_DIR}/Recovery/manual-restore-staging-${TIMESTAMP}\""))
    #expect(script.contains("STAGED_INTEGRITY_RESULT="))
    #expect(!script.contains("cp \"$BACKUP_SOURCE\" \"$DATABASE_PATH\""))
    #expect(stageCopyRange.lowerBound < preserveCurrentRange.lowerBound)
    #expect(preserveCurrentRange.lowerBound < restoreStagedRange.lowerBound)
}

@Test
func swiftUIPrimaryClickSurfacesUseExpandedHitTargets() throws {
    let design = try readRepositoryText("Sources/PromptPanel/Features/Shared/DesignComponents.swift")
    let library = try readRepositoryText("Sources/PromptPanel/Features/MainWindow/LibraryView.swift")
    let mainWindow = try readRepositoryText("Sources/PromptPanel/Features/MainWindow/MainWindowView.swift")
    let quickPanel = try readRepositoryText("Sources/PromptPanel/Features/Panel/QuickPanelView.swift")
    let settings = try readRepositoryText("Sources/PromptPanel/Features/MainWindow/SettingsView.swift")

    #expect(design.contains("func fullHitTarget()"))
    #expect(design.contains("func roundedHitTarget(cornerRadius: CGFloat)"))

    #expect(library.contains("@FocusState private var isEntrySearchFocused"))
    #expect(library.contains(".focused($isEntrySearchFocused)"))
    #expect(library.contains(".onTapGesture {\n            isEntrySearchFocused = true\n        }"))
    #expect(library.components(separatedBy: ".fullHitTarget()").count >= 2)
    #expect(library.components(separatedBy: ".roundedHitTarget(cornerRadius: 6)").count >= 3)

    #expect(mainWindow.contains(".roundedHitTarget(cornerRadius: 6)"))
    #expect(quickPanel.components(separatedBy: ".roundedHitTarget").count >= 6)
    #expect(settings.components(separatedBy: ".roundedHitTarget(cornerRadius: 5)").count >= 3)
}

/// `restore-backup.sh` hardcodes the list of tables that must exist in a backup before it is
/// accepted as a valid PromptPanel database. That hand-maintained list silently drifts every
/// time a migration adds or drops a table: a dropped table leaves the script rejecting
/// legitimate fresh backups, and an added table leaves the script accepting truncated backups
/// that would corrupt user data after restore. Lock both directions to the live schema.
@Test
func testRestoreScriptRequiredTablesStayInSyncWithLiveSchema() throws {
    let temporaryDatabaseURL = try makeTemporaryDatabaseURL()
    let databaseManager = try DatabaseManager(url: temporaryDatabaseURL)

    let liveSchemaNames: Set<String> = try databaseManager.dbQueue.read { db in
        let rows = try Row.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type IN ('table', 'view')
              AND name NOT LIKE 'sqlite_%'
        """)
        return Set(rows.compactMap { $0["name"] as String? })
    }

    let scriptText = try readRepositoryText("scripts/restore-backup.sh")
    let requiredTables = try parseShellArray(named: "REQUIRED_TABLES", from: scriptText)
    #expect(!requiredTables.isEmpty, "Could not parse REQUIRED_TABLES from restore-backup.sh; the regex likely needs to be updated.")

    // Direction 1: every entry in REQUIRED_TABLES must exist in a freshly-migrated database.
    for table in requiredTables {
        #expect(liveSchemaNames.contains(table),
                "restore-backup.sh REQUIRED_TABLES lists '\(table)' but it does not exist in the live schema. Either re-add the table in a migration or remove it from the script.")
    }

    // Direction 2: every primary user-facing table in the live schema must be validated on
    // restore. FTS5 creates internal auxiliaries (entries_fts_config / _data / _idx / _docsize
    // / _content) that exist as a side effect of the virtual table and don't need explicit
    // validation; everything else does.
    let ftsAuxSuffixes = ["_config", "_data", "_idx", "_docsize", "_content"]
    let primaryUserTables = liveSchemaNames.filter { name in
        // Keep `entries_fts` itself (the virtual table); drop its shadow auxiliaries.
        guard name != "entries_fts" else { return true }
        return !ftsAuxSuffixes.contains { name.hasSuffix($0) }
    }
    let missingFromScript = primaryUserTables.subtracting(Set(requiredTables))
    let missingList = missingFromScript.sorted().joined(separator: ", ")
    #expect(missingFromScript.isEmpty,
            "The live schema has primary tables that restore-backup.sh does not validate: \(missingList). Add them to REQUIRED_TABLES in scripts/restore-backup.sh.")
}

/// `pruneRecoveryDirectories(keeping:)` is a best-effort housekeeper called every launch.
/// It must keep the most recent N snapshots and only delete from the trailing end so a
/// human investigator can still find the freshest evidence after a crash. It must also
/// refuse to touch in-flight staging directories so a concurrent restore is not corrupted.
@MainActor
@Test
func testPruneRecoveryDirectoriesKeepsRecentAndSkipsStaging() throws {
    let temporaryDatabaseURL = try makeTemporaryDatabaseURL()
    let databaseManager = try DatabaseManager(url: temporaryDatabaseURL)
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let storage = StorageMaintenanceService(
        dbQueue: databaseManager.dbQueue,
        logRepository: logRepository,
        databaseURL: databaseManager.databaseURL
    )

    let recoveryRoot = Constants.recoveryDirectory(for: databaseManager.databaseURL)
    try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)

    // Create 8 recovered snapshots with distinct modification timestamps. The oldest 3 should
    // be pruned when keeping 5; the most recent 5 must survive.
    var createdDirectories: [URL] = []
    let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
    for index in 0..<8 {
        let snapshotURL = recoveryRoot.appendingPathComponent("recovered-2026-05-\(String(format: "%02d", index + 1))T00-00-00Z", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: baseDate.addingTimeInterval(TimeInterval(index) * 60)], ofItemAtPath: snapshotURL.path)
        createdDirectories.append(snapshotURL)
    }

    // Add an in-flight staging directory with an old timestamp; it must not be deleted even
    // though it would otherwise be the oldest.
    let stagingURL = recoveryRoot.appendingPathComponent("manual-restore-staging-1900-01-01T00-00-00Z", isDirectory: true)
    try FileManager.default.createDirectory(at: stagingURL, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.modificationDate: baseDate.addingTimeInterval(-3600)], ofItemAtPath: stagingURL.path)

    storage.pruneRecoveryDirectories(keeping: 5)

    let surviving = try FileManager.default.contentsOfDirectory(atPath: recoveryRoot.path)
    let survivingNames = Set(surviving)
    // The five newest snapshots are indexes 3..7.
    for index in 3..<8 {
        #expect(survivingNames.contains(createdDirectories[index].lastPathComponent),
                "Newer recovery snapshot \(createdDirectories[index].lastPathComponent) was pruned but should have been kept.")
    }
    // The three oldest snapshots are indexes 0..2.
    for index in 0..<3 {
        #expect(!survivingNames.contains(createdDirectories[index].lastPathComponent),
                "Older recovery snapshot \(createdDirectories[index].lastPathComponent) was kept but should have been pruned.")
    }
    // Staging directory must never be touched even though it is the oldest mtime.
    #expect(survivingNames.contains(stagingURL.lastPathComponent),
            "Staging directory was pruned; restore-backup.sh staging copies must never be touched by maintenance.")
}

/// `DiagnosticsExportService` must emit a zip that contains the documented files, refuse to
/// leak any entry content, and not crash when the unified-log source is empty. Use a fake
/// log source and a fake permission provider so the test does not depend on the live OS.
@MainActor
@Test
func testDiagnosticsExportBundleProducesPrivacySafeZip() throws {
    let temporaryDatabaseURL = try makeTemporaryDatabaseURL()
    let databaseManager = try DatabaseManager(url: temporaryDatabaseURL)
    let logRepository = LogRepository(dbQueue: databaseManager.dbQueue)
    let storage = StorageMaintenanceService(
        dbQueue: databaseManager.dbQueue,
        logRepository: logRepository,
        databaseURL: databaseManager.databaseURL
    )

    // Record one execution log so the bundle has a non-empty execution-logs.json. Note the
    // ExecutionLog model itself never carries entry title or content — only the entry id.
    try logRepository.record(ExecutionLog(
        entryId: "entry-uuid-secret-12345",
        projectId: "project-uuid",
        frontAppBundleId: "com.example.frontmost",
        hasAccessibility: true,
        clipboardSuccess: true,
        pasteAttempted: true,
        pasteSuccess: true,
        result: Constants.ExecutionResult.success.rawValue
    ))

    let permission = FakePermissionProvider(isAccessibilityGranted: true)
    let unifiedLogs = FakeUnifiedLogReader(lines: ["{\"ts\":\"2026-05-19T00:00:00Z\",\"level\":\"info\",\"message\":\"boot\"}"])
    let service = DiagnosticsExportService(
        logRepository: logRepository,
        storageMaintenanceService: storage,
        permissionService: permission,
        appInfo: DiagnosticsExportService.AppInfoProvider(
            bundleIdentifier: "com.promptpanel.app.test",
            shortVersion: "1.0.0",
            buildVersion: "999",
            minimumSystemVersion: "14.0"
        ),
        unifiedLogReader: unifiedLogs
    )

    let destinationDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PromptPanelTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
    let zipURL = destinationDir.appendingPathComponent("diagnostics.zip")
    let producedURL = try service.exportBundle(to: zipURL)
    #expect(FileManager.default.fileExists(atPath: producedURL.path))

    // Unzip and inspect.
    let unpackDir = destinationDir.appendingPathComponent("unpacked", isDirectory: true)
    try FileManager.default.createDirectory(at: unpackDir, withIntermediateDirectories: true)
    let ditto = Process()
    ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    ditto.arguments = ["-x", "-k", producedURL.path, unpackDir.path]
    try ditto.run()
    ditto.waitUntilExit()
    #expect(ditto.terminationStatus == 0)

    let bundleRoots = try FileManager.default.contentsOfDirectory(at: unpackDir, includingPropertiesForKeys: nil)
    #expect(bundleRoots.count == 1)
    guard let bundleRoot = bundleRoots.first else { return }

    let expectedFiles = ["README.txt", "app-info.json", "permissions.json", "health-snapshot.json", "execution-logs.json", "unified-logs.ndjson"]
    for name in expectedFiles {
        let fileURL = bundleRoot.appendingPathComponent(name)
        #expect(FileManager.default.fileExists(atPath: fileURL.path), "Diagnostics bundle missing \(name)")
    }

    // Privacy guard: no file in the bundle may contain the literal string "content" or
    // "title" as a JSON key, nor any entry body. The fact that ExecutionLog model has no
    // such fields gives us strong confidence; assert by scanning every file.
    let entryBodyCanary = "this-should-never-appear-in-a-diagnostics-bundle"
    let allURLs = (try? FileManager.default.contentsOfDirectory(at: bundleRoot, includingPropertiesForKeys: nil)) ?? []
    for url in allURLs {
        let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        #expect(!contents.contains(entryBodyCanary))
        #expect(!contents.contains("\"content\":"), "Diagnostics bundle file \(url.lastPathComponent) contains a 'content' JSON key.")
        #expect(!contents.contains("\"title\":"), "Diagnostics bundle file \(url.lastPathComponent) contains a 'title' JSON key.")
    }

    try? FileManager.default.removeItem(at: destinationDir)
}

private final class FakeUnifiedLogReader: UnifiedLogReading {
    private let lines: [String]
    init(lines: [String]) { self.lines = lines }
    func readEntries(subsystem: String, since: Date) throws -> [String] { lines }
}

private func parseShellArray(named: String, from script: String) throws -> [String] {
    let pattern = #"\#(named)=\(([^)]*)\)"#
    let regex = try NSRegularExpression(pattern: pattern, options: [])
    let range = NSRange(script.startIndex..., in: script)
    guard let match = regex.firstMatch(in: script, options: [], range: range),
          let bodyRange = Range(match.range(at: 1), in: script) else {
        return []
    }
    return script[bodyRange]
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
}
#endif

private final class FakeHotkeyRegistrar: HotkeyRegistrationHandling {
    private var handlers: [String: () -> Void] = [:]

    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping () -> Void) {
        handlers[name.rawValue] = action
    }

    func disable(_ name: KeyboardShortcuts.Name) {
        handlers.removeValue(forKey: name.rawValue)
    }

    func trigger(_ name: KeyboardShortcuts.Name) {
        handlers[name.rawValue]?()
    }
}

private final class FakeClipboardWriter: ClipboardWriting {
    private let success: Bool

    init(success: Bool) {
        self.success = success
    }

    func writeText(_ text: String) -> Bool {
        success
    }
}

private final class FakePasteDispatcher: PasteDispatching {
    private let result: PasteService.PasteDispatchResult
    private(set) var attemptCount: Int = 0

    init(result: PasteService.PasteDispatchResult) {
        self.result = result
    }

    func attemptPaste() -> PasteService.PasteDispatchResult {
        attemptCount += 1
        return result
    }
}

@MainActor
private final class FakePermissionProvider: AccessibilityPermissionProviding {
    private(set) var isAccessibilityGranted: Bool

    init(isAccessibilityGranted: Bool) {
        self.isAccessibilityGranted = isAccessibilityGranted
    }

    func refresh() {}
}

private func makeDatabaseManager() throws -> DatabaseManager {
    try DatabaseManager(url: makeTemporaryDatabaseURL())
}

private func makeTemporaryDatabaseURL() throws -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("PromptPanelTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    return directoryURL.appendingPathComponent("promptpanel.sqlite")
}

private func readRepositoryText(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fileURL = repositoryRoot.appendingPathComponent(relativePath)
    return try String(contentsOf: fileURL, encoding: .utf8)
}
