import Foundation

/// The user's primary training goal (strength-pivot decision D4). Drives the
/// engine's intensity×goal insight (see `KnowledgeBase`) and, in later phases, the
/// prescriptive recommendations. Persisted as a raw string in app settings.
public enum TrainingGoal: String, CaseIterable, Codable, Sendable, Identifiable {
    case strength
    case hypertrophy
    case endurance

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strength:    return "Strength"
        case .hypertrophy: return "Hypertrophy"
        case .endurance:   return "Endurance"
        }
    }

    /// One-line description of what the goal trains for (used in pickers/onboarding).
    public var summary: String {
        switch self {
        case .strength:    return "Lift heavier — maximal force in low reps."
        case .hypertrophy: return "Build muscle — moderate reps near failure."
        case .endurance:   return "Last longer — higher reps, lighter loads."
        }
    }

    /// The working rep range the prescriptive engine programs to for this goal
    /// (P5). From the load/rep continuum (Schoenfeld et al. 2021): strength favours
    /// heavy low-rep work; hypertrophy a moderate range near failure; endurance
    /// higher reps (lower-confidence evidence — kept conservative).
    public var repRange: ClosedRange<Int> {
        switch self {
        case .strength:    return 3...5
        case .hypertrophy: return 6...12
        case .endurance:   return 15...20
        }
    }

    /// The default reps-in-reserve the engine prescribes — how close to failure to
    /// train. Hypertrophy is driven by proximity to failure, so it sits closest;
    /// strength leaves a little more in the tank to keep bar speed and technique.
    public var targetRIR: Int {
        switch self {
        case .strength:    return 2
        case .hypertrophy: return 1
        case .endurance:   return 2
        }
    }
}
