import Testing
import Foundation
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore
import CadencePhoneFeatures

// Release-CI quarantine (2026-11-20): two cancellation tests block cooperative
// threads on DispatchSemaphore.gate.wait(). Replace those gates with an async
// test seam before removing this condition.
@MainActor
@Suite(.enabled(if: !ReleaseCITestSupport.isReleaseCI))
final class WatchSingleExerciseSuggestionSessionTests {
    private func input(_ count: Int = 6) -> SuggestedWorkoutInput {
        let muscles = ["chest", "lats", "quadriceps", "shoulders", "hamstrings", "biceps"]
        let candidates = (0..<count).map {
            SuggestedExerciseCandidate(id: "c\($0)", name: "Move \($0)", mechanics: .compound,
                                       primaryMuscles: [muscles[$0 % muscles.count]],
                                       equipment: .barbell)
        }
        return SuggestedWorkoutInput(completedSetsByMuscle: [:], candidates: candidates,
                                     preferredSetsPerExercise: 3, trainingGoal: .hypertrophy)
    }

    private func exercise(_ id: String) -> SuggestedWorkoutExercise {
        SuggestedWorkoutExercise(candidateID: id, name: id, mechanics: .compound, plannedSets: 3,
                                 repRange: 8...12, contributions: [], selectionScore: 1)
    }

    @Test func initialResultMatchesSharedGenerator() async {
        let i = input()
        let session = WatchSingleExerciseSuggestionSession()
        #expect(session.state == .idle)
        session.suggest(input: i)
        #expect(session.state == .calculating)
        await session.pendingTask?.value
        let direct = SuggestedWorkoutGenerator.suggestSingleExercise(input: i, style: i.preferredStyle)
        #expect(direct != nil)
        #expect(session.state == .ready(direct!))
    }

    @Test func suggestAnotherNeverRepeatsAndLeavesInputUntouched() async {
        let i = input()
        let before = i
        let session = WatchSingleExerciseSuggestionSession()
        session.suggest(input: i)
        await session.pendingTask?.value
        var seen: [String] = []
        for _ in 0..<5 {
            guard case .ready(let shown) = session.state else {
                Issue.record("not ready")
                return
            }
            #expect(!seen.contains(shown.candidateID))
            seen.append(shown.candidateID)
            session.suggestAnother(input: i)
            await session.pendingTask?.value
        }
        #expect(i == before)
    }

    @Test func cancelClearsExclusionsAndState() async {
        let i = input()
        let session = WatchSingleExerciseSuggestionSession()
        session.suggest(input: i)
        await session.pendingTask?.value
        guard case .ready(let first) = session.state else {
            Issue.record()
            return
        }
        session.suggestAnother(input: i)
        await session.pendingTask?.value
        session.cancel()
        #expect(session.state == .idle)
        session.suggest(input: i)
        await session.pendingTask?.value
        #expect(session.state == .ready(first))
    }

    @Test func staleCompletionCannotReplaceNewerResult() async {
        let gate = DispatchSemaphore(value: 0)
        let calls = LockedCounter()
        let session = WatchSingleExerciseSuggestionSession { _, _ in
            if calls.next() == 1 { gate.wait(); return SuggestedWorkoutExercise(
                candidateID: "old", name: "old", mechanics: .compound, plannedSets: 3,
                repRange: 8...12, contributions: [], selectionScore: 1) }
            return SuggestedWorkoutExercise(
                candidateID: "new", name: "new", mechanics: .compound, plannedSets: 3,
                repRange: 8...12, contributions: [], selectionScore: 1)
        }
        let i = input()
        session.suggest(input: i)
        let first = session.pendingTask
        session.suggest(input: i)
        await session.pendingTask?.value
        #expect(session.state == .ready(exercise("new")))
        gate.signal()
        await first?.value
        #expect(session.state == .ready(exercise("new")))
    }

    @Test func cancelDiscardsLateCompletion() async {
        let gate = DispatchSemaphore(value: 0)
        let session = WatchSingleExerciseSuggestionSession { _, _ in gate.wait(); return nil }
        session.suggest(input: input())
        let task = session.pendingTask
        session.cancel()
        gate.signal()
        await task?.value
        #expect(session.state == .idle)
    }

    @Test func emptyAndFailedStatesAreDistinct() async {
        let empty = WatchSingleExerciseSuggestionSession { _, _ in nil }
        empty.suggest(input: input())
        await empty.pendingTask?.value
        #expect(empty.state == .empty)

        struct Boom: Error {}
        let failing = WatchSingleExerciseSuggestionSession { _, _ in throw Boom() }
        failing.suggest(input: input())
        await failing.pendingTask?.value
        if case .failed = failing.state {} else { Issue.record("expected failed") }

        let invalid = WatchSingleExerciseSuggestionSession()
        invalid.suggest(input: input(0))
        if case .failed = invalid.state {} else { Issue.record("expected failed for no catalog") }
    }

    @Test func exhaustingCandidatesYieldsEmpty() async {
        let i = input(1)
        let session = WatchSingleExerciseSuggestionSession()
        session.suggest(input: i)
        await session.pendingTask?.value
        session.suggestAnother(input: i)
        await session.pendingTask?.value
        #expect(session.state == .empty)
    }

    /// A slow/looping generator (large candidate pools on Watch hardware) must
    /// not leave the session stuck in `.calculating` ("Finding an exercise...")
    /// forever -- it should surface a terminal `.failed` state once the bounded
    /// timeout elapses. The timeout's wait is injected to resolve instantly
    /// instead of racing a real `Task.sleep` against the fake generator's real
    /// `Thread.sleep`: both draw on Swift Testing's shared cooperative thread
    /// pool, and with hundreds of suites running concurrently in the full CI
    /// suite, no fixed real-time margin between them is safe from that
    /// contention (confirmed: widening the margin from 6x to 20x still flaked).
    @Test func timesOutInsteadOfHangingForever() async {
        let session = WatchSingleExerciseSuggestionSession(generator: { _, _ in
            Thread.sleep(forTimeInterval: 0.2)
            return nil
        }, timeout: 0.05, timeoutSleep: { _ in })
        session.suggest(input: input())
        #expect(session.state == .calculating)
        await session.pendingTask?.value
        if case .failed = session.state {} else { Issue.record("expected a timeout failure, got \(session.state)") }
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
