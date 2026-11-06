import AppKit
import Foundation
import GRDB
@testable import PromptPanel

#if canImport(XCTest)
import XCTest
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

@MainActor
private enum CoreTestSuite {
    static func runAll() throws {
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
                tags: ["review", "并发", "review"]
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
    }

    static func verifyQuickPanelScopeSafetyAndCopyUsage() throws {
        try withTempDatabase { manager, _ in
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
            let loadDeadline = Date().addingTimeInterval(1)
            while (viewModel.isScopeSearchInFlight || viewModel.entries.count != 2) && Date() < loadDeadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
            }
            try check(viewModel.entries.count == 2)

            // Trigger a scope change and verify in-flight guard blocks stale pointer clicks
            // while deferring keyboard shortcut ⌘1 to the new search results.
            viewModel.query = "Beta"
            try check(viewModel.isScopeSearchInFlight)
            viewModel.executeEntry(at: 0, triggerSource: .pointerClick)
            try check(spyClipboard.writtenTexts.isEmpty)

            _ = viewModel.handlePanelKeyCommand(.executeEntry(number: 1))
            let searchDeadline = Date().addingTimeInterval(1)
            while viewModel.isScopeSearchInFlight && Date() < searchDeadline {
                RunLoop.main.run(until: Date().addingTimeInterval(0.005))
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
                    content: "  Indented First Line\nSecond Line",
                    tags: ["export", "code review"]
                )
            )

            let exportURL = dbURL.deletingLastPathComponent().appendingPathComponent("export.json")
            _ = try transfer.exportJSON(to: exportURL)
            try check(FileManager.default.fileExists(atPath: exportURL.path))

            let mdURL = dbURL.deletingLastPathComponent().appendingPathComponent("export.md")
            _ = try transfer.exportMarkdown(to: mdURL)
            try check(FileManager.default.fileExists(atPath: mdURL.path))

            // Verify Markdown round-trip preserves leading indentation and multi-word tags
            try entryRepo.delete(id: "md-entry-1")
            _ = try transfer.importMarkdown(from: mdURL)
            let roundTripped = try unwrap(entryRepo.fetchById("md-entry-1"))
            try check(roundTripped.content == "  Indented First Line\nSecond Line")
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
}
#else
@MainActor
enum PromptPanelTests {
    static func runAll() throws {
        try CoreTestSuite.runAll()
    }
}
#endif
