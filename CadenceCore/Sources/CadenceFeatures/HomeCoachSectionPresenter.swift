import Foundation
import CadenceCore

/// Render order and visibility for Home's Coach's Suggestions card.
///
/// Field test 2026-08-18 #8/#9/#11: the suggested workout used to render *above*
/// the suggestion list behind a "Suggested Workout" blurb, and its CTA lived
/// inside the card. The order is now a tested fact rather than the order the
/// view happens to declare its children in.
public enum HomeCoachSectionPresenter {

    /// The card's blocks, in render order. The suggested workout is always last.
    public enum Block: Equatable {
        case heading
        case suggestion(HomeSuggestion)
        case showMore(expanded: Bool)
        case divider
        case suggestedWorkout(title: String, why: String, exercises: [ExercisePreview])
    }

    public struct ExercisePreview: Equatable, Sendable {
        public let name: String
        public let loadKg: Double?
        public let sets: Int?
        public let repsText: String?

        public init(name: String, loadKg: Double?, sets: Int?, repsText: String?) {
            self.name = name
            self.loadKg = loadKg
            self.sets = sets
            self.repsText = repsText
        }
    }

    /// Tone → a semantic colour role the view maps (no SwiftUI in this module).
    public enum ToneRole: Equatable, Sendable { case positive, warning, neutral }

    public static func toneRole(_ tone: HomeSuggestion.Tone) -> ToneRole {
        switch tone {
        case .positive: return .positive
        case .warning: return .warning
        case .neutral: return .neutral
        }
    }

    /// Copy shown under "Why this workout" when the session carries no subtitle.
    public static let fallbackWhy = "It matches today's recommended training load."

    /// Most exercises previewed on Home before the "+N more" affordance.
    public static let previewExerciseLimit = 6

    public static func blocks(suggestions: [HomeSuggestion],
                             recommendation: CoachSession?,
                             expanded: Bool) -> [Block] {
        var blocks: [Block] = [.heading]

        let visible = HomeDashboardPresenter.visibleSuggestions(suggestions, expanded: expanded)
        blocks.append(contentsOf: visible.map { Block.suggestion($0) })
        if suggestions.count > 1 {
            blocks.append(.showMore(expanded: expanded))
        }

        guard let session = launchableSession(recommendation) else { return blocks }
        if !suggestions.isEmpty {
            blocks.append(.divider)
        }
        blocks.append(.suggestedWorkout(
            title: session.title,
            why: session.subtitle.isEmpty ? fallbackWhy : session.subtitle,
            exercises: previewExercises(session)))
        return blocks
    }

    /// Whether the external "Do Coach's Workout" button renders.
    public static func showsPrimaryAction(recommendation: CoachSession?) -> Bool {
        launchableSession(recommendation) != nil
    }

    public static func previewExercises(_ session: CoachSession) -> [ExercisePreview] {
        guard let exercises = session.exercises else { return [] }
        return exercises.prefix(previewExerciseLimit).map { exercise in
            ExercisePreview(name: exercise.name,
                            loadKg: exercise.loadKg,
                            sets: exercise.sets,
                            repsText: repsText(exercise))
        }
    }

    public static func additionalExerciseCount(_ session: CoachSession) -> Int {
        max(0, (session.exercises?.count ?? 0) - previewExerciseLimit)
    }

    // MARK: - Rules

    /// Recovery, rest and assessment days have nothing to launch, so they get no
    /// workout block and no CTA (NFR-8: the advice still renders as suggestions).
    private static func launchableSession(_ recommendation: CoachSession?) -> CoachSession? {
        guard let recommendation else { return nil }
        switch recommendation.launchPayload {
        case .strengthPlan, .cardio: return recommendation
        case .recovery, .rest, .assessment: return nil
        }
    }

    private static func repsText(_ exercise: CoachSession.RecommendedExercise) -> String? {
        switch (exercise.repsLow, exercise.repsHigh) {
        case let (low?, high?) where high > low: return "\(low)–\(high)"
        case let (low?, _): return "\(low)"
        case let (nil, high?): return "\(high)"
        default: return nil
        }
    }
}
