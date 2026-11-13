import AppKit
import Combine
import Foundation
import GRDB
@testable import PromptPanel

#if canImport(XCTest)
import XCTest
#endif
#if canImport(Testing) && PROMPTPANEL_SWIFT_TESTING
import Testing
#endif

private struct TestAssertionError: LocalizedError {
    let message: String
    let file: StaticString
    let line: UInt

    var errorDescription: String? {
        "\(file):\(line): \(message)"
    }
}

private func check(
    _ condition: @autoclosure () throws -> Bool,
    _ message: @autoclosure () -> String = "Assertion failed",
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    guard try condition() else {
        let text = message()
        #if canImport(XCTest)
        XCTFail(text, file: file, line: line)
        #endif
        throw TestAssertionError(message: text, file: file, line: line)
    }
}

private func unwrap<T>(
    _ value: @autoclosure () throws -> T?,
    _ message: @autoclosure () -> String = "Expected non-nil value",
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    guard let unwrapped = try value() else {
        let text = message()
        #if canImport(XCTest)
        XCTFail(text, file: file, line: line)
        #endif
        throw TestAssertionError(message: text, file: file, line: line)
    }
    return unwrapped
}

private final class SpyClipboardService: ClipboardWriting {
    var writtenTexts: [String] = []
    var shouldSucceed: Bool = true

    func writeText(_ text: String) -> Bool {
        guard shouldSucceed else { return false }
        writtenTexts.append(text)
        return true
    }
}

private final class SpyPasteService: PasteDispatching {
    var dispatchCount: Int = 0
    var result: PasteService.PasteDispatchResult = .dispatched

    func attemptPaste() -> PasteService.PasteDispatchResult {
        dispatchCount += 1
        return result
    }
}

@MainActor
private final class StubPermissionService: AccessibilityPermissionProviding {
    var isAccessibilityGranted: Bool = false
    func refresh() {}
}

