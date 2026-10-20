import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchSentWorkoutsTests: XCTestCase {
    func testContextRoundTripKeepsStrengthAndCardio() {
        let strength = WatchSentWorkouts.strengthSession(
            title: "Push", exercises: [(name: "Bench Press", repTargets: [8, 8, 6])])
        let cardio = WatchSentWorkouts.cardioSession(title: "Run", cardioType: "run", durationMinutes: 30, zone: 2)
        let context = WatchSentWorkouts.contextDict([strength, cardio])
        let decoded = WatchSentWorkouts.sessions(from: context)
        XCTAssertEqual(decoded.map(\.id), [strength.id, cardio.id])
        XCTAssertEqual(decoded[0].exerciseNames, ["Bench Press"])
        XCTAssertEqual(decoded[0].repLadder, [8, 8, 6])
        XCTAssertEqual(decoded[1].cardioType, "run")
        XCTAssertEqual(decoded[1].durationMinutes, 30)
    }

    func testMultipleSentWorkoutsAllShowAndStartedOnesDisappear() {
        let a = WatchSentWorkouts.strengthSession(title: "A", exercises: [])
        let b = WatchSentWorkouts.cardioSession(title: "B", cardioType: "walk", durationMinutes: 20)
        let sent = WatchSentWorkouts.adding(b, to: WatchSentWorkouts.adding(a, to: []))
        XCTAssertEqual(WatchSentWorkouts.pending(sent, consumedIDs: []).count, 2)
        XCTAssertEqual(WatchSentWorkouts.pending(sent, consumedIDs: [a.id]).map(\.id), [b.id])
    }

    func testAddingReplacesSameIDAndCapsList() {
        var sent: [WatchSync.TodayPlan.Session] = []
        for i in 0..<(WatchSentWorkouts.limit + 3) {
            sent = WatchSentWorkouts.adding(WatchSentWorkouts.cardioSession(title: "\(i)", cardioType: "run", durationMinutes: 10), to: sent)
        }
        XCTAssertEqual(sent.count, WatchSentWorkouts.limit)
        let repeated = WatchSentWorkouts.cardioSession(id: UUID(uuidString: sent[0].id)!, title: "new", cardioType: "run", durationMinutes: 5)
        XCTAssertEqual(WatchSentWorkouts.adding(repeated, to: sent).filter { $0.id == repeated.id }.count, 1)
    }

    func testIncomingContextCarriesSentWorkoutsOnlyWhenPresent() {
        let none = WatchSync.IncomingContext.from(context: [:], applyingTo: .init())
        XCTAssertNil(none.sentWorkouts)
        let sent = WatchSentWorkouts.cardioSession(title: "Row", cardioType: "rowing", durationMinutes: 15)
        let some = WatchSync.IncomingContext.from(context: WatchSentWorkouts.contextDict([sent]), applyingTo: .init())
        XCTAssertEqual(some.sentWorkouts?.map(\.id), [sent.id])
    }
}
