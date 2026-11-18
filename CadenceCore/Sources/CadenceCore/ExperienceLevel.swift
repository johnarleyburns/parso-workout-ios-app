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
        case .beginner:     return {
            #if os(Linux)
            "Beginner"
            #else
            String(localized: "Beginner", bundle: .module)
            #endif
        }()
        case .intermediate: return {
            #if os(Linux)
            "Intermediate"
            #else
            String(localized: "Intermediate", bundle: .module)
            #endif
        }()
        case .advanced:     return {
            #if os(Linux)
            "Advanced"
            #else
            String(localized: "Advanced", bundle: .module)
            #endif
        }()
        }
    }

    public var summary: String {
        switch self {
        case .beginner:     return {
            #if os(Linux)
            "New to lifting (under ~1 year)."
            #else
            String(localized: "New to lifting (under ~1 year).", bundle: .module)
            #endif
        }()
        case .intermediate: return {
            #if os(Linux)
            "Training consistently for a year or more."
            #else
            String(localized: "Training consistently for a year or more.", bundle: .module)
            #endif
        }()
        case .advanced:     return {
            #if os(Linux)
            "Years of consistent, structured training."
            #else
            String(localized: "Years of consistent, structured training.", bundle: .module)
            #endif
        }()
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
