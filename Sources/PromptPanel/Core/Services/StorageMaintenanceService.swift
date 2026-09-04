import AppKit
import Foundation
import GRDB

struct LaunchRecoveryReport {
    let quarantinedFilesDirectoryURL: URL
    let recoveredAt: Date
    let failureDescription: String

    var userFacingMessage: String {
        "检测到本地数据库异常，旧数据已隔离到 \(quarantinedFilesDirectoryURL.lastPathComponent)，应用已重建可用数据库。请优先检查最近备份。"
    }
}

struct StorageHealthSnapshot {
    let databaseURL: URL
    let backupDirectoryURL: URL
    let recoveryDirectoryURL: URL
    let logsDirectoryURL: URL
    let databaseSizeBytes: Int64
    let backupCount: Int
    let latestBackupURL: URL?
    /// Captured here rather than stat-ed by the settings view. The overview card
    /// reads it from `body`, which runs on every state change — a filesystem
    /// round-trip per repaint is exactly the kind of main-thread work that made
    /// the settings tab feel sticky.
    let latestBackupModifiedAt: Date?
}

final class StorageMaintenanceService: @unchecked Sendable {
    private let dbQueue: DatabaseQueue
    private let logRepository: LogRepository
    private let databaseURL: URL
    private let fileManager: FileManager

    init(
        dbQueue: DatabaseQueue,
        logRepository: LogRepository,
        databaseURL: URL,
        fileManager: FileManager = .default
    ) {
        self.dbQueue = dbQueue
        self.logRepository = logRepository
        self.databaseURL = databaseURL
        self.fileManager = fileManager
    }

    @discardableResult
    func performLaunchMaintenance() throws -> StorageHealthSnapshot {
        try ensureStorageDirectories()
        try checkpointWal()
        try logRepository.cleanup(olderThanDays: Constants.executionLogRetentionDays)
        if try shouldCreateAutomaticBackup() {
            _ = try createBackup(reason: "launch")
        }
        try pruneCollectableBackups()
        pruneRecoveryDirectories(keeping: Constants.recoveryDirectoryRetentionCount)
        return try healthSnapshot()
    }

    func prepareForTermination() {
        do {
            try checkpointWal()
        } catch {
            PPLogger.database.error("Failed to checkpoint database during termination: \(error.localizedDescription)")
        }
    }

    /// A backup the user explicitly asked for (立即备份).
    ///
    /// Deliberately **never** pruned: it is the user's own archive, and silently
    /// deleting the copy someone made right before doing something risky is the
    /// worst possible failure mode for a backup feature. Only the two machine-made
    /// classes below are collectable.
    func createManualBackup() throws -> URL {
        try ensureStorageDirectories()
        try checkpointWal()
        let backupURL = try createBackup(reason: "manual")
        try pruneCollectableBackups()
        return backupURL
    }

    /// The safety snapshot taken automatically before a library import.
    ///
    /// This used to go through `createManualBackup()`, so it inherited the
    /// never-prune policy above and every import left another full database copy
    /// behind, forever. Nobody asked for these individually, so they are bounded.
    func createImportSafetyBackup() throws -> URL {
        try ensureStorageDirectories()
        try checkpointWal()
        let backupURL = try createBackup(reason: "import")
        try pruneCollectableBackups()
        return backupURL
    }

    /// Prune only the backup classes the app creates on its own initiative.
    /// `-manual-` is absent on purpose — see `createManualBackup()`.
    private func pruneCollectableBackups() throws {
        try pruneBackups(reason: "launch", keeping: Constants.automaticBackupRetentionCount)
        try pruneBackups(reason: "import", keeping: Constants.importBackupRetentionCount)
    }

    /// Read-only: it reports what is on disk and must not create or chmod
    /// anything. The settings tab refreshes this on load, after every
    /// maintenance action, and on every execution-log change; making it
    /// idempotently re-secure four directories each time was pure main-thread
    /// syscall churn. `performLaunchMaintenance()` and the backup paths still
    /// call `ensureStorageDirectories()` explicitly.
    func healthSnapshot() throws -> StorageHealthSnapshot {
        let backups = try backupFiles()
        let databaseSizeBytes = (try fileSize(at: databaseURL)) ?? 0
        let latestBackupURL = backups.first

        return StorageHealthSnapshot(
            databaseURL: databaseURL,
            backupDirectoryURL: Constants.backupDirectory(for: databaseURL),
            recoveryDirectoryURL: Constants.recoveryDirectory(for: databaseURL),
            logsDirectoryURL: Constants.logsDirectory,
            databaseSizeBytes: databaseSizeBytes,
            backupCount: backups.count,
            latestBackupURL: latestBackupURL,
            latestBackupModifiedAt: latestBackupURL.flatMap {
                try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }
        )
    }

    func openDatabaseDirectory() {
        fileManager.ensureDirectoryExists(
            at: databaseURL.deletingLastPathComponent(),
            permissions: Constants.secureDirectoryPermissions
        )
        NSWorkspace.shared.activateFileViewerSelecting([databaseURL])
    }

