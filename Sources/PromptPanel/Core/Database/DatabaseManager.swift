import Foundation
import GRDB

/// Manages the SQLite database lifecycle: creation, migration, and access.
final class DatabaseManager {
    enum InitializationError: LocalizedError {
        case storeBusyPreservingStore(underlying: Error, databaseURL: URL)
        case migrationFailedPreservingStore(underlying: Error, databaseURL: URL)

        var errorDescription: String? {
            switch self {
            case .storeBusyPreservingStore(let underlying, let databaseURL):
                return """
                本地数据库当前被占用，已保留原始数据文件，未执行自动恢复。
                数据库位置：\(databaseURL.path)
                请先关闭其他 PromptPanel 实例或等待当前操作结束后重试。
                具体错误：\(underlying.localizedDescription)
                """
            case .migrationFailedPreservingStore(let underlying, let databaseURL):
                return """
                本地数据库升级失败，已保留原始数据文件，未执行自动重建。
                数据库位置：\(databaseURL.path)
                具体错误：\(underlying.localizedDescription)
                """
            }
        }
    }

    /// The shared database queue for all read/write operations.
    let dbQueue: DatabaseQueue
    let databaseURL: URL
    private(set) var launchRecoveryReport: LaunchRecoveryReport?
    private static let openRetryMaxAttempts = 4
    private static let openRetryDelayMs = 120

    /// Initialize with a database at the specified URL.
    /// - Parameter url: Path to the SQLite database file. If nil, uses the default path.
    init(url: URL? = nil) throws {
        let databaseURL = url ?? Constants.databaseURL
        self.databaseURL = databaseURL
        PPLogger.database.info("Opening database at \(databaseURL.path)")

        do {
            dbQueue = try Self.openDatabase(at: databaseURL)
        } catch {
            PPLogger.database.error("Database open failed: \(error.localizedDescription)")
            if let initializationError = Self.initializationErrorPreservingStore(for: error, databaseURL: databaseURL) {
                throw initializationError
            }
            if Self.storeExists(at: databaseURL) {
                let report = try Self.quarantineBrokenStore(at: databaseURL, failureDescription: error.localizedDescription)
                launchRecoveryReport = report
                dbQueue = try Self.openDatabase(at: databaseURL)
                PPLogger.database.warning("Recovered by recreating the database after quarantining the broken store at \(report.quarantinedFilesDirectoryURL.path)")
            } else {
                throw error
            }
        }

        do {
            try Self.prepareDatabase(dbQueue, at: databaseURL)
        } catch {
            PPLogger.database.error("Database preparation failed without automatic recovery: \(error.localizedDescription)")
            if let initializationError = Self.initializationErrorPreservingStore(for: error, databaseURL: databaseURL) {
                throw initializationError
            }
            throw InitializationError.migrationFailedPreservingStore(
                underlying: error,
                databaseURL: databaseURL
            )
        }

        PPLogger.database.info("Database initialized successfully")
    }

    /// Run all database migrations in order.
    private static func runMigrations(on dbQueue: DatabaseQueue) throws {
        var migrator = DatabaseMigrator()

        // Schema drift in a local data app must be an explicit destructive choice, not the DEBUG default.
        if ProcessInfo.processInfo.environment["PROMPTPANEL_ERASE_ON_SCHEMA_CHANGE"] == "1" {
            migrator.eraseDatabaseOnSchemaChange = true
            PPLogger.database.warning("Schema-change erase mode enabled via PROMPTPANEL_ERASE_ON_SCHEMA_CHANGE")
        }

        // Register all migrations
        Migrations.registerAll(&migrator)

        // Apply pending migrations
        try migrator.migrate(dbQueue)

        PPLogger.database.info("Migrations completed")
    }

