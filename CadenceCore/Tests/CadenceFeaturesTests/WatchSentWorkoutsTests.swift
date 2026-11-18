import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchSentWorkoutsTests {
    @Test func contextRoundTripKeepsStrengthAndCardio() {
        let strength = WatchSentWorkouts.strengthSession(
            title: "Push", exercises: [(name: "Bench Press", repTargets: [8, 8, 6])])
        let cardio = WatchSentWorkouts.cardioSession(title: "Run", cardioType: "run", durationMinutes: 30, zone: 2)
        let context = WatchSentWorkouts.contextDict([strength, cardio])
        let decoded = WatchSentWorkouts.sessions(from: context)
        #expect(decoded.map(\.id) == [strength.id, cardio.id])
        #expect(decoded[0].exerciseNames == ["Bench Press"])
        #expect(decoded[0].repLadder == [8, 8, 6])
        #expect(decoded[1].cardioType == "run")
        #expect(decoded[1].durationMinutes == 30)
    }

    @Test func latestSentWorkoutSupersedesOlderPendingWorkout() {
        let a = WatchSentWorkouts.strengthSession(title: "A", exercises: [])
        let b = WatchSentWorkouts.cardioSession(title: "B", cardioType: "walk", durationMinutes: 20)
        let sent = WatchSentWorkouts.adding(b, to: WatchSentWorkouts.adding(a, to: []))
        #expect(WatchSentWorkouts.pending(sent, consumedIDs: []).map(\.id) == [b.id])
        #expect(WatchSentWorkouts.pending(sent, consumedIDs: [b.id]).isEmpty)
    }

    @Test func sendingSameWorkoutTwiceRetainsOnePendingSession() {
        let first = WatchSentWorkouts.cardioSession(title: "Run", cardioType: "run", durationMinutes: 20)
        let secondTap = WatchSentWorkouts.cardioSession(title: "Run", cardioType: "run", durationMinutes: 20)
        let sent = WatchSentWorkouts.adding(secondTap, to: [first])
        #expect(sent.count == 1)
        #expect(sent.first?.id == first.id)
    }

    @Test func incomingContextCarriesSentWorkoutsOnlyWhenPresent() {
        let none = WatchSync.IncomingContext.from(context: [:], applyingTo: .init())
        #expect(none.sentWorkouts == nil)
        let sent = WatchSentWorkouts.cardioSession(title: "Row", cardioType: "rowing", durationMinutes: 15)
        let some = WatchSync.IncomingContext.from(context: WatchSentWorkouts.contextDict([sent]), applyingTo: .init())
        #expect(some.sentWorkouts?.map(\.id) == [sent.id])
    }
}
