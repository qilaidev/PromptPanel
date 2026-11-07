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
            }
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
}
#else
@MainActor
enum PromptPanelTests {
    static func runAll() throws {
        try CoreTestSuite.runAll()
    }
}
#endif