@_cdecl("run_promptpanel_core_tests")
@MainActor
public func runPromptPanelCoreTestsFromC() -> Int32 {
    do {
        try CoreTestSuite.runAll()
        return 0
    } catch {
        fputs("Test failure: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

@MainActor
public enum CoreTestSuite {
    public static func runAll() throws {
        try verifyDatabaseAndMigrations()
        try verifyProjectAndEntryRepositories()
        try verifySearchAndRanking()
        try verifySettingsAndWindowPlacement()
        try verifyExecuteAndVisibilityServices()
        try verifyKeyCommands()
        try verifyQuickPanelScopeSafetyAndCopyUsage()
        try verifyTransferAndStorageMaintenance()
        try verifyLibraryJSONImportRollback()
        try verifyManualBackupRetention()
        try verifyWorkspaceKindsArchiveVersionsAndCloning()
        try verifyReferenceWindowAndCloudSyncConflictPreservation()
        try verifyCloudSyncDataLossProtectionAndThrottledBackups()
        try verifyCompletedRankingCleanupAndArchivedExclusion()
        try verifyQuickPanelAllScopeCaptureFilterHoverAndPreview()
        try verifyMainWindowQuickJotAutoTitleCleanupAndDebouncedAutoSave()
        try verifyPerformanceAndStabilityRegressions()
    }

    private static func makeTempDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptPanelTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("test.db")
    }

    private static func withTempDatabase(_ body: (DatabaseManager, URL) throws -> Void) throws {
        let dbURL = makeTempDatabaseURL()
        let rootDir = dbURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let manager = try DatabaseManager(url: dbURL)
        try body(manager, dbURL)
    }

    private static func withTempDatabaseAsync(_ body: @MainActor (DatabaseManager, URL) async throws -> Void) async throws {
        let dbURL = makeTempDatabaseURL()
        let rootDir = dbURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: rootDir) }
        let manager = try DatabaseManager(url: dbURL)
        try await body(manager, dbURL)
    }

    private static func waitUntilAsync(
        timeout: TimeInterval = 1.5,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private static func sleepMainActor(_ seconds: TimeInterval) async {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }

    private static func runAsyncOnMainRunLoop(
        _ operation: @escaping @MainActor () async throws -> Void
    ) throws {
        var outcome: Result<Void, Error>?
        Task { @MainActor in
            do {
                try await operation()
                outcome = .success(())
            } catch {
                outcome = .failure(error)
            }
        }
        let deadline = Date().addingTimeInterval(15)
        while outcome == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        switch outcome {
        case .success:
            return
        case .failure(let error):
            throw error
        case nil:
            throw TestAssertionError(
                message: "Timed out waiting for async main-actor test operation",
                file: #filePath,
                line: #line
            )
        }
    }

    static func verifyDatabaseAndMigrations() throws {
        try withTempDatabase { manager, dbURL in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let settingsRepo = SettingsRepository(dbQueue: manager.dbQueue)

            let defaultProject = try unwrap(projectRepo.fetchDefault())
            try check(defaultProject.name == Constants.defaultProjectName)
            try check(defaultProject.isDefault)
            try check(try settingsRepo.getCurrentProjectId() == defaultProject.id)

            let resolution = AppDelegate.resolveCurrentProjectSelection(
                persistedCurrentProjectId: "missing-id",
                defaultProjectId: defaultProject.id,
                currentProjectExists: { _ in false }
            )
            try check(resolution.projectId == defaultProject.id)
            try check(resolution.needsPersistence)
            try check(FileManager.default.fileExists(atPath: dbURL.path))
        }

        // Verify corrupt store quarantine recovery
        let brokenURL = makeTempDatabaseURL()
        let brokenRoot = brokenURL.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: brokenRoot) }
        try FileManager.default.createDirectory(at: brokenRoot, withIntermediateDirectories: true)
        try Data("not-a-sqlite-db".utf8).write(to: brokenURL)

        let recoveredManager = try DatabaseManager(url: brokenURL)
        let recoveryReport = try unwrap(recoveredManager.launchRecoveryReport)
        try check(FileManager.default.fileExists(atPath: recoveryReport.quarantinedFilesDirectoryURL.path))
        let defaultProject = try unwrap(ProjectRepository(dbQueue: recoveredManager.dbQueue).fetchDefault())
        try check(defaultProject.isDefault)
    }

    static func verifyProjectAndEntryRepositories() throws {
        try withTempDatabase { manager, _ in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)
            let defaultProject = try unwrap(projectRepo.fetchDefault())

            let workProject = Project(name: "后端研发")
            try projectRepo.create(workProject)
            try projectRepo.rename(id: workProject.id, newName: "核心研发")
            try check(try projectRepo.fetchById(workProject.id)?.name == "核心研发")

            var entry = Entry(
                projectId: workProject.id,
                title: "代码审查模板",
                content: "请重点检查：\n1. 边界条件\n2. 并发安全",
                type: Constants.EntryType.prompt.rawValue,
                isPinned: true,
                tags: ["review", "并发", "Review"]
            )
            try check(entry.tags == ["review", "并发"])
            try check(entry.previewLine == "请重点检查： 1. 边界条件 2. 并发安全")

            try entryRepo.create(entry)
            try entryRepo.recordExecution(id: entry.id)

            let fetched = try unwrap(entryRepo.fetchById(entry.id))
            try check(fetched.useCount == 1)
            try check(fetched.lastUsedAt != nil)
            try check(fetched.previewLine == "请重点检查： 1. 边界条件 2. 并发安全")

            entry.content = "更新后的单行内容\n第二行"
            try check(entry.previewLine == "更新后的单行内容 第二行")
            try entryRepo.update(entry)

            let counts = try entryRepo.entryCountByProject()
            try check(counts[workProject.id] == 1)

            try projectRepo.migrateAndDelete(fromId: workProject.id, toId: defaultProject.id)
            try check(try projectRepo.fetchById(workProject.id) == nil)
            try check(try entryRepo.fetchById(entry.id)?.projectId == defaultProject.id)
        }
    }

    static func verifySearchAndRanking() throws {
        try withTempDatabase { manager, _ in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)
            let searchService = EntrySearchService(entryRepository: entryRepo)
            let defaultProject = try unwrap(projectRepo.fetchDefault())
            let activeProject = Project(name: "Active")
            try projectRepo.create(activeProject)

            let now = Date()
            let globalPinned = Entry(
                projectId: defaultProject.id,
                title: "Deploy Checklist",
                content: "Run release-readiness before tagging",
                isPinned: true,
                useCount: 2,
                lastUsedAt: now,
                tags: ["release", "ops"]
            )
            let projectRecent = Entry(
                projectId: activeProject.id,
                title: "Deploy Hotfix",
                content: "请重点检查并发安全与边界条件 (a+b)*c",
                isPinned: false,
                useCount: 10,
                lastUsedAt: now,
                tags: ["deploy", "并发安全"]
            )
            try entryRepo.create(globalPinned)
            try entryRepo.create(projectRecent)

            let browseResults = try searchService.search(
                query: "",
                currentProjectId: activeProject.id,
                defaultProjectId: defaultProject.id
            )
            try check(browseResults.count == 2)
            try check(browseResults.first?.id == globalPinned.id)

            // Mid-token CJK substring search ("安全" inside "并发安全", "检查" inside "请重点检查")
            let midTokenCjkResults = try searchService.search(
                query: "安全",
                currentProjectId: activeProject.id,
                defaultProjectId: defaultProject.id
            )
            try check(midTokenCjkResults.map(\.id) == [projectRecent.id])

            let multiTokenCjkResults = try searchService.search(
                query: "检查 条件",
                currentProjectId: activeProject.id,
                defaultProjectId: defaultProject.id
            )
            try check(multiTokenCjkResults.map(\.id) == [projectRecent.id])

            let specialCharResults = try searchService.search(
                query: "(a+b)*c",
                currentProjectId: activeProject.id,
                defaultProjectId: defaultProject.id
            )
            try check(specialCharResults.map(\.id) == [projectRecent.id])

            let allProjectSearchResults = try entryRepo.searchAll(query: "Deploy")
            try check(allProjectSearchResults.count == 2)

            let tagOnlySearchResults = try entryRepo.searchAll(query: "", tag: "ops")
            try check(tagOnlySearchResults.map(\.id) == [globalPinned.id])

            let caseInsensitiveTagResults = try entryRepo.searchAll(query: "", tag: "OPS")
            try check(caseInsensitiveTagResults.map(\.id) == [globalPinned.id])

            let parsed = QuickPanelViewModel.extractTagFilter(from: "#deploy   hotfix  ")
            try check(parsed.cleanedQuery == "hotfix")
            try check(parsed.tag == "deploy")
        }
    }

    static func verifySettingsAndWindowPlacement() throws {
        try withTempDatabase { manager, _ in
            let settingsRepo = SettingsRepository(dbQueue: manager.dbQueue)

            try settingsRepo.setPanelPinned(true)
            try check(try settingsRepo.isPanelPinned())

            try settingsRepo.setPanelContentSize(NSSize(width: 100, height: 9999))
            let clampedSize = try settingsRepo.getPanelContentSize()
            try check(clampedSize.width == Constants.panelMinContentSize.width)
            try check(clampedSize.height == Constants.panelMaxContentSize.height)

            try settingsRepo.setAppTheme(.dark)
            try check(try settingsRepo.getAppTheme() == .dark)

            let screen = NSRect(x: 0, y: 0, width: 1280, height: 800)
            let fitted = Constants.WindowPlacement.fittedSize(
                NSSize(width: 1600, height: 900),
                minimum: NSSize(width: 440, height: 320),
                in: screen
            )
            try check(fitted.width <= screen.width)
            try check(fitted.height <= screen.height)
        }
    }

    static func verifyExecuteAndVisibilityServices() throws {
        try check(
            !ExecuteService.isTargetApplicationRestoreMismatch(
                expectedBundleId: "com.apple.dt.Xcode",
                observedBundleId: "com.apple.dt.Xcode",
                ownBundleId: "com.promptpanel.app"
            )
        )
        try check(
            ExecuteService.isTargetApplicationRestoreMismatch(
                expectedBundleId: "com.apple.dt.Xcode",
                observedBundleId: "com.apple.Safari",
                ownBundleId: "com.promptpanel.app"
            )
        )

        let coordinator = PanelVisibilityCoordinator()
        try check(coordinator.toggleAction() == .show)
        try check(coordinator.beginShow())
        coordinator.finishShow()
        try check(coordinator.state == .visible)
        try check(coordinator.toggleAction() == .hide)
        try check(coordinator.beginHide())
        coordinator.finishHide()
        try check(coordinator.state == .hidden)

        try check(
            PanelService.desiredActivationPolicy(isPanelVisible: true, isMainWindowVisible: false) == .regular
        )
        try check(
            PanelService.desiredActivationPolicy(isPanelVisible: false, isMainWindowVisible: false) == .accessory
        )
    }

    static func verifyKeyCommands() throws {
        try check(
            QuickPanelViewModel.panelKeyCommand(
                keyCode: 53,
                modifierFlags: [],
                charactersIgnoringModifiers: "\u{1b}"
            ) == .closePanel
        )
        try check(
            QuickPanelViewModel.panelKeyCommand(
                modifierFlags: [.command],
                charactersIgnoringModifiers: "3"
            ) == .executeEntry(number: 3)
        )
        try check(
            QuickPanelViewModel.panelKeyCommand(
                modifierFlags: [.command],
                charactersIgnoringModifiers: "c"
            ) == .copySelection
        )
        try check(
            QuickPanelViewModel.panelKeyCommand(
                modifierFlags: [.command],
                charactersIgnoringModifiers: "p"
            ) == .togglePin
        )

        try check(
            MainWindowViewModel.mainWindowKeyCommand(
                modifierFlags: [.command],
                charactersIgnoringModifiers: "f"
            ) == .focusSearch
        )
        try check(
            MainWindowViewModel.mainWindowKeyCommand(
                modifierFlags: [.command, .shift],
                charactersIgnoringModifiers: "C"
            ) == .copySelectedEntry
        )
        try check(
            MainWindowViewModel.mainWindowKeyCommand(
                modifierFlags: [.command],
                charactersIgnoringModifiers: "e"
            ) == .editSelectedEntry
        )
        try check(
            MainWindowViewModel.mainWindowKeyCommand(
                modifierFlags: [.command],
                charactersIgnoringModifiers: "n"
            ) == .createNewEntry
        )
        try check(
            MainWindowViewModel.mainWindowKeyCommand(
                modifierFlags: [.command],
                charactersIgnoringModifiers: "s"
            ) == .saveInlineDraft
        )
        try check(
            MainWindowViewModel.mainWindowKeyCommand(
                modifierFlags: [.command],
                charactersIgnoringModifiers: ","
            ) == .openSettings
        )
        try check(
            QuickPanelViewModel.panelKeyCommand(
                keyCode: 45,
                modifierFlags: [.command],
                charactersIgnoringModifiers: "n"
            ) == .quickCreateEntry
        )
        try check(
            MainWindowViewModel.mainWindowKeyCommand(
                keyCode: 126,
                modifierFlags: [],
                charactersIgnoringModifiers: nil
            ) == .moveSelectionUp
        )
        try check(
            MainWindowViewModel.mainWindowKeyCommand(
                keyCode: 125,
                modifierFlags: [],
                charactersIgnoringModifiers: nil
            ) == .moveSelectionDown
        )

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textView.string = "搜索关键词"
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        try check(MainWindowViewModel.shouldAllowArrowKeyNavigation(firstResponder: textView))

        textView.setSelectedRange(NSRange(location: 0, length: 2))
        try check(!MainWindowViewModel.shouldAllowArrowKeyNavigation(firstResponder: textView))

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.setMarkedText("pinyin", selectedRange: NSRange(location: 0, length: 6), replacementRange: NSRange(location: 0, length: 0))
        try check(!MainWindowViewModel.shouldAllowArrowKeyNavigation(firstResponder: textView))
        textView.unmarkText()
        try check(MainWindowViewModel.shouldAllowArrowKeyNavigation(firstResponder: textView))

        // Multi-line non-field-editor NSTextView should not have arrow keys swallowed
        textView.isFieldEditor = false
        textView.string = "第一行\n第二行"
        try check(!MainWindowViewModel.shouldAllowArrowKeyNavigation(firstResponder: textView))

        // Even single-line content inside a scroll-view-backed TextEditor should not have arrow keys swallowed
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let editorTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        editorTextView.isFieldEditor = false
        editorTextView.string = "单行正文但处于多行编辑器容器内"
        scrollView.documentView = editorTextView
        try check(!MainWindowViewModel.shouldAllowArrowKeyNavigation(firstResponder: editorTextView))
    }

    static func verifyQuickPanelScopeSafetyAndCopyUsage() throws {
        try runAsyncOnMainRunLoop {
            try await verifyQuickPanelScopeSafetyAndCopyUsageAsync()
        }
    }

    static func verifyQuickPanelScopeSafetyAndCopyUsageAsync() async throws {
        try await withTempDatabaseAsync { manager, _ in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)
            let settingsRepo = SettingsRepository(dbQueue: manager.dbQueue)
            let logRepo = LogRepository(dbQueue: manager.dbQueue)
            let defaultProject = try unwrap(projectRepo.fetchDefault())

            let appState = AppState()
            appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

            let entryA = Entry(projectId: defaultProject.id, title: "Alpha", content: "Alpha body", useCount: 10, lastUsedAt: Date())
            let entryB = Entry(projectId: defaultProject.id, title: "Beta", content: "Beta body", useCount: 5, lastUsedAt: Date())
            try entryRepo.create(entryA)
            try entryRepo.create(entryB)

            let spyClipboard = SpyClipboardService()
            let spyPaste = SpyPasteService()
            let stubPermission = StubPermissionService()
            let executeService = ExecuteService(
                clipboardService: spyClipboard,
                pasteService: spyPaste,
                entryRepository: entryRepo,
                logRepository: logRepo,
                permissionService: stubPermission,
                targetApplicationProvider: { nil },
                currentFrontApplicationProvider: { nil }
            )

            var didClosePanel = false
            let viewModel = QuickPanelViewModel(
                appState: appState,
                projectRepository: projectRepo,
                entryRepository: entryRepo,
                settingsRepository: settingsRepo,
                searchService: EntrySearchService(entryRepository: entryRepo),
                executeService: executeService,
                clipboardService: spyClipboard,
                permissionService: PermissionService(),
                onClosePanel: { didClosePanel = true }
            )

            viewModel.prepareForPresentation()
            await waitUntilAsync(timeout: 1.5) {
                !viewModel.isScopeSearchInFlight && viewModel.entries.count == 2
            }
            try check(viewModel.entries.count == 2)

            // Trigger a scope change and verify in-flight guard blocks stale pointer clicks
            // while deferring keyboard shortcut ⌘1 to the new search results.
            viewModel.query = "Beta"
            try check(viewModel.isScopeSearchInFlight)
            viewModel.executeEntry(at: 0, triggerSource: .pointerClick)
            try check(spyClipboard.writtenTexts.isEmpty)

            _ = viewModel.handlePanelKeyCommand(.executeEntry(number: 1))
            await waitUntilAsync(timeout: 1.5) {
                !viewModel.isScopeSearchInFlight
            }
            try check(viewModel.entries.map(\.id) == [entryB.id])
            try check(spyClipboard.writtenTexts == ["Beta body"])

            // Verify ⌘C copySelectionOnly uses ClipboardService and increments useCount
            didClosePanel = false
            viewModel.copySelectionOnly()
            try check(spyClipboard.writtenTexts.last == "Beta body")
            try check(didClosePanel)
            let updatedBeta = try unwrap(entryRepo.fetchById(entryB.id))
            try check(updatedBeta.useCount >= 6)

            // Verify global search fallback when current project + default project have no match
            let otherProject = Project(id: "proj-other", name: "后端专项", groupKind: .project)
            let archivedProject = Project(id: "proj-archived", name: "归档老项目", groupKind: .project, isArchived: true)
            try projectRepo.create(otherProject)
            try projectRepo.create(archivedProject)
            let crossProjectEntry = Entry(
                id: "entry-cross",
                projectId: otherProject.id,
                title: "Kubernetes 部署排障",
                content: "kubectl describe pod",
                tags: ["k8s"]
            )
            let archivedEntry = Entry(
                id: "entry-archived-only",
                projectId: archivedProject.id,
                title: "Kubernetes 归档旧方案",
                content: "legacy k8s",
                tags: ["k8s"]
            )
            try entryRepo.create(crossProjectEntry)
            try entryRepo.create(archivedEntry)

            viewModel.query = "Kubernetes"
            await waitUntilAsync(timeout: 1.5) {
                !viewModel.isScopeSearchInFlight
            }
            try check(viewModel.isShowingGlobalFallback)
            try check(viewModel.entries.map(\.id) == [crossProjectEntry.id])

            // Verify ⌘N quickCreateEntryFromPanel creates an entry directly from the non-matching query
            viewModel.query = "快速记录新想法 #idea"
            await waitUntilAsync(timeout: 1.5) {
                !viewModel.isScopeSearchInFlight
            }
            try check(viewModel.entries.isEmpty)
            _ = viewModel.handlePanelKeyCommand(.quickCreateEntry)
            await waitUntilAsync(timeout: 1.5) {
                !viewModel.isScopeSearchInFlight && viewModel.query.isEmpty
            }
            let createdFromPanel = try entryRepo.fetchByProject(defaultProject.id).first(where: { $0.content.contains("快速记录新想法") })
            try check(createdFromPanel != nil)
        }
    }

    static func verifyTransferAndStorageMaintenance() throws {
        try withTempDatabase { manager, dbURL in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)
            let logRepo = LogRepository(dbQueue: manager.dbQueue)
            let maintenance = StorageMaintenanceService(
                dbQueue: manager.dbQueue,
                logRepository: logRepo,
                databaseURL: dbURL
            )
            let transfer = LibraryTransferService(
                projectRepository: projectRepo,
                entryRepository: entryRepo,
                storageMaintenanceService: maintenance
            )

            let defaultProject = try unwrap(projectRepo.fetchDefault())
            try entryRepo.create(
                Entry(
                    id: "md-entry-1",
                    projectId: defaultProject.id,
                    title: "导出测试词条",
                    content: "  Indented First Line\n  ```\n  nested code\n  ```\nSecond Line",
                    tags: ["export", "code review"]
                )
            )

            let exportURL = dbURL.deletingLastPathComponent().appendingPathComponent("export.json")
            _ = try transfer.exportJSON(to: exportURL)
            try check(FileManager.default.fileExists(atPath: exportURL.path))

            let mdURL = dbURL.deletingLastPathComponent().appendingPathComponent("export.md")
            _ = try transfer.exportMarkdown(to: mdURL)
            try check(FileManager.default.fileExists(atPath: mdURL.path))

            // Verify Markdown round-trip preserves leading indentation, indented fences, and multi-word tags
            try entryRepo.delete(id: "md-entry-1")
            _ = try transfer.importMarkdown(from: mdURL)
            let roundTripped = try unwrap(entryRepo.fetchById("md-entry-1"))
            try check(roundTripped.content == "  Indented First Line\n  ```\n  nested code\n  ```\nSecond Line")
            try check(roundTripped.tags == ["export", "code review"])

            // Pre-import safety backup should not block subsequent automatic launch backup
            let snapshotAfterImport = try maintenance.performLaunchMaintenance()
            try check(snapshotAfterImport.backupCount >= 2)
        }
    }

    static func verifyLibraryJSONImportRollback() throws {
        try withTempDatabase { manager, dbURL in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)
            let logRepo = LogRepository(dbQueue: manager.dbQueue)
            let maintenance = StorageMaintenanceService(
                dbQueue: manager.dbQueue,
                logRepository: logRepo,
                databaseURL: dbURL
            )
            let transfer = LibraryTransferService(
                projectRepository: projectRepo,
                entryRepository: entryRepo,
                storageMaintenanceService: maintenance
            )

            try manager.dbQueue.write { db in
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
                content: "Blocked by trigger"
            )
            let payload = PromptPanelLibraryExport(
                formatVersion: PromptPanelLibraryExport.currentFormatVersion,
                exportedAt: Date(),
                projects: [importedProject],
                entries: [failingEntry]
            )
            let importURL = dbURL.deletingLastPathComponent().appendingPathComponent("rollback-import.json")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(payload).write(to: importURL)

            var didThrow = false
            do {
                _ = try transfer.importJSON(from: importURL)
            } catch {
                didThrow = true
            }
            try check(didThrow, "Expected importJSON to fail and roll back when trigger aborts")
            try check(try projectRepo.fetchById(importedProject.id) == nil, "Rollback project must not remain after failed import")
            try check(try entryRepo.fetchById(failingEntry.id) == nil)
        }
    }

    static func verifyManualBackupRetention() throws {
        try withTempDatabase { manager, dbURL in
            let logRepo = LogRepository(dbQueue: manager.dbQueue)
            let maintenance = StorageMaintenanceService(
                dbQueue: manager.dbQueue,
                logRepository: logRepo,
                databaseURL: dbURL
            )

            let backupTarget = Constants.automaticBackupRetentionCount + 2
            for _ in 0..<backupTarget {
                _ = try maintenance.createManualBackup()
            }

            let snapshot = try maintenance.healthSnapshot()
            try check(snapshot.backupCount == backupTarget)
            try check(snapshot.latestBackupURL != nil)
        }
    }

    static func verifyWorkspaceKindsArchiveVersionsAndCloning() throws {
        try withTempDatabase { manager, _ in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)

            let defaultProject = try unwrap(projectRepo.fetchDefault())
            try check(defaultProject.groupKind == .category)
            try check(defaultProject.isSystemProtected)

            let inboxProject = try unwrap(projectRepo.fetchInbox())
            try check(inboxProject.groupKind == .inbox)
            try check(inboxProject.name == Constants.inboxProjectName)
            try check(inboxProject.isSystemProtected)

            // Create a reusable category and an active project
            let videoCategory = Project(name: "视频制作", groupKind: .category)
            let clientProject = Project(name: "客户端重构项目", groupKind: .project)
            try projectRepo.create(videoCategory)
            try projectRepo.create(clientProject)

            // Archive and unarchive project
            try projectRepo.setArchived(id: clientProject.id, isArchived: true)
            let activeOnly = try projectRepo.fetchAll(includeArchived: false)
            try check(!activeOnly.contains(where: { $0.id == clientProject.id }))
            let allWithArchived = try projectRepo.fetchAll(includeArchived: true)
            try check(allWithArchived.first(where: { $0.id == clientProject.id })?.isArchived == true)

            try projectRepo.setArchived(id: clientProject.id, isArchived: false)
            try check(try projectRepo.fetchById(clientProject.id)?.isArchived == false)

            // Version history lifecycle: v1 -> v2 -> restore v1 (creates v3)
            var prompt = Entry(
                projectId: videoCategory.id,
                title: "分镜生成提示词 v1",
                content: "请生成 5 个镜头的分镜脚本",
                type: Constants.EntryType.prompt.rawValue
            )
            try entryRepo.create(prompt)

            var versions = try entryRepo.fetchVersions(forEntryId: prompt.id)
            try check(versions.count == 1)
            try check(versions.first?.versionNumber == 1)

            prompt.title = "分镜生成提示词 v2"
            prompt.content = "请生成 8 个镜头的电影感分镜脚本，包含运镜说明"
            try entryRepo.update(prompt, changeNote: "扩充镜头要求")

            versions = try entryRepo.fetchVersions(forEntryId: prompt.id)
            try check(versions.count == 2)
            try check(versions.first?.versionNumber == 2)
            try check(versions.first?.changeNote == "扩充镜头要求")

            let v1 = try unwrap(versions.last)
            let restored = try entryRepo.restoreVersion(versionId: v1.id)
            try check(restored.title == "分镜生成提示词 v1")
            try check(restored.content == "请生成 5 个镜头的分镜脚本")

            versions = try entryRepo.fetchVersions(forEntryId: prompt.id)
            try check(versions.count == 3)
            try check(versions.first?.versionNumber == 3)

            // Clone from reusable category into a specific project
            let cloned = try entryRepo.cloneEntry(id: prompt.id, toProjectId: clientProject.id)
            try check(cloned.projectId == clientProject.id)
            try check(cloned.sourceEntryId == prompt.id)
            try check(cloned.content == restored.content)
            let clonedVersions = try entryRepo.fetchVersions(forEntryId: cloned.id)
            try check(clonedVersions.count == 1)

            // Todo completion state in Inbox without polluting version history
            let todoEntry = Entry(
                projectId: inboxProject.id,
                title: "整理手机端云同步字段",
                content: "待办：确认软删除与版本冲突合并策略",
                type: Constants.EntryType.todo.rawValue
            )
            try entryRepo.create(todoEntry)
            try entryRepo.setCompleted(id: todoEntry.id, isCompleted: true)
            let updatedTodo = try unwrap(entryRepo.fetchById(todoEntry.id))
            try check(updatedTodo.isCompleted)
            try check(try entryRepo.fetchVersions(forEntryId: todoEntry.id).count == 1)
        }
    }

    static func verifyReferenceWindowAndCloudSyncConflictPreservation() throws {
        // 1. Verify Cmd+Shift+N resolves to .openReferenceWindow
        let cmdShiftN = MainWindowViewModel.mainWindowKeyCommand(
            modifierFlags: [.command, .shift],
            charactersIgnoringModifiers: "N"
        )
        try check(cmdShiftN == .openReferenceWindow)

        // 2. Verify CloudSyncService bidirectional sync & Conflict-to-Version-History preservation
        try withTempDatabase { macManager, macDBURL in
            try withTempDatabase { mobileSimManager, _ in
                let macProjectRepo = ProjectRepository(dbQueue: macManager.dbQueue)
                let macEntryRepo = EntryRepository(dbQueue: macManager.dbQueue)
                let macSyncService = CloudSyncService(dbQueue: macManager.dbQueue)

                let mobileEntryRepo = EntryRepository(dbQueue: mobileSimManager.dbQueue)
                let mobileSyncService = CloudSyncService(dbQueue: mobileSimManager.dbQueue)

                let devCategory = Project(id: "cat-dev", name: "开发类", groupKind: .category)
                try macProjectRepo.create(devCategory)

                let sharedEntryId = "shared-entry-1"
                let baseDate = Date(timeIntervalSince1970: 1_710_000_000)
                let macInitialEntry = Entry(
                    id: sharedEntryId,
                    projectId: devCategory.id,
                    title: "Swift 并发检查清单",
                    content: "Mac 初始版本内容：检查 Sendable 与 MainActor",
                    type: Constants.EntryType.prompt.rawValue,
                    useCount: 3,
                    lastUsedAt: baseDate,
                    createdAt: baseDate,
                    updatedAt: baseDate
                )
                try macEntryRepo.create(macInitialEntry, changeNote: "Mac 初始创建")

                let sharedSyncFileURL = macDBURL
                    .deletingLastPathComponent()
                    .appendingPathComponent("PromptPanel-SharedSync.json")

                // Step A: Mac syncs to shared file
                let initialMacSync = try macSyncService.syncNow(
                    endpoint: sharedSyncFileURL.path,
                    apiKey: ""
                )
                try check(FileManager.default.fileExists(atPath: sharedSyncFileURL.path))
                try check(initialMacSync.conflictsPreservedInVersions == 0)

                // Step B: Mobile pulls from shared file, then edits the same entry with a newer timestamp,
                // while Mac ALSO edits the same entry locally before syncing!
                _ = try mobileSyncService.syncNow(endpoint: sharedSyncFileURL.path, apiKey: "")
                var mobileEdited = try unwrap(mobileEntryRepo.fetchById(sharedEntryId))
                mobileEdited.content = "手机端修改后的新内容：增加 CloudSync 冲突自动留存测试"
                mobileEdited.useCount = 5
                mobileEdited.updatedAt = baseDate.addingTimeInterval(300)
                try mobileEntryRepo.update(mobileEdited, changeNote: "手机端修改")

                // Mobile pushes its newer edit to shared file
                _ = try mobileSyncService.syncNow(endpoint: sharedSyncFileURL.path, apiKey: "")

                // Meanwhile on Mac, the user had made an offline local edit at +100s (older than mobile's +300s)
                var macOfflineEdited = try unwrap(macEntryRepo.fetchById(sharedEntryId))
                macOfflineEdited.content = "Mac 离线期间修改的本地内容（不应丢失）"
                macOfflineEdited.updatedAt = baseDate.addingTimeInterval(100)
                try macManager.dbQueue.write { db in
                    // Simulate un-snapshotted or local divergent state before sync
                    try macOfflineEdited.update(db)
                }

                // Step C: Mac syncs with shared file -> Mobile's +300s wins as current Entry,
                // AND Mac's +100s content is automatically preserved in entry_versions!
                let conflictSyncSummary = try macSyncService.syncNow(
                    endpoint: sharedSyncFileURL.path,
                    apiKey: ""
                )
                try check(conflictSyncSummary.entriesUpdated == 1)
                try check(conflictSyncSummary.conflictsPreservedInVersions == 1)

                let finalMacEntry = try unwrap(macEntryRepo.fetchById(sharedEntryId))
                try check(finalMacEntry.content == "手机端修改后的新内容：增加 CloudSync 冲突自动留存测试")
                try check(finalMacEntry.useCount == 5)

                let allMacVersions = try macEntryRepo.fetchVersions(forEntryId: sharedEntryId)
                try check(allMacVersions.contains(where: { $0.content == "Mac 离线期间修改的本地内容（不应丢失）" }))
                try check(allMacVersions.contains(where: { $0.content == "手机端修改后的新内容：增加 CloudSync 冲突自动留存测试" }))

                // Step D: Verify camelCase + fractional-seconds payload from Mobile/Python server decodes & preserves older incoming conflict
                let mobileCamelJSON = """
                {
                  "schemaVersion": 2,
                  "deviceId": "mobile-flutter-test",
                  "exportedAt": "2024-03-09T16:10:00.123456Z",
                  "projects": [
                    {
                      "id": "cat-dev",
                      "name": "开发类",
                      "isDefault": false,
                      "groupKindRaw": "category",
                      "isArchived": false,
                      "createdAt": "2024-03-09T16:00:00.000Z",
                      "updatedAt": "2024-03-09T16:00:00.000Z"
                    }
                  ],
                  "entries": [
                    {
                      "id": "shared-entry-1",
                      "projectId": "cat-dev",
                      "title": "Swift 并发检查清单",
                      "content": "另一台手机在稍早时间点的离线修改版本（同样不应丢失）",
                      "type": "prompt",
                      "isPinned": false,
                      "isCompleted": true,
                      "sortOrder": 0,
                      "useCount": 9,
                      "lastUsedAt": "2024-03-09T16:03:00.500Z",
                      "createdAt": "2024-03-09T16:00:00.000Z",
                      "updatedAt": "2024-03-09T16:02:00.250Z",
                      "tags": ["swift", "concurrency"]
                    }
                  ],
                  "versions": []
                }
                """.data(using: .utf8)!
                let decodedMobileEnvelope = try CloudSyncService.makeDecoder().decode(CloudSyncEnvelope.self, from: mobileCamelJSON)
                let camelMergeSummary = try macSyncService.mergeRemoteEnvelope(decodedMobileEnvelope)
                try check(camelMergeSummary.conflictsPreservedInVersions == 1)
                let macVersionsAfterCamelMerge = try macEntryRepo.fetchVersions(forEntryId: sharedEntryId)
                try check(macVersionsAfterCamelMerge.contains(where: { $0.content == "另一台手机在稍早时间点的离线修改版本（同样不应丢失）" }))
                try check(try unwrap(macEntryRepo.fetchById(sharedEntryId)).useCount == 9)
                let macDefaultProjects = try macProjectRepo.fetchAll(includeArchived: true).filter(\.isDefault)
                try check(macDefaultProjects.count == 1, "CloudSync must not duplicate default projects across devices")

                // Step D2: Verify mixed snake_case + camelCase JSON (Android mutating camelCase on a Mac-originated snake_case record) picks newer camelCase
                let macDefaultId = macDefaultProjects[0].id
                let mixedPhoneEditJSON = """
                {
                  "schemaVersion": 2,
                  "deviceId": "android-mixed-case-client",
                  "exportedAt": "2030-01-01T12:00:00.000Z",
                  "projects": [],
                  "entries": [
                    {
                      "id": "\(sharedEntryId)",
                      "project_id": "\(macDefaultId)",
                      "projectId": "\(macDefaultId)",
                      "title": "手机上最新改动的标题",
                      "content": "手机上修改了便签，携带旧 updated_at 与新 updatedAt 时必须正常同步到电脑",
                      "type": "note",
                      "is_pinned": false,
                      "isPinned": true,
                      "is_completed": false,
                      "isCompleted": true,
                      "sort_order": 0,
                      "use_count": 9,
                      "useCount": 12,
                      "created_at": "2024-03-09T16:00:00.000Z",
                      "updated_at": "2024-03-09T16:00:00.000Z",
                      "updatedAt": "2030-01-01T12:00:00.000Z",
                      "tags": ["mobile", "synced"]
                    }
                  ],
                  "versions": []
                }
                """.data(using: .utf8)!
                let decodedMixedEnvelope = try CloudSyncService.makeDecoder().decode(CloudSyncEnvelope.self, from: mixedPhoneEditJSON)
                let mixedMergeSummary = try macSyncService.mergeRemoteEnvelope(decodedMixedEnvelope)
                try check(mixedMergeSummary.entriesUpdated == 1, "Newer camelCase updatedAt must win over stale snake_case updated_at")
                let syncedFromMixedPhone = try unwrap(macEntryRepo.fetchById(sharedEntryId))
                try check(syncedFromMixedPhone.title == "手机上最新改动的标题")
                try check(syncedFromMixedPhone.content == "手机上修改了便签，携带旧 updated_at 与新 updatedAt 时必须正常同步到电脑")
                try check(syncedFromMixedPhone.isCompleted == true)
                try check(syncedFromMixedPhone.isPinned == true)
                try check(syncedFromMixedPhone.useCount == 12)

                // Step E: Verify soft-delete tombstones prevent resurrection across CloudSync
                try macEntryRepo.delete(id: sharedEntryId)
                try check(try macEntryRepo.fetchById(sharedEntryId) == nil)
                _ = try macSyncService.syncNow(endpoint: sharedSyncFileURL.path, apiKey: "")
                try check(try macEntryRepo.fetchById(sharedEntryId) == nil, "Soft-deleted entry must not resurrect on sync")
                _ = try mobileSyncService.syncNow(endpoint: sharedSyncFileURL.path, apiKey: "")
                try check(try mobileEntryRepo.fetchById(sharedEntryId) == nil, "Soft-delete tombstone must propagate to peer device")

                // Step F: Verify subpath health check URL resolution
                try check(CloudSyncService.resolvedHealthPath(from: "") == "/v1/health")
                try check(CloudSyncService.resolvedHealthPath(from: "/v1/sync") == "/v1/health")
                try check(CloudSyncService.resolvedHealthPath(from: "/promptpanel/v1/sync") == "/promptpanel/v1/health")
                try check(CloudSyncService.resolvedHealthPath(from: "/api/sync") == "/api/v1/health")

                // Step G: Verify AES-256-GCM+Gzip (HKDF-SHA256) envelope encryption & SettingsRepository token encryption
                let testToken = "pp_live_secret_token_2026_aead_verify"
                let sealedPayload = try CloudSyncCrypto.sealEnvelopeData(mobileCamelJSON, apiKey: testToken)
                let sealedString = String(data: sealedPayload, encoding: .utf8) ?? ""
                try check(sealedString.contains("\"cipher\":\"aes-256-gcm+gzip\""))
                try check(!sealedString.contains("Swift 并发检查清单"), "Plaintext entry title must never appear in AES-256-GCM ciphertext")
                let openedPayload = try CloudSyncCrypto.openEnvelopeData(sealedPayload, apiKey: testToken)
                try check(openedPayload == mobileCamelJSON)

                var wrongKeyThrew = false
                do {
                    _ = try CloudSyncCrypto.openEnvelopeData(sealedPayload, apiKey: "pp_live_wrong_token_000000000000")
                } catch {
                    wrongKeyThrew = true
                }
                try check(wrongKeyThrew, "AES-256-GCM authentication tag must reject wrong token")

                let macSettingsRepo = SettingsRepository(dbQueue: macManager.dbQueue)
                try macSettingsRepo.setCloudSyncApiKey(testToken)
                let rawStoredKey = try macManager.dbQueue.read { db in
                    try String.fetchOne(db, sql: "SELECT value FROM app_settings WHERE key = ?", arguments: [Constants.SettingsKey.cloudSyncApiKey])
                }
                try check(rawStoredKey?.hasPrefix("enc:v2:") == true, "API key in app_settings must be encrypted at rest")
                try check(try macSettingsRepo.getCloudSyncApiKey() == testToken)
            }
        }
    }

    static func verifyCloudSyncDataLossProtectionAndThrottledBackups() throws {
        try withTempDatabase { manager, dbURL in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)
            let logRepo = LogRepository(dbQueue: manager.dbQueue)
            let maintenance = StorageMaintenanceService(
                dbQueue: manager.dbQueue,
                logRepository: logRepo,
                databaseURL: dbURL
            )
            let syncService = CloudSyncService(
                dbQueue: manager.dbQueue,
                storageMaintenanceService: maintenance
            )

            // 1. Verify high-frequency sync backup throttling:
            // Repeated calls within the throttle window must only create 1 sync backup and 1 sync-guard backup
            let firstSyncBackup = try maintenance.createSyncSafetyBackupIfNeeded(isGuardTrigger: false)
            try check(firstSyncBackup != nil)
            for _ in 0..<5 {
                let throttled = try maintenance.createSyncSafetyBackupIfNeeded(isGuardTrigger: false)
                try check(throttled == nil, "Throttled routine sync backup must not duplicate within minimum interval")
            }

            let firstGuardBackup = try maintenance.createSyncSafetyBackupIfNeeded(isGuardTrigger: true)
            try check(firstGuardBackup != nil)
            let secondGuardBackup = try maintenance.createSyncSafetyBackupIfNeeded(isGuardTrigger: true)
            try check(secondGuardBackup == nil, "Throttled guard backup must not duplicate within minimum interval")

            // Sync backups must not prevent launch maintenance from creating a launch backup
            let launchSnapshot = try maintenance.performLaunchMaintenance()
            try check(launchSnapshot.backupCount == 3)

            // 2. Verify strict envelope validation rejects non-envelope gateway JSON
            let invalidGatewayJSON = #"{"status":"ok","message":"gateway proxy response"}"#.data(using: .utf8)!
            var gatewayDecodeFailed = false
            do {
                _ = try CloudSyncService.makeDecoder().decode(CloudSyncEnvelope.self, from: invalidGatewayJSON)
            } catch {
                gatewayDecodeFailed = true
            }
            try check(gatewayDecodeFailed, "Non-envelope JSON must be rejected instead of decoding as an empty sync envelope")

            // 3. Seed 4 active entries in a custom project and sync to shared file
            let baseTime = Date(timeIntervalSince1970: 1_720_000_000)
            let teamProject = Project(
                id: "proj-team",
                name: "核心词库项目",
                groupKind: .project,
                createdAt: baseTime,
                updatedAt: baseTime
            )
            try projectRepo.create(teamProject)

            for i in 1...4 {
                let entry = Entry(
                    id: "protected-entry-\(i)",
                    projectId: teamProject.id,
                    title: "关键提示词 \(i)",
                    content: "核心业务内容 \(i) — 绝不能因云端异常而丢失",
                    createdAt: baseTime,
                    updatedAt: baseTime
                )
                try entryRepo.create(entry)
            }

            let syncFileURL = dbURL.deletingLastPathComponent().appendingPathComponent("CloudSync-GuardTest.json")
            _ = try syncService.syncNow(endpoint: syncFileURL.path, apiKey: "")

            // 4. Simulate cloud mass-tombstone disaster: remote marks the project and all 4 entries as deleted with a newer timestamp!
            let disasterTime = baseTime.addingTimeInterval(600)
            var poisonedProject = teamProject
            poisonedProject.deletedAt = disasterTime
            poisonedProject.updatedAt = disasterTime

            let poisonedEntries: [Entry] = (1...4).map { i in
                Entry(
                    id: "protected-entry-\(i)",
                    projectId: teamProject.id,
                    title: "关键提示词 \(i)",
                    content: "核心业务内容 \(i) — 绝不能因云端异常而丢失",
                    createdAt: baseTime,
                    updatedAt: disasterTime,
                    deletedAt: disasterTime
                )
            }
            let poisonedEnvelope = CloudSyncEnvelope(
                deviceId: "poisoned-cloud",
                exportedAt: disasterTime,
                projects: [poisonedProject],
                entries: poisonedEntries,
                versions: []
            )
            try CloudSyncService.makeEncoder().encode(poisonedEnvelope).write(to: syncFileURL, options: .atomic)

            // Sync against the poisoned cloud file: circuit breaker must block the mass wipe and heal the cloud file!
            let guardSummary = try syncService.syncNow(endpoint: syncFileURL.path, apiKey: "")
            try check(guardSummary.protectedEntriesCount == 4, "Circuit breaker must protect all 4 active entries from mass deletion")
            try check(guardSummary.protectedProjectsCount >= 1, "Circuit breaker must protect the parent project from deletion")

            for i in 1...4 {
                let localEntry = try unwrap(entryRepo.fetchById("protected-entry-\(i)"))
                try check(localEntry.deletedAt == nil)
                try check(localEntry.projectId == teamProject.id)
            }
            try check(try projectRepo.fetchById(teamProject.id) != nil)

            // Verify the cloud file itself was healed by the local push
            let healedCloudData = try Data(contentsOf: syncFileURL)
            let healedCloudEnvelope = try CloudSyncService.makeDecoder().decode(CloudSyncEnvelope.self, from: healedCloudData)
            let healedActiveIds = Set(healedCloudEnvelope.entries.filter { $0.deletedAt == nil }.map(\.id))
            for i in 1...4 {
                try check(healedActiveIds.contains("protected-entry-\(i)"), "Cloud sync file must be re-healed with active local entries")
            }

            // 5. Simulate complete cloud wipe (empty envelope on cloud) -> local must preserve all data and re-seed cloud
            let wipedEnvelope = CloudSyncEnvelope(
                deviceId: "wiped-cloud-server",
                exportedAt: disasterTime.addingTimeInterval(1200),
                projects: [],
                entries: [],
                versions: []
            )
            try CloudSyncService.makeEncoder().encode(wipedEnvelope).write(to: syncFileURL, options: .atomic)
            _ = try syncService.syncNow(endpoint: syncFileURL.path, apiKey: "")
            try check(try entryRepo.fetchByProject(teamProject.id).count == 4, "Local entries must survive an empty cloud reset")

            let reseededCloudData = try Data(contentsOf: syncFileURL)
            let reseededEnvelope = try CloudSyncService.makeDecoder().decode(CloudSyncEnvelope.self, from: reseededCloudData)
            try check(reseededEnvelope.entries.filter { $0.deletedAt == nil }.count >= 4, "Empty cloud must be re-seeded from local library")

            // 6. Verify manual soft-delete recovery (`recoverDeletedAndSync`)
            try entryRepo.delete(id: "protected-entry-1")
            try check(try entryRepo.fetchById("protected-entry-1") == nil)
            let recoveryResult = try syncService.recoverDeletedAndSync(endpoint: syncFileURL.path, apiKey: "")
            try check(recoveryResult.entriesRestored >= 1)
            try check(try entryRepo.fetchById("protected-entry-1") != nil, "Soft-deleted entry must be restored by recoverDeletedAndSync")
        }
    }

    static func verifyCompletedRankingCleanupAndArchivedExclusion() throws {
        try withTempDatabase { manager, _ in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)
            let inbox = try unwrap(projectRepo.fetchInbox())
            let activeProject = Project(id: "proj-active-rank", name: "活跃项目", groupKind: .project)
            let archivedProject = Project(id: "proj-archived-rank", name: "归档项目", groupKind: .project, isArchived: true)
            try projectRepo.create(activeProject)
            try projectRepo.create(archivedProject)

            let oldDate = Date(timeIntervalSinceNow: -86_400)
            let now = Date()

            // Unfinished entry is unpinned and older; completed entry is pinned, heavily used, and updated right now!
            let unfinishedTodo = Entry(
                id: "todo-open",
                projectId: inbox.id,
                title: "未完成待办",
                content: "必须排在前面",
                type: Constants.EntryType.todo.rawValue,
                isPinned: false,
                isCompleted: false,
                useCount: 0,
                createdAt: oldDate,
                updatedAt: oldDate
            )
            let completedPinnedNote = Entry(
                id: "note-done-pinned",
                projectId: inbox.id,
                title: "已完成置顶便签",
                content: "即便置顶且刚更新也应下沉",
                type: Constants.EntryType.note.rawValue,
                isPinned: true,
                isCompleted: true,
                useCount: 50,
                lastUsedAt: now,
                createdAt: oldDate,
                updatedAt: now
            )
            let activeCompleted = Entry(
                id: "active-done",
                projectId: activeProject.id,
                title: "活跃项目已完成项",
                content: "active completed",
                type: Constants.EntryType.todo.rawValue,
                isCompleted: true
            )
            let archivedEntry = Entry(
                id: "archived-note",
                projectId: archivedProject.id,
                title: "归档项目词条",
                content: "archived body",
                type: Constants.EntryType.note.rawValue,
                isCompleted: false
            )

            try entryRepo.create(completedPinnedNote)
            try entryRepo.create(unfinishedTodo)
            try entryRepo.create(activeCompleted)
            try entryRepo.create(archivedEntry)

            // 1. EntryRanking in-memory & SQL order: unfinished always ranks before completed (even pinned + newer)
            try check(EntryRanking.isOrderedBefore(unfinishedTodo, completedPinnedNote, currentProjectId: inbox.id, now: now))
            try check(!EntryRanking.isOrderedBefore(completedPinnedNote, unfinishedTodo, currentProjectId: inbox.id, now: now))

            let inboxFetched = try entryRepo.fetchByProject(inbox.id)
            try check(inboxFetched.map(\.id) == [unfinishedTodo.id, completedPinnedNote.id])

            // Toggle unfinishedTodo to completed -> updatedAt = now; add a new unfinished item and verify ranking
            let secondUnfinished = Entry(
                id: "todo-open-2",
                projectId: inbox.id,
                title: "第二条未完成",
                content: "保持在顶部",
                type: Constants.EntryType.todo.rawValue,
                createdAt: oldDate,
                updatedAt: oldDate
            )
            try entryRepo.create(secondUnfinished)
            try entryRepo.setCompleted(id: unfinishedTodo.id, isCompleted: true)

            let reFetchedInbox = try entryRepo.fetchByProject(inbox.id)
            try check(reFetchedInbox.first?.id == secondUnfinished.id, "Toggling completion must sink item below unfinished entries")
            let panelSorted = QuickPanelViewModel.applyPanelRankingSort(reFetchedInbox, currentProjectId: inbox.id, now: Date())
            try check(panelSorted.first?.id == secondUnfinished.id)

            // 2. fetchAll(excludeArchivedProjects:)
            let allIncludingArchived = try entryRepo.fetchAll(excludeArchivedProjects: false)
            try check(allIncludingArchived.contains(where: { $0.id == archivedEntry.id }))
            let nonArchivedOnly = try entryRepo.fetchAll(excludeArchivedProjects: true)
            try check(!nonArchivedOnly.contains(where: { $0.id == archivedEntry.id }))
            try check(nonArchivedOnly.contains(where: { $0.id == secondUnfinished.id }))

            // 3. deleteCompleted(projectId:) scoped & global
            let scopedDeleted = try entryRepo.deleteCompleted(projectId: inbox.id)
            try check(scopedDeleted == 2, "Expected 2 completed entries soft-deleted in inbox")
            try check(try entryRepo.fetchByProject(inbox.id).map(\.id) == [secondUnfinished.id])
            try check(try entryRepo.fetchById(activeCompleted.id) != nil, "Completed entry in another project must remain untouched")

            let globalDeleted = try entryRepo.deleteCompleted(projectId: nil)
            try check(globalDeleted == 1, "Expected remaining 1 completed entry soft-deleted globally")
            try check(try entryRepo.fetchById(activeCompleted.id) == nil)
        }
    }

    static func verifyQuickPanelAllScopeCaptureFilterHoverAndPreview() throws {
        try runAsyncOnMainRunLoop {
            try await verifyQuickPanelAllScopeCaptureFilterHoverAndPreviewAsync()
        }
    }

    static func verifyQuickPanelAllScopeCaptureFilterHoverAndPreviewAsync() async throws {
        try await withTempDatabaseAsync { manager, _ in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)
            let settingsRepo = SettingsRepository(dbQueue: manager.dbQueue)
            let logRepo = LogRepository(dbQueue: manager.dbQueue)
            let defaultProject = try unwrap(projectRepo.fetchDefault())
            let inboxProject = try unwrap(projectRepo.fetchInbox())

            let projectAlpha = Project(id: "proj-alpha", name: "前端工程", groupKind: .project)
            let archivedProject = Project(id: "proj-old", name: "归档老工程", groupKind: .project, isArchived: true)
            try projectRepo.create(projectAlpha)
            try projectRepo.create(archivedProject)

            let promptEntry = Entry(
                id: "qp-prompt",
                projectId: defaultProject.id,
                title: "系统架构评审 Prompt",
                content: "请评审以下微服务边界与容错方案",
                type: Constants.EntryType.prompt.rawValue
            )
            let codeEntry = Entry(
                id: "qp-code",
                projectId: projectAlpha.id,
                title: "Debounce Hook",
                content: "function useDebounce(value, delay) { return value; }",
                type: Constants.EntryType.code.rawValue
            )
            let archivedSecret = Entry(
                id: "qp-archived",
                projectId: archivedProject.id,
                title: "Debounce Legacy",
                content: "archived legacy snippet",
                type: Constants.EntryType.code.rawValue
            )
            try entryRepo.create(promptEntry)
            try entryRepo.create(codeEntry)
            try entryRepo.create(archivedSecret)

            let appState = AppState()
            appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

            let spyClipboard = SpyClipboardService()
            let spyPaste = SpyPasteService()
            let stubPermission = StubPermissionService()
            let executeService = ExecuteService(
                clipboardService: spyClipboard,
                pasteService: spyPaste,
                entryRepository: entryRepo,
                logRepository: logRepo,
                permissionService: stubPermission,
                targetApplicationProvider: { nil },
                currentFrontApplicationProvider: { nil }
            )

            var panelCloseCount = 0
            let viewModel = QuickPanelViewModel(
                appState: appState,
                projectRepository: projectRepo,
                entryRepository: entryRepo,
                settingsRepository: settingsRepo,
                searchService: EntrySearchService(entryRepository: entryRepo),
                executeService: executeService,
                clipboardService: spyClipboard,
                permissionService: PermissionService(),
                onClosePanel: { panelCloseCount += 1 }
            )
            var mockClipboardText: String? = "剪贴板临时灵感\n第二行补充 #clip"
            viewModel.clipboardTextProvider = { mockClipboardText }

            viewModel.prepareForPresentation()
            viewModel.handleSearchFieldFocus(
                PanelFocusResult(token: viewModel.focusToken, succeeded: true, attempt: 1)
            )
            await waitUntilAsync(timeout: 1.0) {
                viewModel.isExecutionReady && !viewModel.isScopeSearchInFlight
            }

            // 1. All-projects scope ("__all_projects__") browse & search excludes archived projects and preserves persisted project ID
            viewModel.activateScope(QuickPanelViewModel.allProjectsScopeId)
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            try check(viewModel.isAllProjectsScope)
            try check(!viewModel.isShowingGlobalFallback)
            try check(try settingsRepo.getCurrentProjectId() == defaultProject.id)
            try check(viewModel.entries.contains(where: { $0.id == promptEntry.id }))
            try check(viewModel.entries.contains(where: { $0.id == codeEntry.id }))
            try check(!viewModel.entries.contains(where: { $0.id == archivedSecret.id }))

            viewModel.query = "Debounce"
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            try check(viewModel.entries.map(\.id) == [codeEntry.id])
            viewModel.query = ""
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }

            // 2. Tab / Shift+Tab scope cycling (`cycleScope`)
            let scopes = viewModel.availableScopeIds
            try check(scopes.first == QuickPanelViewModel.allProjectsScopeId)
            try check(scopes.contains(inboxProject.id))
            try check(scopes.contains(projectAlpha.id))
            viewModel.activateScope(scopes[0])
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            viewModel.cycleScope(1)
            try check(viewModel.currentProjectId == scopes[1])
            viewModel.cycleScope(-1)
            try check(viewModel.currentProjectId == scopes[0])
            viewModel.cycleScope(-1)
            try check(viewModel.currentProjectId == scopes.last)

            // 3. Quick-capture prefixes (`; `, `n `, `t `, `todo:`) enter capture mode and save on Enter without pasting old entries
            viewModel.activateScope(projectAlpha.id)
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            let clipboardWritesBeforeCapture = spyClipboard.writtenTexts.count

            try check(QuickPanelViewModel.parseQuickCapture(from: "n 会议纪要 #sync")?.type == .note)
            try check(QuickPanelViewModel.parseQuickCapture(from: "todo: 修复样式细节 #ui")?.type == .todo)

            viewModel.query = "; 周五发版检查清单 #release #mac"
            try check(viewModel.isQuickCaptureMode)
            let noteDraft = try unwrap(viewModel.quickCaptureDraft)
            try check(noteDraft.type == .note)
            try check(noteDraft.tags == ["release", "mac"])
            viewModel.executeSelection(triggerSource: .keyboardSubmit)
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            try check(spyClipboard.writtenTexts.count == clipboardWritesBeforeCapture, "Enter in quick-capture mode must save note, not execute/copy stale entry")
            try check(viewModel.query.isEmpty)
            try check(viewModel.currentProjectId == projectAlpha.id, "Quick capture into inbox must keep current project scope unchanged")
            let savedQuickNote = try unwrap(
                entryRepo.fetchByProject(inboxProject.id).first(where: { $0.content.contains("周五发版检查清单") })
            )
            try check(savedQuickNote.type == Constants.EntryType.note.rawValue)
            try check(savedQuickNote.tags == ["release", "mac"])

            viewModel.query = "t 补充回归单测 #qa"
            try check(viewModel.quickCaptureDraft?.type == .todo)
            viewModel.executeSelection(triggerSource: .keyboardSubmit)
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            let savedQuickTodo = try unwrap(
                entryRepo.fetchByProject(inboxProject.id).first(where: { $0.content.contains("补充回归单测") })
            )
            try check(savedQuickTodo.type == Constants.EntryType.todo.rawValue)
            try check(savedQuickTodo.tags == ["qa"])

            // 3b. One-click direct typing mode (`startQuickCapture(type:)`) enters `; ` / `t `, closes overlays, bumps focusToken, and preserves body on mode switch
            viewModel.isScopeDropdownOpen = true
            viewModel.isPreviewPresented = true
            let tokenBeforeStartCapture = viewModel.focusToken
            viewModel.startQuickCapture(type: .note)
            try check(viewModel.query == "; ")
            try check(!viewModel.isScopeDropdownOpen)
            try check(!viewModel.isPreviewPresented)
            try check(viewModel.focusToken == tokenBeforeStartCapture + 1)
            try check(viewModel.quickCaptureDraft?.type == .note)
            try check(viewModel.quickCaptureDraft?.hasContent == false)

            viewModel.query = "; 一键写便签直接切换类型 #ux"
            let tokenBeforeSwitchToTodo = viewModel.focusToken
            viewModel.startQuickCapture(type: .todo)
            try check(viewModel.query == "t 一键写便签直接切换类型 #ux")
            try check(viewModel.focusToken == tokenBeforeSwitchToTodo + 1)
            try check(viewModel.quickCaptureDraft?.type == .todo)
            viewModel.executeSelection(force: true, triggerSource: .pointerClick)
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            let savedDirectCapture = try unwrap(
                entryRepo.fetchByProject(inboxProject.id).first(where: { $0.content.contains("一键写便签直接切换类型") })
            )
            try check(savedDirectCapture.type == Constants.EntryType.todo.rawValue)
            try check(savedDirectCapture.tags == ["ux"])

            // 4. Shift+Enter (.quickCreateNote) & Option+Enter (.quickCreateTodo) key commands + clipboard quick-note
            try check(
                QuickPanelViewModel.panelKeyCommand(
                    keyCode: 36,
                    modifierFlags: [.shift],
                    charactersIgnoringModifiers: "\r"
                ) == .quickCreateNote
            )
            try check(
                QuickPanelViewModel.panelKeyCommand(
                    keyCode: 36,
                    modifierFlags: [.option],
                    charactersIgnoringModifiers: "\r"
                ) == .quickCreateTodo
            )
            try check(
                QuickPanelViewModel.panelKeyCommand(
                    modifierFlags: [.command],
                    charactersIgnoringModifiers: "y"
                ) == .togglePreview
            )

            viewModel.query = "快捷键直存便签 #fast"
            _ = viewModel.handlePanelKeyCommand(.quickCreateNote)
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            try check(
                try entryRepo.fetchByProject(inboxProject.id).contains(where: {
                    $0.content == "快捷键直存便签" && $0.type == Constants.EntryType.note.rawValue && $0.tags == ["fast"]
                })
            )

            viewModel.query = "快捷键直存待办 #next"
            _ = viewModel.handlePanelKeyCommand(.quickCreateTodo)
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            try check(
                try entryRepo.fetchByProject(inboxProject.id).contains(where: {
                    $0.content == "快捷键直存待办" && $0.type == Constants.EntryType.todo.rawValue && $0.tags == ["next"]
                })
            )

            viewModel.quickCreateNoteFromClipboard()
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            try check(
                try entryRepo.fetchByProject(inboxProject.id).contains(where: {
                    $0.title == "剪贴板临时灵感" && $0.type == Constants.EntryType.note.rawValue
                })
            )
            mockClipboardText = nil
            viewModel.refreshClipboardState()
            try check(!viewModel.hasClipboardText)

            // 5. Kind filter (`activeKindFilter`) + smart `defaultQuickCreateType`
            viewModel.activateScope(QuickPanelViewModel.allProjectsScopeId)
            await waitUntilAsync(timeout: 1.5) { !viewModel.isScopeSearchInFlight }
            let totalUnfiltered = viewModel.unfilteredEntries.count
            try check(totalUnfiltered >= 5)

            viewModel.activeKindFilter = .code
            try check(viewModel.entries.allSatisfy { $0.type == Constants.EntryType.code.rawValue })
            try check(viewModel.defaultQuickCreateType == .code)

            viewModel.activeKindFilter = .noteAndTodo
            try check(viewModel.entries.allSatisfy {
                $0.type == Constants.EntryType.note.rawValue || $0.type == Constants.EntryType.todo.rawValue
            })
            try check(viewModel.defaultQuickCreateType == .note)

            viewModel.activeKindFilter = .all
            try check(viewModel.entries.count == totalUnfiltered)

            // 6. Deterministic keyboard selection scroll revision (pointer selection never triggers scroll jumps)
            try check(viewModel.entries.count >= 3)
            let revisionBeforePointerSelect = viewModel.scrollSelectionRevision
            viewModel.selectEntry(at: 2)
            try check(viewModel.selectedIndex == 2, "Pointer selection should update selectedIndex")
            try check(
                viewModel.scrollSelectionRevision == revisionBeforePointerSelect,
                "Pointer selection must not increment scrollSelectionRevision"
            )

            viewModel.moveSelection(.up)
            try check(viewModel.selectedIndex == 1)
            try check(viewModel.scrollSelectionRevision == revisionBeforePointerSelect + 1)

            viewModel.moveSelection(.down)
            try check(viewModel.selectedIndex == 2)
            try check(viewModel.scrollSelectionRevision == revisionBeforePointerSelect + 2)

            viewModel.selectEntry(at: 0)
            try check(viewModel.selectedIndex == 0)
            try check(viewModel.scrollSelectionRevision == revisionBeforePointerSelect + 2)

            // 7. Full-text preview (`⌘Y`) & layered `Esc` dismissal (preview -> scope dropdown -> panel)
            try check(!viewModel.isPreviewPresented)
            _ = viewModel.handlePanelKeyCommand(.togglePreview)
            try check(viewModel.isPreviewPresented)

            viewModel.isScopeDropdownOpen = true
            _ = viewModel.handlePanelKeyCommand(.closePanel) // Esc #1 closes preview first
            try check(!viewModel.isPreviewPresented)
            try check(viewModel.isScopeDropdownOpen)
            try check(panelCloseCount == 0)

            _ = viewModel.handlePanelKeyCommand(.closePanel) // Esc #2 closes scope dropdown
            try check(!viewModel.isScopeDropdownOpen)
            try check(panelCloseCount == 0)

            _ = viewModel.handlePanelKeyCommand(.closePanel) // Esc #3 closes panel
            try check(panelCloseCount == 1)

            // 8. Chinese IME (`hasMarkedText()`) guard prevents swallowing Esc / Return / Shift+Enter / Option+Enter during Pinyin composition
            let imeTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
            imeTextView.setMarkedText(
                "zhongwen",
                selectedRange: NSRange(location: 8, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            try check(imeTextView.hasMarkedText())
            try check(AppDelegate.shouldDeferPanelCommandForActiveMarkedText(.closePanel, firstResponder: imeTextView))
            try check(AppDelegate.shouldDeferPanelCommandForActiveMarkedText(.quickCreateNote, firstResponder: imeTextView))
            try check(AppDelegate.shouldDeferPanelCommandForActiveMarkedText(.quickCreateTodo, firstResponder: imeTextView))

            var searchText = ""
            let searchCoordinator = KeyAwareSearchField.Coordinator(
                text: .init(get: { searchText }, set: { searchText = $0 })
            )
            var didTriggerEscape = false
            var didTriggerSubmit = false
            searchCoordinator.onEscape = { didTriggerEscape = true }
            searchCoordinator.onSubmit = { didTriggerSubmit = true }
            let dummyField = PromptSearchField()
            try check(
                !searchCoordinator.control(
                    dummyField,
                    textView: imeTextView,
                    doCommandBy: #selector(NSResponder.cancelOperation(_:))
                )
            )
            try check(
                !searchCoordinator.control(
                    dummyField,
                    textView: imeTextView,
                    doCommandBy: #selector(NSResponder.insertNewline(_:))
                )
            )
            try check(!didTriggerEscape && !didTriggerSubmit)

            imeTextView.unmarkText()
            try check(!imeTextView.hasMarkedText())
            try check(!AppDelegate.shouldDeferPanelCommandForActiveMarkedText(.closePanel, firstResponder: imeTextView))
            try check(
                searchCoordinator.control(
                    dummyField,
                    textView: imeTextView,
                    doCommandBy: #selector(NSResponder.cancelOperation(_:))
                )
            )
            try check(didTriggerEscape)
        }
    }

    static func verifyMainWindowQuickJotAutoTitleCleanupAndDebouncedAutoSave() throws {
        try runAsyncOnMainRunLoop {
            try await verifyMainWindowQuickJotAutoTitleCleanupAndDebouncedAutoSaveAsync()
        }
    }

    static func verifyMainWindowQuickJotAutoTitleCleanupAndDebouncedAutoSaveAsync() async throws {
        try await withTempDatabaseAsync { manager, dbURL in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)
            let settingsRepo = SettingsRepository(dbQueue: manager.dbQueue)
            let logRepo = LogRepository(dbQueue: manager.dbQueue)
            let maintenance = StorageMaintenanceService(
                dbQueue: manager.dbQueue,
                logRepository: logRepo,
                databaseURL: dbURL
            )
            let defaultProject = try unwrap(projectRepo.fetchDefault())
            let inboxProject = try unwrap(projectRepo.fetchInbox())
            let featureProject = Project(id: "proj-feature", name: "客户端专项", groupKind: .project)
            try projectRepo.create(featureProject)

            let appState = AppState()
            appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

            let viewModel = MainWindowViewModel(
                appState: appState,
                projectRepository: projectRepo,
                entryRepository: entryRepo,
                settingsRepository: settingsRepo,
                logRepository: logRepo,
                permissionService: PermissionService(),
                loginItemService: LoginItemService(),
                storageMaintenanceService: maintenance,
                updaterService: UpdaterService(),
                launchRecoveryReport: nil
            )
            defer { viewModel.cancelPendingBackgroundTasks() }

            viewModel.load()
            await waitUntilAsync(timeout: 1.5) { !viewModel.projects.isEmpty }
            await sleepMainActor(0.06)

            // 1. Inline Quick Jot (`submitQuickCapture`) in All Projects routes to `builtin-inbox` with #tags & auto-title
            viewModel.selectedProjectId = MainWindowViewModel.allProjectsSelection
            await sleepMainActor(0.06)
            viewModel.quickCaptureText = "记录线上压测结论\n峰值 QPS 稳定在 4200 #perf #report"
            let createdNote = try unwrap(viewModel.submitQuickCapture(type: .note))
            try check(createdNote.projectId == inboxProject.id)
            try check(createdNote.type == Constants.EntryType.note.rawValue)
            try check(createdNote.title == "记录线上压测结论")
            try check(createdNote.tags == ["perf", "report"])
            try check(viewModel.quickCaptureText.isEmpty)

            let createdTodo = try unwrap(
                viewModel.submitQuickCapture(text: "跟进压测监控告警阈值 #ops", type: .todo)
            )
            try check(createdTodo.projectId == inboxProject.id)
            try check(createdTodo.type == Constants.EntryType.todo.rawValue)
            try check(createdTodo.tags == ["ops"])

            // 2. EntryEditorSheet blank-title auto-derivation + `.note` default when in `builtin-inbox`
            viewModel.selectedProjectId = inboxProject.id
            await waitUntilAsync(timeout: 1.5) { viewModel.entries.count >= 2 }
            viewModel.startCreateEntry()
            let draftInInbox = try unwrap(viewModel.entryDraft)
            try check(draftInInbox.projectId == inboxProject.id)
            try check(draftInInbox.type == Constants.EntryType.note.rawValue, "Creating entry in Inbox must default to .note")

            viewModel.entryDraft?.title = "   "
            viewModel.entryDraft?.content = "   \n第一行自动生成标题测试内容\n第二行详细描述"
            try check(viewModel.saveEntryDraft())
            let autoTitledEntry = try unwrap(
                entryRepo.fetchByProject(inboxProject.id).first(where: { $0.title == "第一行自动生成标题测试内容" })
            )
            try check(autoTitledEntry.type == Constants.EntryType.note.rawValue)

            // 2b. Creating entry while filtered to `.todo` in Inbox defaults to `.todo`, and mobile QR pairing bundle validates cleanly
            viewModel.entryKindFilter = Constants.EntryType.todo.rawValue
            viewModel.startCreateEntry()
            try check(viewModel.entryDraft?.type == Constants.EntryType.todo.rawValue, "Creating entry while filtered to .todo must default to .todo")
            viewModel.entryDraft = nil
            viewModel.entryKindFilter = nil

            viewModel.cloudSyncEndpoint = "http://127.0.0.1:8787/v1/sync"
            try check(viewModel.mobileSyncEndpointWarning != nil, "Loopback endpoint must warn when pairing mobile")
            viewModel.cloudSyncEndpoint = "https://sync.example.com/v1/sync"
            viewModel.cloudSyncApiKey = "pp_live_pairing_secret_2026"
            let bundleJSON = try unwrap(viewModel.makeMobileSyncBundleJSON())
            try check(viewModel.mobileSyncEndpointWarning == nil)
            try check(bundleJSON.contains("\"endpoint\":\"https://sync.example.com/v1/sync\"") || bundleJSON.contains("\"endpoint\":\"https:\\/\\/sync.example.com\\/v1\\/sync\""))
            try check(bundleJSON.contains("pp_live_pairing_secret_2026"))
            try check(bundleJSON.contains("\"autoSync\":true"))

            // 3. Completed entries sink below unfinished entries in MainWindowViewModel + hideCompletedEntries + clearCompletedEntriesInVisibleScope
            viewModel.togglePin(createdTodo) // Pin the todo, then mark it completed -> must STILL sink below unfinished entries!
            viewModel.toggleEntryCompleted(try unwrap(entryRepo.fetchById(createdTodo.id)))
            await waitUntilAsync(timeout: 1.5) { viewModel.completedEntryCount == 1 }

            try check(viewModel.completedEntryCount == 1)
            try check(viewModel.displayedEntries.last?.id == createdTodo.id, "Completed pinned entry must sink below unfinished entries")

            viewModel.hideCompletedEntries = true
            try check(!viewModel.displayedEntries.contains(where: { $0.id == createdTodo.id }))
            viewModel.hideCompletedEntries = false
            try check(viewModel.displayedEntries.contains(where: { $0.id == createdTodo.id }))

            let clearedCount = viewModel.clearCompletedEntriesInVisibleScope()
            try check(clearedCount == 1)
            try check(try entryRepo.fetchById(createdTodo.id) == nil)
            try check(try entryRepo.fetchById(createdNote.id) != nil)
            await waitUntilAsync(timeout: 1.5) { viewModel.completedEntryCount == 0 }

            // 4. Debounced inline auto-save (900ms) + zero-data-loss flush on entry switch
            viewModel.selectedEntryId = createdNote.id
            await waitUntilAsync(timeout: 1.5) { viewModel.inlineDraftEntryId == createdNote.id }
            try check(viewModel.inlineDraftEntryId == createdNote.id)

            viewModel.inlineDraftContent = "   "
            try check(viewModel.inlineAutoSaveState == .invalid, "Blank inline content must mark auto-save state .invalid without overwriting DB")

            viewModel.inlineDraftTitle = ""
            viewModel.inlineDraftContent = "自动保存首行新标题\n已通过 900ms 防抖自动落盘"
            try check(viewModel.inlineAutoSaveState == .pending)

            await waitUntilAsync(timeout: 2.0) { viewModel.inlineAutoSaveState == .saved }
            try check(viewModel.inlineAutoSaveState == .saved)
            let autoSavedFromDB = try unwrap(entryRepo.fetchById(createdNote.id))
            try check(autoSavedFromDB.title == "自动保存首行新标题")
            try check(autoSavedFromDB.content == "自动保存首行新标题\n已通过 900ms 防抖自动落盘")

            // 4b. Mid-typing trailing spaces / tag separators must NOT be clobbered when auto-save posts .entriesDidChange
            viewModel.inlineDraftTitle = "Project "
            viewModel.inlineDraftTagsText = "alpha, "
            viewModel.inlineDraftContent = "正文同步更新以触发防抖保存"
            try check(viewModel.inlineAutoSaveState == .pending)
            await waitUntilAsync(timeout: 2.0) { viewModel.inlineAutoSaveState == .saved }
            await sleepMainActor(0.1) // allow .entriesDidChange -> refreshDisplayedEntries() to settle
            try check(viewModel.inlineDraftTitle == "Project ", "Trailing space in title must survive auto-save refresh mid-typing")
            try check(viewModel.inlineDraftTagsText == "alpha, ", "Trailing separator in tags must survive auto-save refresh mid-typing")
            let midTypingSaved = try unwrap(entryRepo.fetchById(createdNote.id))
            try check(midTypingSaved.title == "Project")
            try check(midTypingSaved.tags == ["alpha"])

            // 4c. Toolbar mutations during 900ms debounce window must flush pending inline edits first (never overwrite with stale entry)
            let staleEntrySnapshot = try unwrap(entryRepo.fetchById(createdNote.id))
            viewModel.inlineDraftTitle = "防抖期内工具栏操作标题"
            viewModel.inlineDraftContent = "防抖期内点击置顶/类型/克隆/完成都不应丢失这段新正文"
            viewModel.inlineDraftTagsText = "debounce, safe"
            try check(viewModel.inlineAutoSaveState == .pending)
            viewModel.togglePin(staleEntrySnapshot)
            let afterPin = try unwrap(entryRepo.fetchById(createdNote.id))
            try check(afterPin.isPinned)
            try check(afterPin.title == "防抖期内工具栏操作标题")
            try check(afterPin.content == "防抖期内点击置顶/类型/克隆/完成都不应丢失这段新正文")
            try check(afterPin.tags == ["debounce", "safe"])

            viewModel.inlineDraftContent = "防抖期内克隆与改类型正文"
            try check(viewModel.inlineAutoSaveState == .pending)
            let clonedDuringDebounce = try unwrap(viewModel.cloneEntry(staleEntrySnapshot, toProjectId: featureProject.id))
            try check(clonedDuringDebounce.content == "防抖期内克隆与改类型正文")

            viewModel.inlineDraftContent = "防抖期内切换类型正文"
            try check(viewModel.inlineAutoSaveState == .pending)
            viewModel.updateEntryType(staleEntrySnapshot, toType: Constants.EntryType.todo.rawValue)
            let afterTypeChange = try unwrap(entryRepo.fetchById(createdNote.id))
            try check(afterTypeChange.type == Constants.EntryType.todo.rawValue)
            try check(afterTypeChange.content == "防抖期内切换类型正文")

            // Edit again and switch selection BEFORE 900ms elapses -> must flush immediately without losing edits!
            viewModel.inlineDraftContent = "切换词条前尚未到 900ms 的修改内容"
            try check(viewModel.inlineAutoSaveState == .pending)
            viewModel.selectedEntryId = autoTitledEntry.id
            let flushedOnSwitch = try unwrap(entryRepo.fetchById(createdNote.id))
            try check(flushedOnSwitch.content == "切换词条前尚未到 900ms 的修改内容", "Switching entries must immediately flush pending inline edits")

            // 5. Context cycling (`cycleCurrentProject`), drag-and-drop move (`moveEntries`), and Tray clipboard quick-note helper
            let initialContextId = viewModel.currentProjectId
            viewModel.cycleCurrentProject(step: 1)
            try check(viewModel.currentProjectId != initialContextId)

            let movedCount = viewModel.moveEntries(withIds: [autoTitledEntry.id], toProjectId: featureProject.id)
            try check(movedCount == 1)
            try check(try entryRepo.fetchById(autoTitledEntry.id)?.projectId == featureProject.id)

            let traySaved = try unwrap(
                AppDelegate.saveQuickNoteFromClipboard(
                    clipboardText: "菜单栏一键剪贴板便签 #tray",
                    projectRepository: projectRepo,
                    entryRepository: entryRepo
                )
            )
            try check(traySaved.projectId == inboxProject.id)
            try check(traySaved.type == Constants.EntryType.note.rawValue)
            try check(traySaved.tags == ["tray"])
            try check(
                try AppDelegate.saveQuickNoteFromClipboard(
                    clipboardText: "   \n  ",
                    projectRepository: projectRepo,
                    entryRepository: entryRepo
                ) == nil
            )
        }
    }

    static func verifyPerformanceAndStabilityRegressions() throws {
        try runAsyncOnMainRunLoop {
            try await verifyPerformanceAndStabilityRegressionsAsync()
        }
    }

    static func verifyPerformanceAndStabilityRegressionsAsync() async throws {
        try await withTempDatabaseAsync { manager, dbURL in
            let projectRepo = ProjectRepository(dbQueue: manager.dbQueue)
            let entryRepo = EntryRepository(dbQueue: manager.dbQueue)
            let settingsRepo = SettingsRepository(dbQueue: manager.dbQueue)
            let logRepo = LogRepository(dbQueue: manager.dbQueue)
            let maintenance = StorageMaintenanceService(
                dbQueue: manager.dbQueue,
                logRepository: logRepo,
                databaseURL: dbURL
            )
            let defaultProject = try unwrap(projectRepo.fetchDefault())
            let inboxProject = try unwrap(projectRepo.fetchInbox())
            let projectBeta = Project(id: "proj-beta", name: "性能稳定专项", groupKind: .project)
            try projectRepo.create(projectBeta)

            let e1 = Entry(projectId: defaultProject.id, title: "条目一", content: "正文一", type: Constants.EntryType.prompt.rawValue)
            let e2 = Entry(projectId: defaultProject.id, title: "条目二", content: "正文二", type: Constants.EntryType.code.rawValue)
            let e3 = Entry(projectId: defaultProject.id, title: "条目三", content: "正文三", type: Constants.EntryType.note.rawValue)
            try entryRepo.create(e1)
            try entryRepo.create(e2)
            try entryRepo.create(e3)

            let appState = AppState()
            appState.loadPersistedState(currentProjectId: defaultProject.id, defaultProjectId: defaultProject.id)

            let spyClipboard = SpyClipboardService()
            let spyPaste = SpyPasteService()
            let stubPermission = StubPermissionService()
            let executeService = ExecuteService(
                clipboardService: spyClipboard,
                pasteService: spyPaste,
                entryRepository: entryRepo,
                logRepository: logRepo,
                permissionService: stubPermission,
                targetApplicationProvider: { nil },
                currentFrontApplicationProvider: { nil }
            )

            let panelVM = QuickPanelViewModel(
                appState: appState,
                projectRepository: projectRepo,
                entryRepository: entryRepo,
                settingsRepository: settingsRepo,
                searchService: EntrySearchService(entryRepository: entryRepo),
                executeService: executeService,
                clipboardService: spyClipboard,
                permissionService: PermissionService(),
                onClosePanel: {}
            )

            let mainVM = MainWindowViewModel(
                appState: appState,
                projectRepository: projectRepo,
                entryRepository: entryRepo,
                settingsRepository: settingsRepo,
                logRepository: logRepo,
                permissionService: PermissionService(),
                loginItemService: LoginItemService(),
                storageMaintenanceService: maintenance,
                updaterService: UpdaterService(),
                launchRecoveryReport: nil
            )
            defer { mainVM.cancelPendingBackgroundTasks() }

            mainVM.load()
            panelVM.prepareForPresentation()
            await waitUntilAsync(timeout: 1.5) {
                !panelVM.isScopeSearchInFlight && panelVM.entries.count == 3 && mainVM.entries.count == 3
            }

            // 1. QuickPanelViewModel: synchronous race-free project scope persistence on `.currentProjectDidChange`
            var persistedIdSeenDuringNotification: String?
            let projectChangeCancellable = NotificationCenter.default.publisher(for: .currentProjectDidChange)
                .sink { _ in
                    persistedIdSeenDuringNotification = try? settingsRepo.getCurrentProjectId()
                }
            defer { projectChangeCancellable.cancel() }

            panelVM.activateScope(projectBeta.id)
            try check(persistedIdSeenDuringNotification == projectBeta.id, "SQLite currentProjectId must already be updated when .currentProjectDidChange fires")
            try check(try settingsRepo.getCurrentProjectId() == projectBeta.id)
            try check(appState.currentProjectId == projectBeta.id)
            try check(mainVM.currentProjectId == projectBeta.id, "MainWindowViewModel must stay synchronized on panel scope switch")

            panelVM.activateScope(defaultProject.id)
            await waitUntilAsync(timeout: 1.5) { !panelVM.isScopeSearchInFlight && panelVM.entries.count == 3 }

            // 2. QuickPanelViewModel: `scrollSelectionRevision` increments ONLY on keyboard navigation, never on pointer selection
            let basePanelScrollRev = panelVM.scrollSelectionRevision
            panelVM.selectEntry(at: 1)
            try check(panelVM.selectedIndex == 1)
            try check(panelVM.scrollSelectionRevision == basePanelScrollRev, "Pointer selectEntry(at:) must not increment scrollSelectionRevision")
            panelVM.moveSelection(.down)
            try check(panelVM.selectedIndex == 2)
            try check(panelVM.scrollSelectionRevision == basePanelScrollRev + 1)
            panelVM.moveSelection(.up)
            try check(panelVM.selectedIndex == 1)
            try check(panelVM.scrollSelectionRevision == basePanelScrollRev + 2)

            // 3. MainWindowViewModel: clicking a row (`selectedEntryId = ...`) does NOT increment `programmaticScrollRevision`, while keyboard navigation does
            mainVM.selectedProjectId = defaultProject.id
            await waitUntilAsync(timeout: 1.5) { mainVM.displayedEntries.count == 3 }
            let firstEntry = mainVM.displayedEntries[0]
            let secondEntry = mainVM.displayedEntries[1]

            let baseLibraryScrollRev = mainVM.programmaticScrollRevision
            mainVM.selectedEntryId = firstEntry.id
            try check(mainVM.programmaticScrollRevision == baseLibraryScrollRev, "Clicking an EntryListRow must not increment programmaticScrollRevision")
            mainVM.selectedEntryId = secondEntry.id
            try check(mainVM.programmaticScrollRevision == baseLibraryScrollRev)
            try check(mainVM.moveSelection(delta: -1))
            try check(mainVM.selectedEntryId == firstEntry.id)
            try check(mainVM.programmaticScrollRevision == baseLibraryScrollRev + 1, "Keyboard arrow selection must increment programmaticScrollRevision")

            // 4. InlineEditorSession isolation: keystrokes fire ZERO `MainWindowViewModel.objectWillChange` events
            var mainVMWillChangeCount = 0
            var inlineSessionWillChangeCount = 0
            let mainVMCancellable = mainVM.objectWillChange.sink { _ in
                mainVMWillChangeCount += 1
            }
            let inlineSessionCancellable = mainVM.inlineSession.objectWillChange.sink { _ in
                inlineSessionWillChangeCount += 1
            }
            defer {
                mainVMCancellable.cancel()
                inlineSessionCancellable.cancel()
            }

            mainVM.inlineDraftTitle = "高频输入标题 A"
            mainVM.handleInlineFieldEdit()
            mainVM.inlineDraftContent = "高频输入正文第一段"
            mainVM.handleInlineFieldEdit()
            mainVM.inlineDraftContent = "高频输入正文第一段 + 第二段"
            mainVM.handleInlineFieldEdit()
            mainVM.inlineDraftTagsText = "perf, isolated"
            mainVM.handleInlineFieldEdit()

            try check(mainVMWillChangeCount == 0, "Inline keystrokes must emit 0 MainWindowViewModel.objectWillChange events")
            try check(inlineSessionWillChangeCount > 0, "InlineEditorSession must publish local draft updates to PreviewPane")
            try check(mainVM.inlineAutoSaveState == .pending)

            // 5. Consecutive inline auto-saves on the same entry coalesce `EntryVersion` snapshots (1 instead of N) & update `entries` in place
            let versionsBefore = try entryRepo.fetchVersions(forEntryId: firstEntry.id).count
            mainVM.flushPendingInlineChangesIfNeeded()
            try check(mainVM.inlineAutoSaveState == .saved)

            mainVM.inlineDraftContent = "连续第二次内联自动保存"
            mainVM.flushPendingInlineChangesIfNeeded()
            mainVM.inlineDraftContent = "连续第三次内联自动保存"
            mainVM.flushPendingInlineChangesIfNeeded()

            let versionsAfterAutoSaves = try entryRepo.fetchVersions(forEntryId: firstEntry.id)
            try check(
                versionsAfterAutoSaves.count == versionsBefore + 1,
                "Rapid consecutive inline auto-saves on the same entry must coalesce into 1 EntryVersion snapshot"
            )
            let updatedInMemory = try unwrap(mainVM.entries.first(where: { $0.id == firstEntry.id }))
            try check(updatedInMemory.title == "高频输入标题 A")
            try check(updatedInMemory.content == "连续第三次内联自动保存")
            try check(updatedInMemory.tags == ["perf", "isolated"])

            // Explicit manual save (`⌘S` / `commitInlineChanges`) still records a fresh `EntryVersion`
            mainVM.inlineDraftContent = "显式手动保存版本内容"
            let latestEntry = try unwrap(entryRepo.fetchById(firstEntry.id))
            try check(mainVM.commitInlineChanges(for: latestEntry))
            let versionsAfterExplicitSave = try entryRepo.fetchVersions(forEntryId: firstEntry.id)
            try check(versionsAfterExplicitSave.count == versionsBefore + 2, "Explicit manual save must still record a version snapshot")
            _ = inboxProject
        }
    }
}

