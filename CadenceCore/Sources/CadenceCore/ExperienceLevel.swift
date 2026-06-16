import Foundation

/// The user's training experience, used to scale weekly volume landmarks
/// (MEV/MAV/MRV — see `VolumeLandmarks`). More-trained lifters tolerate and need
/// more volume to progress; beginners grow on less. Persisted as a raw string in
/// app settings.
public enum ExperienceLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case beginner
    case intermediate
    case advanced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .beginner:     return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced:     return "Advanced"
        }
    }

    public var summary: String {
        switch self {
        case .beginner:     return "New to lifting (under ~1 year)."
        case .intermediate: return "Training consistently for a year or more."
        case .advanced:     return "Years of consistent, structured training."
        }
    }

    /// Multiplier applied to the baseline (intermediate) volume landmarks.
    /// Beginners need/tolerate less weekly volume; advanced lifters more.
    var volumeScale: Double {
        switch self {
        case .beginner:     return 0.7
        case .intermediate: return 1.0
        case .advanced:     return 1.25
        }
    }
}
