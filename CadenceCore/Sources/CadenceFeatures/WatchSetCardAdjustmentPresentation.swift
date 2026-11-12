import Foundation
import CadenceCore

/// The value the inline Watch Set Card +/- row currently adjusts.
public enum WatchSetCardAdjustmentField: Equatable, Sendable {
    case weight(MeasurementUnitPreference)
    case reps

    /// Short, non-truncating center label between the +/- controls.
    public var inlineLabel: String {
        switch self {
        case .weight(.pounds): return "lbs"
        case .weight(.kilograms): return "kg"
        case .reps: return String(localized: "reps")
        }
    }
}