#if canImport(XCTest)
@MainActor
final class PromptPanelTests: XCTestCase {
    func testDatabaseAndMigrations() throws {
        try CoreTestSuite.verifyDatabaseAndMigrations()
    }

    func testProjectAndEntryRepositories() throws {
        try CoreTestSuite.verifyProjectAndEntryRepositories()
    }

    func testSearchAndRanking() throws {
        try CoreTestSuite.verifySearchAndRanking()
    }

    func testSettingsAndWindowPlacement() throws {
        try CoreTestSuite.verifySettingsAndWindowPlacement()
    }

    func testExecuteAndVisibilityServices() throws {
        try CoreTestSuite.verifyExecuteAndVisibilityServices()
    }

    func testKeyCommands() throws {
        try CoreTestSuite.verifyKeyCommands()
    }

    func testQuickPanelClearsResultsWhileAsyncSearchIsPending() throws {
        try CoreTestSuite.verifyQuickPanelScopeSafetyAndCopyUsage()
    }

    func testTransferAndStorageMaintenance() throws {
        try CoreTestSuite.verifyTransferAndStorageMaintenance()
    }

    func testLibraryJSONImportRollsBackPartialWritesWhenEntryInsertFails() throws {
        try CoreTestSuite.verifyLibraryJSONImportRollback()
    }

