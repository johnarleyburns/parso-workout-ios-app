import Foundation
import CadenceCore

/// Phase G (field-test-fixes): per-rep weight default cascade for inline editor.
public enum InlineEditorDefaults {

    /// Default weight for a set at the given target reps.
    /// Precedence: current-session exact rep → `WeightSuggestion` (history) →
    /// prescribed load → nil (editor shows empty).
    public static func defaultWeight(
        targetReps: Int,
        history: [SetSample],
        formula: OneRepMaxFormula = .epley,
        prescribedKg: Double = 0,
        isPrescribed: Bool = false
    ) -> WeightSuggestion.Result? {
        // 1. History-based suggestion (exact-rep match or inverse e1RM).
        if let suggestion = WeightSuggestion.suggest(targetReps: targetReps, history: history, formula: formula) {
            return suggestion
        }

        // 2. Prescribed load fallback.
        if isPrescribed && prescribedKg > 0 {
            return WeightSuggestion.Result(weightKg: prescribedKg, basis: .exactRepMatch)
        }

        return nil
    }
}
