import CadenceFeatures
import Foundation
import Observation
import CadenceCore

/// Session-only state machine behind Watch "Suggest an exercise". It calls the
/// shared `SuggestedWorkoutGenerator.suggestSingleExercise` (no Watch-local
/// ranking), never adds the result to a workout, and never touches persistent
/// "don't suggest" settings, UserDefaults or WatchConnectivity.
@MainActor @Observable
public final class WatchSingleExerciseSuggestionSession {
    public enum State: Equatable {
        case idle
        case calculating
        case ready(SuggestedWorkoutExercise)
        /// No eligible candidate exists for the input.
        case empty
        /// Transient calculation or context failure (retryable).
        case failed(String)
    }

    /// Runs off the main actor. Receives the input and the session-only exclusions.
    public typealias Generator = @Sendable (SuggestedWorkoutInput, Set<String>) throws -> SuggestedWorkoutExercise?

    public static let defaultGenerator: Generator = { input, excluded in
        SuggestedWorkoutGenerator.suggestSingleExercise(
            input: input, style: input.preferredStyle, excludingCandidateIDs: excluded)
    }

    public private(set) var state: State = .idle
    private var transientExcluded: Set<String> = []
    private var generation = 0
    private let generator: Generator
    /// Bounds how long a single generation can run before the session gives up
    /// and surfaces `.failed` instead of leaving the UI in `.calculating`
    /// ("Finding an exercise...") forever -- large candidate pools can be slow
    /// on Watch hardware.
    private let timeout: TimeInterval
    /// The real timeout wait, injectable only for tests. A test that wants a
    /// deterministic, CI-contention-proof race can supply an instantly-returning
    /// closure instead of relying on a real `Task.sleep` winning a real-time race
    /// against a fake generator's `Thread.sleep` -- both draw on the same shared
    /// cooperative thread pool, and no fixed margin between them is safe when
    /// hundreds of other suites are concurrently contending for that pool.
    private let timeoutSleep: @Sendable (TimeInterval) async -> Void
    /// The in-flight calculation; exposed so tests can await completion.
    private(set) var pendingTask: Task<Void, Never>?

    public init(generator: @escaping Generator = WatchSingleExerciseSuggestionSession.defaultGenerator,
                timeout: TimeInterval = 8,
                timeoutSleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
                    try? await Task.sleep(for: .seconds(seconds))
                }) {
        self.generator = generator
        self.timeout = timeout
        self.timeoutSleep = timeoutSleep
    }

    private struct SuggestionTimedOut: Error, LocalizedError {
        var errorDescription: String? { "Suggestion took too long" }
    }

    /// Races `operation` against a `timeout`-second deadline. The loser is
    /// cancelled; a synchronous, non-cooperatively-cancellable `generator` may
    /// keep running in the background briefly, but the caller moves on.
    private static func withTimeout<T: Sendable>(
        seconds: TimeInterval, sleep: @escaping @Sendable (TimeInterval) async -> Void,
        operation: @escaping @Sendable () async -> T
    ) async -> Result<T, Error> {
        await withTaskGroup(of: Result<T, Error>.self) { group in
            group.addTask { .success(await operation()) }
            group.addTask {
                await sleep(seconds)
                return .failure(SuggestionTimedOut())
            }
            let result = await group.next() ?? .failure(SuggestionTimedOut())
            group.cancelAll()
            return result
        }
    }

    /// Starts a fresh session: previous session-only exclusions are dropped.
    public func suggest(input: SuggestedWorkoutInput) {
        transientExcluded = []
        run(input)
    }

    /// Excludes only the currently shown candidate, then recalculates.
    public func suggestAnother(input: SuggestedWorkoutInput) {
        if case .ready(let shown) = state { transientExcluded.insert(shown.candidateID) }
        run(input)
    }

    /// Clears in-memory state and exclusions; persistent settings are untouched.
    public func cancel() {
        generation += 1
        pendingTask?.cancel()
        pendingTask = nil
        transientExcluded = []
        state = .idle
    }

    private func run(_ input: SuggestedWorkoutInput) {
        generation += 1
        let token = generation
        pendingTask?.cancel()
        guard !input.candidates.isEmpty else {
            pendingTask = nil
            state = .failed("Exercise catalog unavailable")
            return
        }
        state = .calculating
        let excluded = transientExcluded
        let generator = generator
        let timeout = timeout
        let timeoutSleep = timeoutSleep
        pendingTask = Task { [weak self] in
            let raced = await Self.withTimeout(seconds: timeout, sleep: timeoutSleep) {
                await Task.detached {
                    Result { try generator(input, excluded) }
                }.value
            }
            let result: Result<SuggestedWorkoutExercise?, Error>
            switch raced {
            case .success(let inner): result = inner
            case .failure(let timeoutError): result = .failure(timeoutError)
            }
            guard let self, token == self.generation else { return }
            switch result {
            case .success(let exercise?): self.state = .ready(exercise)
            case .success(nil): self.state = .empty
            case .failure(let error): self.state = .failed(error.localizedDescription)
            }
        }
    }
}