    func testStorageMaintenanceKeepsManualBackupsBeyondAutomaticRetention() throws {
        try CoreTestSuite.verifyManualBackupRetention()
    }

    func testWorkspaceKindsArchiveVersionsAndCloning() throws {
        try CoreTestSuite.verifyWorkspaceKindsArchiveVersionsAndCloning()
    }

    func testReferenceWindowAndCloudSyncConflictPreservation() throws {
        try CoreTestSuite.verifyReferenceWindowAndCloudSyncConflictPreservation()
    }

    func testCloudSyncDataLossProtectionAndThrottledBackups() throws {
        try CoreTestSuite.verifyCloudSyncDataLossProtectionAndThrottledBackups()
    }

    func testCompletedRankingCleanupAndArchivedExclusion() throws {
        try CoreTestSuite.verifyCompletedRankingCleanupAndArchivedExclusion()
    }

    func testQuickPanelAllScopeCaptureFilterHoverAndPreview() throws {
        try CoreTestSuite.verifyQuickPanelAllScopeCaptureFilterHoverAndPreview()
    }

    func testMainWindowQuickJotAutoTitleCleanupAndDebouncedAutoSave() throws {
        try CoreTestSuite.verifyMainWindowQuickJotAutoTitleCleanupAndDebouncedAutoSave()
    }

