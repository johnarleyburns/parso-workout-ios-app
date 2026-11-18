#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

@MainActor
struct HistoryPagingTests {
    private func ctx() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @discardableResult
    private func seed(_ c: ModelContext, strength: Int, cardio: Int, deleted: Int = 0, sameDate: Bool = false) throws -> Int {
        for i in 0..<strength {
            let s = WorkoutSession(title: "S\(i)", date: sameDate ? base : base.addingTimeInterval(Double(i) * 120))
            c.insert(s)
            if i < deleted { s.deletedAt = Date() }
        }
        for i in 0..<cardio {
            let w = CardioWorkout(type: .run, start: sameDate ? base : base.addingTimeInterval(Double(i) * 120 + 60),
                                  end: base.addingTimeInterval(Double(i) * 120 + 600), source: .iphone)
            c.insert(w)
        }
        try c.save()
        return strength + cardio
    }

    @Test func firstPageIs50NewestFirstWithMore() throws {
        let c = try ctx(); try seed(c, strength: 40, cardio: 40)
        let p = try WorkoutRepository.historyPage(HistoryPageRequest(), in: c)
        #expect(p.entries.count == 50)
        #expect(p.hasMore)
        #expect(p.entries.map(\.date) == p.entries.map(\.date).sorted(by: >))
    }

    @Test func secondPageContinuesWithoutGapsOrDuplicates() throws {
        let c = try ctx(); try seed(c, strength: 40, cardio: 40)
        let p1 = try WorkoutRepository.historyPage(HistoryPageRequest(), in: c)
        let p2 = try WorkoutRepository.historyPage(HistoryPageRequest(cursor: p1.nextCursor), in: c)
        #expect(p2.entries.count == 30)
        #expect(!p2.hasMore)
        let ids = (p1.entries + p2.entries).map(\.id)
        #expect(Set(ids).count == 80)
        let dates = (p1.entries + p2.entries).map(\.date)
        #expect(dates == dates.sorted(by: >))
    }

    @Test func hasMoreBoundary() throws {
        let c = try ctx(); try seed(c, strength: 25, cardio: 25)
        #expect(!(try WorkoutRepository.historyPage(HistoryPageRequest(), in: c).hasMore))
        try seed(c, strength: 1, cardio: 0)
        #expect(try WorkoutRepository.historyPage(HistoryPageRequest(), in: c).hasMore)
    }

    @Test func equalTimestampsSurvivePageBoundary() throws {
        let c = try ctx(); try seed(c, strength: 40, cardio: 40, sameDate: true)
        var all: [UUID] = []
        var cursor: HistoryCursor?
        var pages = 0
        repeat {
            let p = try WorkoutRepository.historyPage(HistoryPageRequest(limit: 7, cursor: cursor), in: c)
            all += p.entries.map(\.id)
            cursor = p.hasMore ? p.nextCursor : nil
            pages += 1
        } while cursor != nil && pages < 50
        #expect(all.count == 80)
        #expect(Set(all).count == 80)
        #expect(all.map(\.uuidString) == all.map(\.uuidString).sorted(by: >))
    }

    @Test func visibilityIsExclusiveAndPaginatesIndependently() throws {
        let c = try ctx(); try seed(c, strength: 60, cardio: 0, deleted: 55)
        let active = try WorkoutRepository.historyPage(HistoryPageRequest(visibility: .active), in: c)
        let deleted = try WorkoutRepository.historyPage(HistoryPageRequest(visibility: .deleted), in: c)
        #expect(active.entries.count == 5); #expect(!active.hasMore)
        #expect(deleted.entries.count == 50); #expect(deleted.hasMore)
        #expect(Set(active.entries.map(\.id)).isDisjoint(with: deleted.entries.map(\.id)))
        #expect(try WorkoutRepository.hasDeletedHistory(in: c))
    }

    // MARK: State machine with a fake fetcher

    private final class Fake: HistoryPageFetching {
        var requests: [HistoryPageRequest] = []
        var total = 120
        func fetchPage(_ r: HistoryPageRequest) throws -> HistoryPage<WorkoutHistoryEntry> {
            requests.append(r)
            return HistoryPage(entries: [], hasMore: false, nextCursor: nil)
        }
    }

    @Test func stateMachineRequestsBoundedWindow() {
        let f = Fake()
        let s = HistoryPagingState(fetcher: f)
        s.reload()
        #expect(f.requests.count == 1)
        #expect(f.requests[0].limit == 50)
        #expect(f.requests[0].fetchLimit == 51)
        #expect(f.requests[0].cursor == nil)
    }

