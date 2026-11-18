import Foundation
import SwiftData

/// Which soft-delete partition of the history a page request reads.
public enum HistoryVisibility: Equatable, Sendable {
    case active
    case deleted
}

/// Position of the last row already shown. The total order of the unified feed
/// is `(date DESC, id.uuidString DESC)`: `date` is `WorkoutSession.date` /
/// `CardioWorkout.start`; the UUID string is unique across both record kinds
/// (ids are random v4), so equal timestamps resolve deterministically and a page
/// boundary can never skip or repeat a row. SwiftData cannot sort on a UUID
/// reliably, so the tie-break is applied in memory over a bounded candidate window.
public struct HistoryCursor: Equatable, Sendable {
    public let date: Date
    public let id: UUID
    public init(date: Date, id: UUID) { self.date = date; self.id = id }
}

public struct HistoryPageRequest: Equatable, Sendable {
    /// Named policy: rows shown per page.
    public static let pageSize = 50
    /// Extra row fetched past the page solely to learn `hasMore`.
    public static let lookahead = 1

    public let limit: Int
    public let visibility: HistoryVisibility
    public let cursor: HistoryCursor?

    public init(limit: Int = HistoryPageRequest.pageSize,
                visibility: HistoryVisibility = .active,
                cursor: HistoryCursor? = nil) {
        self.limit = limit; self.visibility = visibility; self.cursor = cursor
    }

    /// The most rows any single backing fetch may return for this request.
    public var fetchLimit: Int { limit + Self.lookahead }
}

public struct HistoryPage<Entry: Identifiable> {
    public let entries: [Entry]
    public let hasMore: Bool
    public let nextCursor: HistoryCursor?
    public init(entries: [Entry], hasMore: Bool, nextCursor: HistoryCursor?) {
        self.entries = entries; self.hasMore = hasMore; self.nextCursor = nextCursor
    }
}

extension HistoryPage: Sendable where Entry: Sendable {}

@MainActor
public protocol HistoryPageFetching {
    func fetchPage(_ request: HistoryPageRequest) throws -> HistoryPage<WorkoutHistoryEntry>
}

/// Persistence-backed fetcher used by the History screen.
@MainActor
public struct WorkoutHistoryPageFetcher: HistoryPageFetching {
    private let context: ModelContext
    public init(context: ModelContext) { self.context = context }
    public func fetchPage(_ request: HistoryPageRequest) throws -> HistoryPage<WorkoutHistoryEntry> {
        try WorkoutRepository.historyPage(request, in: context)
    }
}

extension WorkoutHistoryEntry {
    var cursor: HistoryCursor { HistoryCursor(date: date, id: id) }

    /// `true` when `self` sorts strictly before `other` in the feed (newer first).
    func precedes(_ other: WorkoutHistoryEntry) -> Bool {
        date != other.date ? date > other.date : id.uuidString > other.id.uuidString
    }
}

extension WorkoutRepository {
    /// One bounded page of the unified feed. Each kind is fetched with
    /// `fetchLimit = limit + lookahead` (plus any rows sharing the boundary
    /// timestamp, so the in-memory tie-break is exact), then merged.
    public static func historyPage(_ request: HistoryPageRequest,
                                   in context: ModelContext) throws -> HistoryPage<WorkoutHistoryEntry> {
        let strength = try boundedStrength(request, context).map(WorkoutHistoryEntry.strength)
        let cardio = try boundedCardio(request, context).map(WorkoutHistoryEntry.cardio)
        var merged = (strength + cardio).sorted { $0.precedes($1) }
        if let c = request.cursor {
            merged = merged.filter { $0.date != c.date ? $0.date < c.date : $0.id.uuidString < c.id.uuidString }
        }
        let page = Array(merged.prefix(request.limit))
        return HistoryPage(entries: page,
                           hasMore: merged.count > request.limit,
                           nextCursor: page.last?.cursor)
    }

    /// Cheap existence check for the "View Deleted" affordance.
    public static func hasDeletedHistory(in context: ModelContext) throws -> Bool {
        var s = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.deletedAt != nil })
        s.fetchLimit = 1
        var c = FetchDescriptor<CardioWorkout>(predicate: #Predicate { $0.deletedAt != nil })
        c.fetchLimit = 1
        return try !context.fetch(s).isEmpty || !context.fetch(c).isEmpty
    }

    /// Bounded count of soft-deleted records (count queries, no record fetch).
    public static func deletedHistoryCount(in context: ModelContext) throws -> Int {
        let s = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.deletedAt != nil })
        let c = FetchDescriptor<CardioWorkout>(predicate: #Predicate { $0.deletedAt != nil })
        return try context.fetchCount(s) + context.fetchCount(c)
    }

    private static func boundedStrength(_ r: HistoryPageRequest, _ ctx: ModelContext) throws -> [WorkoutSession] {
        let deleted = r.visibility == .deleted
        let cursorDate = r.cursor?.date ?? .distantFuture
        // Strictly older rows (limited) and rows tied with the cursor (small set).
        var older = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { s in
                ((deleted && s.deletedAt != nil) || (!deleted && s.deletedAt == nil)) && s.date < cursorDate },
            sortBy: [SortDescriptor(\.date, order: .reverse)])
        older.fetchLimit = r.fetchLimit
        var rows = try ctx.fetch(older)
        if rows.count == r.fetchLimit, let boundary = rows.last?.date {
            let tied = try ctx.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { s in
                ((deleted && s.deletedAt != nil) || (!deleted && s.deletedAt == nil)) && s.date == boundary }))
            rows = rows.filter { $0.date != boundary } + tied
        }
        if let c = r.cursor {
            let cd = c.date
            rows += try ctx.fetch(FetchDescriptor<WorkoutSession>(predicate: #Predicate { s in
                ((deleted && s.deletedAt != nil) || (!deleted && s.deletedAt == nil)) && s.date == cd }))
        }
        return rows
    }

    private static func boundedCardio(_ r: HistoryPageRequest, _ ctx: ModelContext) throws -> [CardioWorkout] {
        let deleted = r.visibility == .deleted
        let cursorDate = r.cursor?.date ?? .distantFuture
        var older = FetchDescriptor<CardioWorkout>(
            predicate: #Predicate { c in
                ((deleted && c.deletedAt != nil) || (!deleted && c.deletedAt == nil)) && c.start < cursorDate },
            sortBy: [SortDescriptor(\.start, order: .reverse)])
        older.fetchLimit = r.fetchLimit
        var rows = try ctx.fetch(older)
        if rows.count == r.fetchLimit, let boundary = rows.last?.start {
            let tied = try ctx.fetch(FetchDescriptor<CardioWorkout>(predicate: #Predicate { c in
                ((deleted && c.deletedAt != nil) || (!deleted && c.deletedAt == nil)) && c.start == boundary }))
            rows = rows.filter { $0.start != boundary } + tied
        }
        if let cur = r.cursor {
            let cd = cur.date
            rows += try ctx.fetch(FetchDescriptor<CardioWorkout>(predicate: #Predicate { c in
                ((deleted && c.deletedAt != nil) || (!deleted && c.deletedAt == nil)) && c.start == cd }))
        }
        return rows
    }
}
