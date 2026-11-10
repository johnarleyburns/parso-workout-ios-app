import Foundation
import Observation
import CadenceCore

/// Which data owner the Progress route instantiates. Only analytics routes may
/// hold the all-history `@Query`s; My Workouts owns its bounded paged fetch.
public enum ProgressDataOwner: Equatable, Sendable {
    case pagedHistory
    case analytics

    public static func owner(for question: ProgressQuestion) -> ProgressDataOwner {
        question == .workoutHistory ? .pagedHistory : .analytics
    }
}

/// UI state machine for My Workouts: holds already-displayed rows and asks the
/// fetcher only for the next bounded window.
@MainActor
@Observable
public final class HistoryPagingState {
    public private(set) var entries: [WorkoutHistoryEntry] = []
    public private(set) var hasMore = false
    public private(set) var visibility: HistoryVisibility = .active
    public private(set) var lastError: String?
    @ObservationIgnored private var nextCursor: HistoryCursor?
    @ObservationIgnored private let fetcher: any HistoryPageFetching
    @ObservationIgnored private let pageSize: Int

    public init(fetcher: any HistoryPageFetching, pageSize: Int = HistoryPageRequest.pageSize) {
        self.fetcher = fetcher
        self.pageSize = pageSize
    }

    /// Resets to the first page of the current visibility.
    public func reload() {
        entries = []; hasMore = false; nextCursor = nil
        append(cursor: nil)
    }

    /// Switching visibility discards loaded rows and cursor.
    public func setVisibility(_ v: HistoryVisibility) {
        visibility = v
        reload()
    }

    /// Appends the next page; no-op when there is nothing more.
    public func loadMore() {
        guard hasMore, let cursor = nextCursor else { return }
        append(cursor: cursor)
    }

    private func append(cursor: HistoryCursor?) {
        do {
            let page = try fetcher.fetchPage(HistoryPageRequest(limit: pageSize, visibility: visibility, cursor: cursor))
            let known = Set(entries.map(\.id))
            entries += page.entries.filter { !known.contains($0.id) }
            hasMore = page.hasMore
            nextCursor = page.nextCursor
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
