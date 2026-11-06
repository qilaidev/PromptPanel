import Foundation
import OSLog

/// Reads from the unified-logging store so test code can swap in a fake source. Production
/// uses `OSLogStoreReader`; tests use a fixture that returns a fixed transcript.
protocol UnifiedLogReading {
    func readEntries(subsystem: String, since: Date) throws -> [String]
}

/// Builds a single zip file with everything a maintainer needs to investigate a paste failure
/// or storage anomaly. Privacy: never includes entry titles or bodies — only metadata,
/// permission state, and the unified-log transcript that the user can review before sending.
///
/// Threading: the permission service is main-isolated, so the *init* is main-isolated and
/// snapshots the grant state there. `exportBundle(to:)` itself is not — it reads the unified
/// log store, serializes JSON and shells out to `ditto`, which together take long enough to
/// freeze the window when run inline. The caller runs it off the main thread.
final class DiagnosticsExportService: @unchecked Sendable {
    struct AppInfoProvider {
        let bundleIdentifier: String
        let shortVersion: String
        let buildVersion: String
        let minimumSystemVersion: String

        static var fromMainBundle: AppInfoProvider {
            let info = Bundle.main.infoDictionary ?? [:]
            return AppInfoProvider(
                bundleIdentifier: (info["CFBundleIdentifier"] as? String) ?? Constants.bundleIdentifier,
                shortVersion: (info["CFBundleShortVersionString"] as? String) ?? "unknown",
                buildVersion: (info["CFBundleVersion"] as? String) ?? "unknown",
                minimumSystemVersion: (info["LSMinimumSystemVersion"] as? String) ?? "unknown"
            )
        }
    }

    enum ExportError: LocalizedError {
        case zipFailed(exitCode: Int32, message: String)
        case destinationUnreachable(URL)

        var errorDescription: String? {
            switch self {
            case .zipFailed(let exitCode, let message):
                return "诊断包压缩失败（exit=\(exitCode)）：\(message)"
            case .destinationUnreachable(let url):
                return "无法写入诊断包到 \(url.path)"
            }
        }
    }

    private let logRepository: LogRepository
    private let storageMaintenanceService: StorageMaintenanceService
    /// Snapshotted at init on the main actor; the export itself runs off-main and
    /// must not touch the main-isolated permission service.
    private let isAccessibilityGranted: Bool
    private let appInfo: AppInfoProvider
    private let unifiedLogReader: UnifiedLogReading
    private let fileManager: FileManager
    private let clock: @Sendable () -> Date

    @MainActor
    init(
        logRepository: LogRepository,
        storageMaintenanceService: StorageMaintenanceService,
        permissionService: AccessibilityPermissionProviding,
        appInfo: AppInfoProvider = .fromMainBundle,
        unifiedLogReader: UnifiedLogReading = OSLogStoreReader(),
        fileManager: FileManager = .default,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.logRepository = logRepository
        self.storageMaintenanceService = storageMaintenanceService
        permissionService.refresh()
        self.isAccessibilityGranted = permissionService.isAccessibilityGranted
        self.appInfo = appInfo
        self.unifiedLogReader = unifiedLogReader
        self.fileManager = fileManager
        self.clock = clock
    }

    /// Build the bundle and zip it to `destinationZipURL`. Returns the same URL on success
    /// so the caller can show it to the user.
    @discardableResult
    func exportBundle(to destinationZipURL: URL) throws -> URL {
        let now = clock()
        let timestamp = ISO8601DateFormatter.diagnosticsTimestamp.string(from: now)
        let bundleDirectoryName = "PromptPanel-Diagnostics-\(timestamp)"

        let stagingRoot = fileManager.temporaryDirectory
            .appendingPathComponent("PromptPanel-DiagnosticsExport-\(UUID().uuidString)", isDirectory: true)
        let bundleDirectoryURL = stagingRoot.appendingPathComponent(bundleDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: bundleDirectoryURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingRoot) }

        try writeReadme(into: bundleDirectoryURL, timestamp: timestamp)
        try writeAppInfo(into: bundleDirectoryURL)
        try writeHealthSnapshot(into: bundleDirectoryURL)
        try writePermissions(into: bundleDirectoryURL)
        try writeExecutionLogs(into: bundleDirectoryURL)
        try writeUnifiedLogs(into: bundleDirectoryURL, since: now.addingTimeInterval(-24 * 60 * 60))

