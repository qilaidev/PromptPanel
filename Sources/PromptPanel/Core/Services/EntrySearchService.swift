import Foundation

/// Search service for entries: handles FTS search, mixed project results, and PRD-compliant sorting.
final class EntrySearchService: @unchecked Sendable {

    private let entryRepository: EntryRepository

    init(entryRepository: EntryRepository) {
        self.entryRepository = entryRepository
    }

    /// Search entries for the current project + default project.
    /// Empty query returns all entries (no filter).
    func search(query: String, currentProjectId: String, defaultProjectId: String?) throws -> [Entry] {
        let startTime = DispatchTime.now().uptimeNanoseconds
        let currentId = currentProjectId
        let defaultId = defaultProjectId ?? ""
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let results: [Entry]
            let scope: String

            if currentId == defaultId {
                scope = "default_only"
                if normalizedQuery.isEmpty {
                    results = try entryRepository.fetchByProject(currentId)
                } else {
                    results = try entryRepository.search(
                        query: normalizedQuery,
                        currentProjectId: currentId,
                        defaultProjectId: defaultId
                    )
                }
            } else if normalizedQuery.isEmpty {
                scope = "mixed_browse"
                results = try entryRepository.fetchMixed(currentProjectId: currentId, defaultProjectId: defaultId)
            } else {
                scope = "mixed_search"
                results = try entryRepository.search(
                    query: normalizedQuery,
                    currentProjectId: currentId,
                    defaultProjectId: defaultId
                )
            }

            let durationMs = elapsedMilliseconds(since: startTime)
            logSearchSample(
                scope: scope,
                query: normalizedQuery,
                resultCount: results.count,
                durationMs: durationMs,
                includesDefaultProject: currentId != defaultId
            )
            return results
        } catch {
            let durationMs = elapsedMilliseconds(since: startTime)
            let failureScope = currentId == defaultId ? "default_only" : "mixed"
            let queryTokenCount = tokenCount(for: normalizedQuery)
            PPLogger.search.error(
                "Search failed scope=\(failureScope) duration_ms=\(durationMs) query_length=\(normalizedQuery.count) token_count=\(queryTokenCount) error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    private func logSearchSample(
        scope: String,
        query: String,
        resultCount: Int,
        durationMs: Int,
        includesDefaultProject: Bool
    ) {
        let queryLength = query.count
        let tokenCount = tokenCount(for: query)
        // Debug, not info: this fires on every debounced keystroke in both the panel
        // and the library. The latency warning below is the line that matters.
        PPLogger.search.debug(
            "Search completed scope=\(scope) duration_ms=\(durationMs) result_count=\(resultCount) query_length=\(queryLength) token_count=\(tokenCount) includes_default_project=\(includesDefaultProject)"
        )

        if durationMs > Constants.searchLatencyTargetMs {
            PPLogger.search.warning(
                "search_latency_exceeded scope=\(scope) duration_ms=\(durationMs) target_ms=\(Constants.searchLatencyTargetMs) result_count=\(resultCount) query_length=\(queryLength)"
            )
        }
    }

    private func tokenCount(for query: String) -> Int {
        query.split(whereSeparator: \.isWhitespace).count
    }

    private func elapsedMilliseconds(since startTime: UInt64) -> Int {
        Int((DispatchTime.now().uptimeNanoseconds - startTime) / 1_000_000)
    }
}
