import CadenceFeatures
import CadenceCore

public enum CoachWarningModalityFilter {
    /// Surfaces warnings matching the requested modality plus `.general` ones, preserving order.
    public static func filter(_ warnings: [CoachWarning],
                              for modality: CoachWarning.Modality) -> [CoachWarning] {
        warnings.filter { $0.modality == modality || $0.modality == .general }
    }
}
