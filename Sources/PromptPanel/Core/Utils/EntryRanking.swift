import Foundation

/// How entries are ranked in the quick panel and the library.
///
/// The original PRD order was `是否置顶 → 手动排序值 → 最近使用时间 → 使用次数`, and it had
/// two problems that only showed up against a real library:
///
/// 1. `use_count` could never fire. It sat behind `last_used_at`, which is a
///    second-precision timestamp — two entries practically never share one, so the
///    tiebreaker below it was unreachable. Usage frequency had *no* effect on the order.
/// 2. `sort_order` outranked everything but pinning, and nothing in the UI ever wrote it
///    (`updateSortOrder` was only ever called from tests). Entries that picked up a value
///    from an import were nailed above the list forever, no matter how little they were
///    used, with no way to clear them.
///
/// The order is now `是否置顶 → frecency → 最近使用时间 → 使用次数 → …`. Frecency multiplies
/// how often an entry is used by how recently it was used, so a prompt used 600 times this
/// week outranks one used 3 times in July, while a once-hot prompt that has not been touched
/// in half a year sinks on its own instead of holding the top slot forever.
///
/// The weights are deliberately coarse integer buckets rather than a continuous decay
/// curve: the same table generates both the SQL used for `ORDER BY` and the Swift
/// comparator used by the panel, so the two orderings cannot drift, and neither depends on
/// SQLite being built with the optional math extension (`pow`/`exp` are not guaranteed).
enum EntryRanking {
    /// Recency multipliers, ordered by ascending age. The first bucket whose `maxAgeDays`
    /// exceeds the entry's age wins; anything older falls through to `staleWeight`.
    ///
    /// The 100 → 1 spread means recency dominates within a season and frequency decides
    /// inside a bucket: 4 days is "this week", 31 is "this month", 180 is "still remembered".
    static let recencyBuckets: [(maxAgeDays: Int, weight: Int)] = [
        (maxAgeDays: 4, weight: 100),
        (maxAgeDays: 14, weight: 70),
        (maxAgeDays: 31, weight: 50),
        (maxAgeDays: 90, weight: 30),
        (maxAgeDays: 180, weight: 10),
    ]

    /// Weight for an entry older than every bucket. Not zero: a rarely-touched entry should
    /// still outrank one that has never been used at all.
    static let staleWeight = 1

    /// Weight for an entry that has never been used. Zero, so it sorts below everything
    /// with any history and falls through to the `updated_at` tiebreaker.
    static let neverUsedScore = 0

    static func recencyWeight(ageDays: Int) -> Int {
        for bucket in recencyBuckets where ageDays < bucket.maxAgeDays {
            return bucket.weight
        }
        return staleWeight
    }

    /// Age in whole days, truncated toward zero to match SQLite's
    /// `CAST(julianday(now) - julianday(last_used_at) AS INTEGER)`.
    ///
    /// A negative age (a clock that moved backwards, or an imported future timestamp) is
    /// left negative on purpose so it lands in the freshest bucket in both implementations
    /// rather than being clamped differently on each side.
    static func ageInDays(from lastUsedAt: Date, to now: Date) -> Int {
        Int(now.timeIntervalSince(lastUsedAt) / 86_400)
    }

    static func score(useCount: Int, lastUsedAt: Date?, now: Date) -> Int {
        guard let lastUsedAt else {
            return neverUsedScore
        }
        return useCount * recencyWeight(ageDays: ageInDays(from: lastUsedAt, to: now))
    }

    /// The same score as a SQL expression, generated from `recencyBuckets` so the table
    /// stays the single source of truth.
    ///
    /// - Parameter nowJulianDay: SQL that evaluates to the current Julian day. Production
    ///   passes SQLite's own `julianday('now')` (UTC, matching how GRDB stores dates); tests
    ///   pin it to a literal so the expected order is stable.
    static func sqlScoreExpression(
        useCountColumn: String = "entries.use_count",
        lastUsedAtColumn: String = "entries.last_used_at",
        nowJulianDay: String = "julianday('now')"
    ) -> String {
        let age = "CAST(\(nowJulianDay) - julianday(\(lastUsedAtColumn)) AS INTEGER)"
        var branches = ["WHEN \(lastUsedAtColumn) IS NULL THEN \(neverUsedScore)"]
        branches += recencyBuckets.map { bucket in
            "WHEN \(age) < \(bucket.maxAgeDays) THEN \(bucket.weight)"
        }
        return """
            (\(useCountColumn) * (CASE
                \(branches.joined(separator: "\n    "))
                ELSE \(staleWeight)
            END))
            """
    }

    /// `ORDER BY` for every list the user reads, generated once so the four repository
    /// queries and the panel's in-memory sort cannot fall out of step.
    ///
    /// `sort_order` is deliberately absent — see the type documentation. The column is kept
    /// so import/export round-trips stay compatible, but nothing ranks by it any more.
    static func sqlOrderByClause(includeProjectPriority: Bool, nowJulianDay: String = "julianday('now')") -> String {
        let projectPriority = includeProjectPriority ? "\n    project_priority ASC," : ""
        return """
            ORDER BY
                entries.is_pinned DESC,
                \(sqlScoreExpression(nowJulianDay: nowJulianDay)) DESC,
                entries.last_used_at DESC,
                entries.use_count DESC,\(projectPriority)
                entries.updated_at DESC,
                entries.id ASC
            """
    }

    /// The comparator behind `sqlOrderByClause`, for the panel's in-memory re-sort.
    static func isOrderedBefore(_ lhs: Entry, _ rhs: Entry, currentProjectId: String?, now: Date) -> Bool {
        if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned
        }
        let lhsScore = score(useCount: lhs.useCount, lastUsedAt: lhs.lastUsedAt, now: now)
        let rhsScore = score(useCount: rhs.useCount, lastUsedAt: rhs.lastUsedAt, now: now)
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        let lhsLastUsedAt = lhs.lastUsedAt ?? .distantPast
        let rhsLastUsedAt = rhs.lastUsedAt ?? .distantPast
        if lhsLastUsedAt != rhsLastUsedAt {
            return lhsLastUsedAt > rhsLastUsedAt
        }
        if lhs.useCount != rhs.useCount {
            return lhs.useCount > rhs.useCount
        }
        if let currentProjectId {
            let lhsCurrent = lhs.projectId == currentProjectId
            let rhsCurrent = rhs.projectId == currentProjectId
            if lhsCurrent != rhsCurrent {
                return lhsCurrent
            }
        }
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id < rhs.id
    }
}
