import Foundation

/// Search service for entries: handles FTS search, mixed project results, and PRD-compliant sorting.
final class EntrySearchService: @unchecked Sendable {

    static let allProjectsScopeId = "__all_projects__"

    private let entryRepository: EntryRepository

    init(entryRepository: EntryRepository) {
        self.entryRepository = entryRepository
    }

    /// Search entries for the current project + default project.
    /// Empty query returns all entries for the current scope.
    /// When `query` or `tag` is non-empty, if the scoped search returns zero matches,
    /// `searchWithScopeFallback` can automatically expand across all non-archived projects
    /// so the user doesn't hit a dead end when a prompt lives in another category/project.
    struct SearchResult {
        let entries: [Entry]
        let isGlobalFallback: Bool
    }

    func searchWithScopeFallback(
        query: String,
        currentProjectId: String,
        defaultProjectId: String?,
        tag: String? = nil
    ) throws -> SearchResult {
        let scoped = try search(
            query: query,
            currentProjectId: currentProjectId,
            defaultProjectId: defaultProjectId,
            tag: tag
        )
        guard currentProjectId != Self.allProjectsScopeId else {
            return SearchResult(entries: scoped, isGlobalFallback: false)
        }
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard scoped.isEmpty, (!normalizedQuery.isEmpty || (tag != nil && !(tag?.isEmpty ?? true))) else {
            return SearchResult(entries: scoped, isGlobalFallback: false)
        }
        let globalMatches = try entryRepository.searchAll(
            query: normalizedQuery,
            tag: tag,
            excludeArchivedProjects: true
        )
        return SearchResult(entries: globalMatches, isGlobalFallback: !globalMatches.isEmpty)
    }

    func search(
        query: String,
        currentProjectId: String,
        defaultProjectId: String?,
        tag: String? = nil
    ) throws -> [Entry] {
        let startTime = DispatchTime.now().uptimeNanoseconds
        let currentId = currentProjectId
        let defaultId = defaultProjectId ?? ""
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let results: [Entry]
            let scope: String
            let includesDefaultProject: Bool

            if currentId == Self.allProjectsScopeId {
                scope = (normalizedQuery.isEmpty && tag == nil) ? "all_projects_browse" : "all_projects_search"
                includesDefaultProject = true
                results = try entryRepository.searchAll(
                    query: normalizedQuery,
                    tag: tag,
                    excludeArchivedProjects: true
                )
            } else if currentId == defaultId {
                scope = "default_only"
                includesDefaultProject = false
                if normalizedQuery.isEmpty, tag == nil {
                    results = try entryRepository.fetchByProject(currentId)
                } else {
                    results = try entryRepository.search(
                        query: normalizedQuery,
                        projectIds: [currentId],
                        currentProjectId: currentId,
                        tag: tag
                    )
                }
            } else if normalizedQuery.isEmpty, tag == nil {
                scope = "mixed_browse"
                includesDefaultProject = true
                results = try entryRepository.fetchMixed(currentProjectId: currentId, defaultProjectId: defaultId)
            } else {
                scope = "mixed_search"
                includesDefaultProject = true
                results = try entryRepository.search(
                    query: normalizedQuery,
                    currentProjectId: currentId,
                    defaultProjectId: defaultId,
                    tag: tag
                )
            }

            let durationMs = elapsedMilliseconds(since: startTime)
            logSearchSample(
                scope: scope,
                query: normalizedQuery,
                resultCount: results.count,
                durationMs: durationMs,
                includesDefaultProject: includesDefaultProject
            )
            return results
        } catch {
            let durationMs = elapsedMilliseconds(since: startTime)
            let failureScope: String = {
                if currentId == Self.allProjectsScopeId {
                    return "all_projects"
                }
                return currentId == defaultId ? "default_only" : "mixed"
            }()
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
