import Foundation

/// The top-level workout types offered by the Start Workout picker
/// (field-testing §02, decision #9). Each routes to a purpose-built screen.
/// Distinct from `CardioType`/`ExerciseCategory`: this is the entry-point
/// taxonomy the user chooses from first.
public enum WorkoutType: String, CaseIterable, Codable, Sendable, Identifiable {
    case weights
    case run
    case walk
    case cycle
    case hiit
    case boxing
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .weights: return "Weights"
        case .run: return "Run"
        case .walk: return "Walk"
        case .cycle: return "Cycle"
        case .hiit: return "HIIT"
        case .boxing: return "Boxing"
        case .other: return "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .weights: return "dumbbell"
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .cycle: return "figure.outdoor.cycle"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .boxing: return "figure.boxing"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Outdoor types that record a GPS route (field-testing §05).
    public var usesGPS: Bool {
        switch self {
        case .run, .walk, .cycle: return true
        default: return false
        }
    }

    /// True for strength logging; false for the cardio/interval recorder.
    public var isStrength: Bool { self == .weights }

    /// Maps a cardio/interval `WorkoutType` to its `CardioType`. Returns nil for
    /// `.weights`, which is logged as a strength session, not cardio.
    public var cardioType: CardioType? {
        switch self {
        case .weights: return nil
        case .run: return .run
        case .walk: return .walk
        case .cycle: return .cycle
        case .hiit: return .hiit
        case .boxing: return .boxing
        case .other: return .other
        }
    }
}
