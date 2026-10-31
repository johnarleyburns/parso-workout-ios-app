import Foundation
import Observation
import CadenceCore

/// Logic behind the Watch "Suggest exercise" shell. Reads the persisted phone
/// context (no phone reachability needed), assembles the active workout's
/// allocation and asks the session to calculate. Never adds an exercise.
@MainActor @Observable
public final class WatchSuggestedExerciseShell {
    public enum Phase: Equatable {
        case calculating
        /// No usable phone context, or a transient failure; retryable.
        case unavailable
        case noEligibleResult
        case ready(SuggestedWorkoutExercise)
    }

    public static let calculatingTitle = "Finding an exercise…"
    public static let unavailableMessage = "Suggestions are updating—sync with iPhone and try again"
    public static let noResultMessage = "No suitable exercise found for this workout"

    public let session: WatchSingleExerciseSuggestionSession
    private let loadContext: () -> WatchSingleExerciseSuggestionContext?
    private var contextMissing = false
    private var started = false

    public init(session: WatchSingleExerciseSuggestionSession = WatchSingleExerciseSuggestionSession(),
                loadContext: @escaping () -> WatchSingleExerciseSuggestionContext? = {
                    WatchSingleExerciseSuggestionContextStore().load()
                }) {
        self.session = session
        self.loadContext = loadContext
    }

    public var phase: Phase {
        if contextMissing { return .unavailable }
        switch session.state {
        case .idle, .calculating: return .calculating
        case .failed: return .unavailable
        case .empty: return .noEligibleResult
        case .ready(let exercise): return .ready(exercise)
        }
    }

    /// Starts once per presentation; Retry calls `retry`.
    public func start(activeNames: [String], activeWorkingSets: [WatchSuggestionSet]) {
        guard !started else { return }
        started = true
        calculate(activeNames: activeNames, activeWorkingSets: activeWorkingSets)
    }

    public func retry(activeNames: [String], activeWorkingSets: [WatchSuggestionSet]) {
        calculate(activeNames: activeNames, activeWorkingSets: activeWorkingSets)
    }

    /// Excludes the shown candidate and visibly returns to `.calculating`.
    public func suggestAnother(activeNames: [String], activeWorkingSets: [WatchSuggestionSet]) {
        guard let context = loadContext(),
              let input = WatchSingleExerciseSuggestionAssembler.make(
                context: context, activeExerciseNames: activeNames,
                activeWorkingSets: activeWorkingSets, transientExcludedCandidateIDs: []) else {
            contextMissing = true
            session.cancel()
            return
        }
        contextMissing = false
        session.suggestAnother(input: input)
    }

    public func cancel() {
        session.cancel()
        started = false
    }

    private func calculate(activeNames: [String], activeWorkingSets: [WatchSuggestionSet]) {
        guard let context = loadContext(),
              let input = WatchSingleExerciseSuggestionAssembler.make(
                context: context, activeExerciseNames: activeNames,
                activeWorkingSets: activeWorkingSets, transientExcludedCandidateIDs: []) else {
            contextMissing = true
            session.cancel()
            return
        }
        contextMissing = false
        session.suggest(input: input)
    }
}
