import Foundation
import GRDB

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
/// The order is now `是否置顶 → frecency → 最近使用时间 → 使用次数 → …`, where frecency decays
/// an entry's use count by how long it has been sitting untouched:
///
///     score = use_count × 2 ^ (−age_in_days / halfLifeDays)
///
/// One parameter with one meaning: after `halfLifeDays` without use, an entry counts for
/// half as much. A prompt used 600 times this week outranks one used 3 times in July, and a
/// once-hot prompt nobody has touched in a year sinks on its own instead of holding the top
/// slot forever on historical volume alone.
///
/// A continuous curve rather than coarse age buckets, because buckets have cliffs: an entry
/// that crossed a boundary overnight jumped several places for no reason the user could see,
/// and the boundaries themselves were six unexplainable magic numbers.
///
/// **SQL and Swift run the same code.** `databaseFunction` registers `score(useCount:…)` with
/// SQLite, so the repository's `ORDER BY` and the panel's in-memory comparator apply the same
/// formula — not "generated from one table", literally the same function. That also keeps the
/// ordering independent of whether this SQLite was built with the optional math extension
/// (`pow`/`exp` are not guaranteed to exist).
///
/// The one thing that is not bit-identical between the two is `now`: SQL binds it through
/// GRDB, which round-trips a `Date` at millisecond precision, while the in-memory sort passes
/// a full-precision `Date`. That shifts every score by the same sub-millisecond factor, so it
/// can only reorder entries whose scores already agree to ~10 significant digits — entries
/// that are interchangeable to the user by construction.
enum EntryRanking {
    /// Days without use after which an entry counts for half as much.
    ///
    /// 90 days is tuned against a real library: it lets "19 uses, three months ago" stay
    /// ahead of "6 uses, today" — frequency still leads — while "500 uses, two years ago"
    /// finally drops below a prompt used a handful of times this week. Shorter half-lives
    /// (30 days) let a single recent use outrank months of accumulated usage, which is the
    /// complaint this replaced.
    static let halfLifeDays: Double = 90

    /// Score for an entry that has never been used. Zero, so it sorts below everything with
    /// any history and falls through to the `updated_at` tiebreaker.
    static let neverUsedScore: Double = 0

    /// Name of the SQL function that exposes `score` to `ORDER BY`.
    static let sqlFunctionName = "pp_frecency"

    static func ageInDays(from lastUsedAt: Date, to now: Date) -> Double {
        now.timeIntervalSince(lastUsedAt) / 86_400
    }

    static func score(useCount: Int, lastUsedAt: Date?, now: Date) -> Double {
        guard let lastUsedAt else {
            return neverUsedScore
        }
        // A negative age (a clock that moved backwards, or an imported future timestamp)
        // is clamped rather than amplified: without this, a timestamp a year in the future
        // would score 4× its use count and park itself at the top.
        let ageDays = max(ageInDays(from: lastUsedAt, to: now), 0)
        return Double(useCount) * pow(2, -ageDays / halfLifeDays)
    }

    /// `score` as a SQLite scalar function: `pp_frecency(use_count, last_used_at, now)`.
    ///
    /// `now` is passed in rather than read from the clock inside the function so a query is
    /// reproducible and the tests can pin it.
    static let databaseFunction = DatabaseFunction(
        sqlFunctionName,
        argumentCount: 3,
        pure: true
    ) { values in
        let useCount = Int.fromDatabaseValue(values[0]) ?? 0
        let lastUsedAt = Date.fromDatabaseValue(values[1])
        guard let now = Date.fromDatabaseValue(values[2]) else {
            return neverUsedScore
        }
        return score(useCount: useCount, lastUsedAt: lastUsedAt, now: now)
    }

    /// `ORDER BY` for every list the user reads, so the four repository queries stay in step.
    ///
    /// The clause carries exactly one bind parameter — `now`, for `pp_frecency` — which the
    /// caller must append after its own arguments.
    ///
    /// `sort_order` is deliberately absent; see the type documentation. The column is kept so
    /// import/export round-trips stay compatible, but nothing ranks by it any more.
    static func sqlOrderByClause(includeProjectPriority: Bool) -> String {
        let projectPriority = includeProjectPriority ? "\n    project_priority ASC," : ""
        return """
            ORDER BY
                entries.is_pinned DESC,
                \(sqlFunctionName)(entries.use_count, entries.last_used_at, ?) DESC,
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
