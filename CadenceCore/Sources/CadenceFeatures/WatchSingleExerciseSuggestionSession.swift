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
    /// The in-flight calculation; exposed so tests can await completion.
    private(set) var pendingTask: Task<Void, Never>?

    public init(generator: @escaping Generator = WatchSingleExerciseSuggestionSession.defaultGenerator) {
        self.generator = generator
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
        pendingTask = Task { [weak self] in
            let result: Result<SuggestedWorkoutExercise?, Error> = await Task.detached {
                Result { try generator(input, excluded) }
            }.value
            guard let self, token == self.generation else { return }
            switch result {
            case .success(let exercise?): self.state = .ready(exercise)
            case .success(nil): self.state = .empty
            case .failure(let error): self.state = .failed(error.localizedDescription)
            }
        }
    }
}