    private static func openDatabase(at databaseURL: URL) throws -> DatabaseQueue {
        let fileManager = FileManager.default
        let directory = databaseURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Constants.secureDirectoryPermissions]
        )
        try fileManager.setAttributes([.posixPermissions: Constants.secureDirectoryPermissions], ofItemAtPath: directory.path)

        var config = Configuration()
        config.prepareDatabase { db in
            // Ranking runs through a Swift function rather than a SQL expression so the
            // repository's ORDER BY and the panel's in-memory sort cannot drift apart.
            // It has to be registered on every connection, not just the first.
            db.add(function: EntryRanking.databaseFunction)
            // Opt-in rather than on for every debug build: tracing emits a log line
            // per statement, which on a library load is one line per row fetched.
            if ProcessInfo.processInfo.environment["PROMPTPANEL_TRACE_SQL"] == "1" {
                db.trace { PPLogger.database.debug("\($0)") }
            }
        }

        var lastError: Error?
        for attempt in 0...openRetryMaxAttempts {
            do {
                return try DatabaseQueue(path: databaseURL.path, configuration: config)
            } catch {
                lastError = error
                guard shouldRetryOpen(after: error), attempt < openRetryMaxAttempts else {
                    throw error
                }

                let retryAttempt = attempt + 1
                PPLogger.database.warning(
                    "Database open hit a transient busy/locked state; retrying attempt \(retryAttempt) of \(openRetryMaxAttempts)"
                )
                usleep(useconds_t(openRetryDelayMs * 1_000))
            }
        }

        throw lastError ?? DatabaseError(resultCode: .SQLITE_CANTOPEN, message: "Database open failed after retries")
    }

    private static func prepareDatabase(_ dbQueue: DatabaseQueue, at databaseURL: URL) throws {
        let fileManager = FileManager.default
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
        }
        try runMigrations(on: dbQueue)

        if fileManager.fileExists(atPath: databaseURL.path) {
            try fileManager.setAttributes([.posixPermissions: Constants.secureFilePermissions], ofItemAtPath: databaseURL.path)
        }
    }

    private static func storeExists(at databaseURL: URL) -> Bool {
        let fileManager = FileManager.default
        let candidateURLs = storeFileURLs(for: databaseURL)
        return candidateURLs.contains { fileManager.fileExists(atPath: $0.path) }
    }

    private static func shouldRetryOpen(after error: Error) -> Bool {
        isDatabaseBusyOrLocked(error)
    }

    private static func initializationErrorPreservingStore(for error: Error, databaseURL: URL) -> InitializationError? {
        guard isDatabaseBusyOrLocked(error) else {
            return nil
        }
        return .storeBusyPreservingStore(underlying: error, databaseURL: databaseURL)
    }

    private static func isDatabaseBusyOrLocked(_ error: Error) -> Bool {
        guard let databaseError = error as? DatabaseError else {
            return false
        }

        let busyOrLockedCodes: Set<Int32> = [
            ResultCode.SQLITE_BUSY.rawValue,
            ResultCode.SQLITE_LOCKED.rawValue
        ]
        return busyOrLockedCodes.contains(databaseError.resultCode.rawValue)
            || busyOrLockedCodes.contains(databaseError.extendedResultCode.rawValue)
    }

    private static func quarantineBrokenStore(at databaseURL: URL, failureDescription: String) throws -> LaunchRecoveryReport {
        let fileManager = FileManager.default
        let recoveryRootURL = Constants.recoveryDirectory(for: databaseURL)
        try fileManager.createDirectory(
            at: recoveryRootURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Constants.secureDirectoryPermissions]
        )
        try fileManager.setAttributes([.posixPermissions: Constants.secureDirectoryPermissions], ofItemAtPath: recoveryRootURL.path)

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let quarantineDirectoryURL = recoveryRootURL.appendingPathComponent("recovered-\(timestamp)", isDirectory: true)
        try fileManager.createDirectory(
            at: quarantineDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: Constants.secureDirectoryPermissions]
        )
        try fileManager.setAttributes([.posixPermissions: Constants.secureDirectoryPermissions], ofItemAtPath: quarantineDirectoryURL.path)

        for sourceURL in storeFileURLs(for: databaseURL) where fileManager.fileExists(atPath: sourceURL.path) {
            let destinationURL = quarantineDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
            try? fileManager.removeItem(at: destinationURL)
            try fileManager.moveItem(at: sourceURL, to: destinationURL)
            try fileManager.setAttributes([.posixPermissions: Constants.secureFilePermissions], ofItemAtPath: destinationURL.path)
        }

        return LaunchRecoveryReport(
            quarantinedFilesDirectoryURL: quarantineDirectoryURL,
            recoveredAt: Date(),
            failureDescription: failureDescription
        )
    }

    private static func storeFileURLs(for databaseURL: URL) -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
    }
}
