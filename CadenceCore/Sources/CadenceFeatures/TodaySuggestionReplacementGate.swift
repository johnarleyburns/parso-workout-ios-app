import Foundation
import CadenceCore

/// Whether a freshly computed Today suggestion should replace what's already
/// on screen immediately, or wait for the user to explicitly accept it.
public enum TodaySuggestionReplacement: Equatable, Sendable {
    case applyImmediately
    case holdPending
}

/// Decides between the two above. Nothing displayed yet always applies
/// immediately. A plan identical to what's displayed is a no-op and also
/// applies immediately. Only a genuinely different plan is held back — the
/// coach suggests, it does not proscribe (NFR-8).
public enum TodaySuggestionReplacementGate {
    public static func decide(displayed: TodaySuggestedPlanPayload?,
                              freshlyComputed: TodaySuggestedPlanPayload) -> TodaySuggestionReplacement {
        guard let displayed, displayed != freshlyComputed else { return .applyImmediately }
        return .holdPending
    }
}
