import XCTest
@testable import CadenceFeatures
import CadenceCore

@MainActor
final class WatchSingleExerciseSuggestionSessionTests: XCTestCase {
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

    func testInitialResultMatchesSharedGenerator() async {
        let i = input()
        let session = WatchSingleExerciseSuggestionSession()
        XCTAssertEqual(session.state, .idle)
        session.suggest(input: i)
        XCTAssertEqual(session.state, .calculating)
        await session.pendingTask?.value
        let direct = SuggestedWorkoutGenerator.suggestSingleExercise(input: i, style: i.preferredStyle)
        XCTAssertNotNil(direct)
        XCTAssertEqual(session.state, .ready(direct!))
    }

    func testSuggestAnotherNeverRepeatsAndLeavesInputUntouched() async {
        let i = input()
        let before = i
        let session = WatchSingleExerciseSuggestionSession()
        session.suggest(input: i)
        await session.pendingTask?.value
        var seen: [String] = []
        for _ in 0..<5 {
            guard case .ready(let shown) = session.state else { return XCTFail("not ready") }
            XCTAssertFalse(seen.contains(shown.candidateID))
            seen.append(shown.candidateID)
            session.suggestAnother(input: i)
            await session.pendingTask?.value
        }
        XCTAssertEqual(i, before)
    }

    func testCancelClearsExclusionsAndState() async {
        let i = input()
        let session = WatchSingleExerciseSuggestionSession()
        session.suggest(input: i)
        await session.pendingTask?.value
        guard case .ready(let first) = session.state else { return XCTFail() }
        session.suggestAnother(input: i)
        await session.pendingTask?.value
        session.cancel()
        XCTAssertEqual(session.state, .idle)
        session.suggest(input: i)
        await session.pendingTask?.value
        XCTAssertEqual(session.state, .ready(first))
    }

    func testStaleCompletionCannotReplaceNewerResult() async {
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
        XCTAssertEqual(session.state, .ready(exercise("new")))
        gate.signal()
        await first?.value
        XCTAssertEqual(session.state, .ready(exercise("new")))
    }

    func testCancelDiscardsLateCompletion() async {
        let gate = DispatchSemaphore(value: 0)
        let session = WatchSingleExerciseSuggestionSession { _, _ in gate.wait(); return nil }
        session.suggest(input: input())
        let task = session.pendingTask
        session.cancel()
        gate.signal()
        await task?.value
        XCTAssertEqual(session.state, .idle)
    }

    func testEmptyAndFailedStatesAreDistinct() async {
        let empty = WatchSingleExerciseSuggestionSession { _, _ in nil }
        empty.suggest(input: input())
        await empty.pendingTask?.value
        XCTAssertEqual(empty.state, .empty)

        struct Boom: Error {}
        let failing = WatchSingleExerciseSuggestionSession { _, _ in throw Boom() }
        failing.suggest(input: input())
        await failing.pendingTask?.value
        if case .failed = failing.state {} else { XCTFail("expected failed") }

        let invalid = WatchSingleExerciseSuggestionSession()
        invalid.suggest(input: input(0))
        if case .failed = invalid.state {} else { XCTFail("expected failed for no catalog") }
    }

    func testExhaustingCandidatesYieldsEmpty() async {
        let i = input(1)
        let session = WatchSingleExerciseSuggestionSession()
        session.suggest(input: i)
        await session.pendingTask?.value
        session.suggestAnother(input: i)
        await session.pendingTask?.value
        XCTAssertEqual(session.state, .empty)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