    @Test func stateMachinePagesAndResets() throws {
        let c = try ctx(); try seed(c, strength: 60, cardio: 60, deleted: 3)
        let s = HistoryPagingState(fetcher: WorkoutHistoryPageFetcher(context: c))
        s.reload()
        #expect(s.entries.count == 50); #expect(s.hasMore)
        let first = s.entries.map(\.id)
        s.loadMore()
        #expect(Array(s.entries.map(\.id).prefix(50)) == first)
        #expect(s.entries.count == 100)
        #expect(Set(s.entries.map(\.id)).count == 100)
        s.setVisibility(.deleted)
        #expect(s.entries.count == 3); #expect(!s.hasMore)
        s.setVisibility(.active)
        #expect(s.entries.count == 50)
        // Soft-delete the newest row, then reload: it leaves the active page.
        switch s.entries.first {
        case .strength(let top)?: try WorkoutRepository.softDeleteSession(top, in: c)
        case .cardio(let top)?: try WorkoutRepository.softDeleteCardio(top, in: c)
        case nil: Issue.record("empty")
        }
        let topId = s.entries.first?.id
        s.reload()
        #expect(s.entries.first?.id != topId)
        #expect(s.entries.count == 50)
    }

    @Test func progressRoutePolicy() {
        #expect(ProgressDataOwner.owner(for: .workoutHistory) == .pagedHistory)
        for q in ProgressQuestion.alphabetical where q != .workoutHistory && q != .observations {
            #expect(ProgressDataOwner.owner(for: q) == .analytics)
        }
    }

    @Test func largeStoreRequestSizeStaysBounded() {
        let r = HistoryPageRequest()
        #expect(r.fetchLimit == HistoryPageRequest.pageSize + 1)
    }

    // MARK: Deleted control (#615)

    @Test func controlStateTransitions() {
        #expect(DeletedHistoryControlState.make(visibility: .active, deletedCount: 0) == nil)
        #expect(DeletedHistoryControlState.make(visibility: .deleted, deletedCount: 0) == nil)
        let a = DeletedHistoryControlState.make(visibility: .active, deletedCount: 2)
        #expect(a?.title == "Show Deleted"); #expect(a?.nextVisibility == .deleted)
        let d = DeletedHistoryControlState.make(visibility: .deleted, deletedCount: 1)
        #expect(d?.title == "Back to Workouts"); #expect(d?.nextVisibility == .active)
    }

    @Test func deletedCountCountsBothKindsAndSoftDeleteMakesControlAvailable() throws {
        let c = try ctx(); try seed(c, strength: 3, cardio: 2)
        let f = WorkoutHistoryPageFetcher(context: c)
        let s = HistoryPagingState(fetcher: f)
        s.reload(deletedCount: try WorkoutRepository.deletedHistoryCount(in: c))
        #expect(s.deletedControl == nil)
        let w = try c.fetch(FetchDescriptor<CardioWorkout>()).first!
        try WorkoutRepository.softDeleteCardio(w, in: c)
        s.reload(deletedCount: try WorkoutRepository.deletedHistoryCount(in: c))
        #expect(s.deletedControl?.title == "Show Deleted")
        s.toggleDeleted()
        #expect(s.visibility == .deleted)
        #expect(s.entries.count == 1)
        #expect(s.deletedControl?.title == "Back to Workouts")
    }

    @Test func restoringFinalDeletedReturnsToActive() throws {
        let c = try ctx(); try seed(c, strength: 2, cardio: 0, deleted: 1)
        let s = HistoryPagingState(fetcher: WorkoutHistoryPageFetcher(context: c))
        s.reload(deletedCount: try WorkoutRepository.deletedHistoryCount(in: c))
        s.toggleDeleted()
        #expect(s.entries.count == 1)
        let dead = try c.fetch(FetchDescriptor<WorkoutSession>()).first { $0.deletedAt != nil }!
        dead.deletedAt = nil; try c.save()
        s.reload(deletedCount: try WorkoutRepository.deletedHistoryCount(in: c))
        #expect(s.visibility == .active)
        #expect(s.deletedControl == nil)
        #expect(s.entries.count == 2)
    }

    @Test func modeTransitionRequestsFirstPageWithNoCursor() {
        let f = Fake()
        let s = HistoryPagingState(fetcher: f)
        s.reload(deletedCount: 3)
        s.toggleDeleted()
        #expect(f.requests.last?.visibility == .deleted)
        #expect(f.requests.last?.cursor == nil)
        #expect(s.entries.isEmpty)
    }
}
#endif