    func testPerformanceAndStabilityRegressions() throws {
        try CoreTestSuite.verifyPerformanceAndStabilityRegressions()
    }
}
#else
@MainActor
enum PromptPanelTests {
    static func runAll() throws {
        try CoreTestSuite.runAll()
    }
}
#endif

#if canImport(Testing) && PROMPTPANEL_SWIFT_TESTING
@Suite(.serialized)
@MainActor
struct PromptPanelSwiftTestingSuite {
    @Test func databaseAndMigrations() throws {
        try CoreTestSuite.verifyDatabaseAndMigrations()
    }

    @Test func projectAndEntryRepositories() throws {
        try CoreTestSuite.verifyProjectAndEntryRepositories()
    }

    @Test func searchAndRanking() throws {
        try CoreTestSuite.verifySearchAndRanking()
    }

    @Test func settingsAndWindowPlacement() throws {
        try CoreTestSuite.verifySettingsAndWindowPlacement()
    }

    @Test func executeAndVisibilityServices() throws {
        try CoreTestSuite.verifyExecuteAndVisibilityServices()
    }

    @Test func keyCommands() throws {
        try CoreTestSuite.verifyKeyCommands()
    }

    @Test func quickPanelScopeSafetyAndCopyUsage() async throws {
        try await CoreTestSuite.verifyQuickPanelScopeSafetyAndCopyUsageAsync()
    }