    func openBackupDirectory() {
        let backupDirectoryURL = Constants.backupDirectory(for: databaseURL)
        fileManager.ensureDirectoryExists(at: backupDirectoryURL, permissions: Constants.secureDirectoryPermissions)
        NSWorkspace.shared.open(backupDirectoryURL)
    }

    private func shouldCreateAutomaticBackup() throws -> Bool {
        guard let latestBackupURL = try backupFiles().first else {
            return true
        }
        guard let modificationDate = try latestBackupURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return true
        }
        return Date().timeIntervalSince(modificationDate) >= Constants.automaticBackupMinimumInterval
    }

    private func createBackup(reason: String) throws -> URL {
        let backupDirectoryURL = Constants.backupDirectory(for: databaseURL)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let filename = "promptpanel-\(timestamp)-\(reason)-\(UUID().uuidString.prefix(8)).sqlite"
        let destinationURL = backupDirectoryURL.appendingPathComponent(filename)

        try? fileManager.removeItem(at: destinationURL)
        do {
            let destinationQueue = try DatabaseQueue(path: destinationURL.path)
            try dbQueue.backup(to: destinationQueue)
            try secureItem(at: destinationURL, isDirectory: false)
            PPLogger.database.info("Database backup created at \(destinationURL.lastPathComponent)")
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            PPLogger.database.error("Failed to create database backup: \(error.localizedDescription)")
            throw error
        }
    }

    /// Keep only the most recent `count` recovery snapshots so that a machine that quarantines
    /// stores repeatedly does not accumulate unbounded files. Failures here are non-fatal —
    /// recovery directories are diagnostic, not load-bearing.
    func pruneRecoveryDirectories(keeping count: Int) {
        guard count >= 0 else { return }
        let recoveryRoot = Constants.recoveryDirectory(for: databaseURL)
        guard fileManager.fileExists(atPath: recoveryRoot.path) else { return }

        let candidates: [URL]
        do {
            candidates = try fileManager.contentsOfDirectory(
                at: recoveryRoot,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            PPLogger.database.error("Failed to enumerate recovery directory: \(error.localizedDescription)")
            return
        }

        let directories = candidates.compactMap { url -> URL? in
            let prefix = url.lastPathComponent
            guard prefix.hasPrefix("recovered-") || prefix.hasPrefix("manual-restore-") else {
                return nil
            }
            // Skip in-flight staging copies; restore-backup.sh removes them via trap on exit, but
            // we should never delete one mid-operation even if the trap was skipped.
            if prefix.hasPrefix("manual-restore-staging-") {
                return nil
            }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return isDirectory ? url : nil
        }

        let sorted = directories.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }

        guard sorted.count > count else { return }
        for directory in sorted.dropFirst(count) {
            do {
                try fileManager.removeItem(at: directory)
                PPLogger.database.info("Pruned recovery directory \(directory.lastPathComponent)")
            } catch {
                PPLogger.database.warning("Failed to prune recovery directory \(directory.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func pruneBackups(reason: String? = nil, keeping count: Int) throws {
        let backups = try backupFiles(reason: reason)
        guard backups.count > count else {
            return
        }

        for backupURL in backups.dropFirst(count) {
            try? fileManager.removeItem(at: backupURL)
        }
    }

    private func backupFiles(reason: String? = nil) throws -> [URL] {
        let directoryURL = Constants.backupDirectory(for: databaseURL)
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let urls = enumerator.compactMap { $0 as? URL }.filter { url in
            guard url.pathExtension == "sqlite" else {
                return false
            }
            guard let reason else {
                return true
            }
            return url.lastPathComponent.contains("-\(reason)-")
        }
        return try urls.sorted { lhs, rhs in
            let lhsDate = try lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            let rhsDate = try rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    private func checkpointWal() throws {
        try dbQueue.writeWithoutTransaction { db in
            _ = try db.checkpoint(.truncate)
        }
    }

    private func ensureStorageDirectories() throws {
        try secureItem(at: databaseURL.deletingLastPathComponent(), isDirectory: true)
        try secureItem(at: Constants.backupDirectory(for: databaseURL), isDirectory: true)
        try secureItem(at: Constants.recoveryDirectory(for: databaseURL), isDirectory: true)
        try secureItem(at: Constants.logsDirectory, isDirectory: true)
    }

    private func fileSize(at url: URL) throws -> Int64? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value
    }

    private func secureItem(at url: URL, isDirectory: Bool) throws {
        let permissions = isDirectory ? Constants.secureDirectoryPermissions : Constants.secureFilePermissions
        if isDirectory {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: permissions]
            )
        }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: url.path)
        }
    }
}

private extension FileManager {
    func ensureDirectoryExists(at url: URL, permissions: Int) {
        try? createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: permissions]
        )
    }
}
