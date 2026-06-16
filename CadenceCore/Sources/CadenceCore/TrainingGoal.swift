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
}