    @Test func transferAndStorageMaintenance() throws {
        try CoreTestSuite.verifyTransferAndStorageMaintenance()
    }

    @Test func libraryJSONImportRollback() throws {
        try CoreTestSuite.verifyLibraryJSONImportRollback()
    }

    @Test func manualBackupRetention() throws {
        try CoreTestSuite.verifyManualBackupRetention()
    }

    @Test func workspaceKindsArchiveVersionsAndCloning() throws {
        try CoreTestSuite.verifyWorkspaceKindsArchiveVersionsAndCloning()
    }

    @Test func referenceWindowAndCloudSyncConflictPreservation() throws {
        try CoreTestSuite.verifyReferenceWindowAndCloudSyncConflictPreservation()
    }

    @Test func cloudSyncDataLossProtectionAndThrottledBackups() throws {
        try CoreTestSuite.verifyCloudSyncDataLossProtectionAndThrottledBackups()
    }

    @Test func completedRankingCleanupAndArchivedExclusion() throws {
        try CoreTestSuite.verifyCompletedRankingCleanupAndArchivedExclusion()
    }

    @Test func quickPanelAllScopeCaptureFilterHoverAndPreview() async throws {
        try await CoreTestSuite.verifyQuickPanelAllScopeCaptureFilterHoverAndPreviewAsync()
    }

    @Test func mainWindowQuickJotAutoTitleCleanupAndDebouncedAutoSave() async throws {
        try await CoreTestSuite.verifyMainWindowQuickJotAutoTitleCleanupAndDebouncedAutoSaveAsync()
    }

    @Test func performanceAndStabilityRegressions() async throws {
        try await CoreTestSuite.verifyPerformanceAndStabilityRegressionsAsync()
    }
}
#endif
