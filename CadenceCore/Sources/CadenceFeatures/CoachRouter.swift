import Foundation
import CadenceCore

/// Pure navigation decision for a coach recommendation (test-pyramid Phase 4).
///
/// The load-bearing rule — "every trainable coach recommendation lands on that
/// workout's setup/editor surface first, never directly into a live recorder"
/// (audio/coach routing plan §D) — was previously only asserted by nine flaky
/// simulator tests. It is now a one-line unit assertion over every `CoachSession`.
public enum CoachRoute: Equatable {
    /// Open the plan editor pre-filled from the coach's prescription.
    case planEditor(EditablePlan)
    /// A strength session with no exercises → open an empty editor titled from it.
    case emptyEditor(title: String)
    /// GPS cardio (walk/run/cycle) → its goal/setup surface, then recorder.
    case outdoorCardio(CardioType)
    /// Swim → the swim setup screen.
    case swim
    /// HIIT / boxing → the interval setup (protocol picker).
    case interval(WorkoutType)
    /// Non-GPS timer cardio (rowing/other) → its setup surface.
    case timerCardio(type: CardioType, suggestedMinutes: Int?)
    /// Recovery / rest / assessment → nothing launches from Home.
    case none
}

public enum CoachRouter {

    /// Resolves where a coach recommendation should route. Never returns a live
    /// recorder for a strength recommendation — always the editor.
    public static func destination(for session: CoachSession) -> CoachRoute {
        switch session.launchPayload {
        case .strengthPlan:
            if let plan = EditablePlan.from(coach: session) {
                return .planEditor(plan)
            }
            return .emptyEditor(title: session.title)
        case .cardio(let type, let durationMinutes):
            switch type {
            case "walk": return .outdoorCardio(.walk)
            case "run": return .outdoorCardio(.run)
            case "cycle": return .outdoorCardio(.cycle)
            case "swim": return .swim
            case "hiit": return .interval(.hiit)
            case "boxing": return .interval(.boxing)
            case "rowing": return .timerCardio(type: .rowing, suggestedMinutes: durationMinutes)
            default: return .timerCardio(type: .other, suggestedMinutes: durationMinutes)
            }
        case .recovery, .rest, .assessment:
            return .none
        }
    }

    /// Whether tapping an add-on suggestion launches it, or first warns the user.
    public enum AddOnAction: Equatable { case launch, warn }

    public static func addOnAction(status: CoachAddOnStatus) -> AddOnAction {
        switch status {
        case .encouraged, .neutral: return .launch
        case .warn: return .warn
        }
    }
}