        let destinationDirectory = destinationZipURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destinationDirectory.path) {
            try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: destinationZipURL.path) {
            try fileManager.removeItem(at: destinationZipURL)
        }
        try zip(directory: bundleDirectoryURL, into: destinationZipURL)

        guard fileManager.fileExists(atPath: destinationZipURL.path) else {
            throw ExportError.destinationUnreachable(destinationZipURL)
        }
        return destinationZipURL
    }

    private func writeReadme(into directory: URL, timestamp: String) throws {
        let body = """
        PromptPanel diagnostics bundle
        ===============================

        Generated at: \(timestamp)
        App version : \(appInfo.shortVersion)+\(appInfo.buildVersion)
        Bundle id   : \(appInfo.bundleIdentifier)
        Min macOS   : \(appInfo.minimumSystemVersion)

        Contents:
        - app-info.json        Build metadata.
        - permissions.json     Accessibility permission state when the bundle was created.
        - health-snapshot.json Storage health snapshot (database/backup/recovery paths and sizes).
        - execution-logs.json  Up to 200 most recent execution records. NO entry titles or bodies.
        - unified-logs.ndjson  Unified-logging transcript for the PromptPanel subsystem (best-effort, last 24h or session length).

        Review every file before sharing. Nothing here contains the contents of any prompt entry,
        but you may want to confirm that bundle identifiers of frontmost apps are appropriate to share.
        """
        try body.write(to: directory.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    }

    private func writeAppInfo(into directory: URL) throws {
        let payload: [String: String] = [
            "bundle_identifier": appInfo.bundleIdentifier,
            "short_version": appInfo.shortVersion,
            "build_version": appInfo.buildVersion,
            "minimum_system_version": appInfo.minimumSystemVersion
        ]
        try writeJSON(payload, to: directory.appendingPathComponent("app-info.json"))
    }

    private func writeHealthSnapshot(into directory: URL) throws {
        let snapshot = try storageMaintenanceService.healthSnapshot()
        let payload: [String: Any?] = [
            "database_path": snapshot.databaseURL.path,
            "database_size_bytes": snapshot.databaseSizeBytes,
            "backup_directory": snapshot.backupDirectoryURL.path,
            "backup_count": snapshot.backupCount,
            "latest_backup": snapshot.latestBackupURL?.lastPathComponent as Any?,
            "recovery_directory": snapshot.recoveryDirectoryURL.path,
            "logs_directory": snapshot.logsDirectoryURL.path
        ]
        try writeJSON(payload.compactMapValues { $0 }, to: directory.appendingPathComponent("health-snapshot.json"))
    }

    private func writePermissions(into directory: URL) throws {
        let payload: [String: Any] = [
            "accessibility_granted": isAccessibilityGranted,
            "recorded_at": ISO8601DateFormatter().string(from: clock())
        ]
        try writeJSON(payload, to: directory.appendingPathComponent("permissions.json"))
    }

    private func writeExecutionLogs(into directory: URL) throws {
        let logs = try logRepository.fetchRecent(limit: 200)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(logs)
        try data.write(to: directory.appendingPathComponent("execution-logs.json"))
    }

    private func writeUnifiedLogs(into directory: URL, since: Date) throws {
        let entries = (try? unifiedLogReader.readEntries(subsystem: appInfo.bundleIdentifier, since: since)) ?? []
        let body = entries.joined(separator: "\n")
        try body.write(to: directory.appendingPathComponent("unified-logs.ndjson"), atomically: true, encoding: .utf8)
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    private func zip(directory: URL, into destinationZipURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", directory.path, destinationZipURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        // Drain stderr before waiting: if ditto writes more than the pipe buffer
        // (~64KB) it blocks on write, and waitUntilExit() would deadlock forever.
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? ""
            throw ExportError.zipFailed(exitCode: process.terminationStatus, message: message)
        }
    }
}

/// Production reader: pulls log entries for `subsystem` from `OSLogStore`. macOS 12+ ships
/// the API; on non-sandboxed apps `.currentProcessIdentifier` works without entitlements
/// and gives this process's logs since launch. That's usually enough — PromptPanel is a
/// resident menu-bar app, so a 24h window is realistic during a typical session.
struct OSLogStoreReader: UnifiedLogReading {
    func readEntries(subsystem: String, since: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: since)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        let entries = try store.getEntries(at: position, matching: predicate)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var lines: [String] = []
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }
            let payload: [String: Any] = [
                "ts": formatter.string(from: logEntry.date),
                "level": String(describing: logEntry.level),
                "subsystem": logEntry.subsystem,
                "category": logEntry.category,
                "message": logEntry.composedMessage
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
               let line = String(data: data, encoding: .utf8) {
                lines.append(line)
            }
        }
        return lines
    }
}

private extension ISO8601DateFormatter {
    static let diagnosticsTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
