import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

@MainActor
final class HistoryPagingTests: XCTestCase {
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

    func testFirstPageIs50NewestFirstWithMore() throws {
        let c = try ctx(); try seed(c, strength: 40, cardio: 40)
        let p = try WorkoutRepository.historyPage(HistoryPageRequest(), in: c)
        XCTAssertEqual(p.entries.count, 50)
        XCTAssertTrue(p.hasMore)
        XCTAssertEqual(p.entries.map(\.date), p.entries.map(\.date).sorted(by: >))
    }

    func testSecondPageContinuesWithoutGapsOrDuplicates() throws {
        let c = try ctx(); try seed(c, strength: 40, cardio: 40)
        let p1 = try WorkoutRepository.historyPage(HistoryPageRequest(), in: c)
        let p2 = try WorkoutRepository.historyPage(HistoryPageRequest(cursor: p1.nextCursor), in: c)
        XCTAssertEqual(p2.entries.count, 30)
        XCTAssertFalse(p2.hasMore)
        let ids = (p1.entries + p2.entries).map(\.id)
        XCTAssertEqual(Set(ids).count, 80)
        let dates = (p1.entries + p2.entries).map(\.date)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testHasMoreBoundary() throws {
        let c = try ctx(); try seed(c, strength: 25, cardio: 25)
        XCTAssertFalse(try WorkoutRepository.historyPage(HistoryPageRequest(), in: c).hasMore)
        try seed(c, strength: 1, cardio: 0)
        XCTAssertTrue(try WorkoutRepository.historyPage(HistoryPageRequest(), in: c).hasMore)
    }

    func testEqualTimestampsSurvivePageBoundary() throws {
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
        XCTAssertEqual(all.count, 80)
        XCTAssertEqual(Set(all).count, 80)
        XCTAssertEqual(all.map(\.uuidString), all.map(\.uuidString).sorted(by: >))
    }

    func testVisibilityIsExclusiveAndPaginatesIndependently() throws {
        let c = try ctx(); try seed(c, strength: 60, cardio: 0, deleted: 55)
        let active = try WorkoutRepository.historyPage(HistoryPageRequest(visibility: .active), in: c)
        let deleted = try WorkoutRepository.historyPage(HistoryPageRequest(visibility: .deleted), in: c)
        XCTAssertEqual(active.entries.count, 5); XCTAssertFalse(active.hasMore)
        XCTAssertEqual(deleted.entries.count, 50); XCTAssertTrue(deleted.hasMore)
        XCTAssertTrue(Set(active.entries.map(\.id)).isDisjoint(with: deleted.entries.map(\.id)))
        XCTAssertTrue(try WorkoutRepository.hasDeletedHistory(in: c))
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

    func testStateMachineRequestsBoundedWindow() {
        let f = Fake()
        let s = HistoryPagingState(fetcher: f)
        s.reload()
        XCTAssertEqual(f.requests.count, 1)
        XCTAssertEqual(f.requests[0].limit, 50)
        XCTAssertEqual(f.requests[0].fetchLimit, 51)
        XCTAssertNil(f.requests[0].cursor)
    }

    func testStateMachinePagesAndResets() throws {
        let c = try ctx(); try seed(c, strength: 60, cardio: 60, deleted: 3)
        let s = HistoryPagingState(fetcher: WorkoutHistoryPageFetcher(context: c))
        s.reload()
        XCTAssertEqual(s.entries.count, 50); XCTAssertTrue(s.hasMore)
        let first = s.entries.map(\.id)
        s.loadMore()
        XCTAssertEqual(Array(s.entries.map(\.id).prefix(50)), first)
        XCTAssertEqual(s.entries.count, 100)
        XCTAssertEqual(Set(s.entries.map(\.id)).count, 100)
        s.setVisibility(.deleted)
        XCTAssertEqual(s.entries.count, 3); XCTAssertFalse(s.hasMore)
        s.setVisibility(.active)
        XCTAssertEqual(s.entries.count, 50)
        // Soft-delete the newest row, then reload: it leaves the active page.
        switch s.entries.first {
        case .strength(let top)?: try WorkoutRepository.softDeleteSession(top, in: c)
        case .cardio(let top)?: try WorkoutRepository.softDeleteCardio(top, in: c)
        case nil: XCTFail("empty")
        }
        let topId = s.entries.first?.id
        s.reload()
        XCTAssertNotEqual(s.entries.first?.id, topId)
        XCTAssertEqual(s.entries.count, 50)
    }

    func testProgressRoutePolicy() {
        XCTAssertEqual(ProgressDataOwner.owner(for: .workoutHistory), .pagedHistory)
        for q in ProgressQuestion.alphabetical where q != .workoutHistory {
            XCTAssertEqual(ProgressDataOwner.owner(for: q), .analytics)
        }
    }

    func testLargeStoreRequestSizeStaysBounded() {
        let r = HistoryPageRequest()
        XCTAssertEqual(r.fetchLimit, HistoryPageRequest.pageSize + 1)
    }
}
