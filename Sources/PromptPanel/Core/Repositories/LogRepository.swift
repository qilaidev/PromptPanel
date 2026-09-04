import Foundation
import GRDB

/// Data access layer for execution logs.
final class LogRepository: @unchecked Sendable {
    struct HealthSummary {
        let totalCount: Int
        let successCount: Int
        let clipboardOnlyCount: Int
        let failedCount: Int
        let latestExecutionAt: Date?
        let latestFailureAt: Date?
    }

    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Record an execution log entry.
    func record(_ log: ExecutionLog) throws {
        try dbQueue.write { db in
            try log.insert(db)
        }
        PPLogger.execute.debug("Execution logged: entry=\(log.entryId), result=\(log.result)")
    }

    /// Fetch recent execution logs (for debugging).
    func fetchRecent(limit: Int = 100) throws -> [ExecutionLog] {
        try dbQueue.read { db in
            try ExecutionLog
                .order(ExecutionLog.Columns.createdAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Clean up old logs (keep only last N days).
    func cleanup(olderThanDays days: Int = 30) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
            ?? Date().addingTimeInterval(-Double(days) * 86_400)
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM execution_logs WHERE created_at < ?",
                arguments: [cutoff]
            )
        }
        PPLogger.execute.info("Cleaned up logs older than \(days) days")
    }

    func fetchHealthSummary(since cutoff: Date) throws -> HealthSummary {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT
                        COUNT(*) AS total_count,
                        SUM(CASE WHEN result = ? THEN 1 ELSE 0 END) AS success_count,
                        SUM(CASE WHEN result = ? THEN 1 ELSE 0 END) AS clipboard_only_count,
                        SUM(CASE WHEN result = ? THEN 1 ELSE 0 END) AS failed_count,
                        MAX(created_at) AS latest_execution_at,
                        MAX(CASE WHEN result != ? THEN created_at END) AS latest_failure_at
                    FROM execution_logs
                    WHERE created_at >= ?
                    """,
                arguments: [
                    Constants.ExecutionResult.success.rawValue,
                    Constants.ExecutionResult.clipboardOnly.rawValue,
                    Constants.ExecutionResult.failed.rawValue,
                    Constants.ExecutionResult.success.rawValue,
                    cutoff
                ]
            ) ?? Row()

            return HealthSummary(
                totalCount: row["total_count"] ?? 0,
                successCount: row["success_count"] ?? 0,
                clipboardOnlyCount: row["clipboard_only_count"] ?? 0,
                failedCount: row["failed_count"] ?? 0,
                latestExecutionAt: row["latest_execution_at"],
                latestFailureAt: row["latest_failure_at"]
            )
        }
    }
}
