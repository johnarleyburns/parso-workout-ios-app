import Foundation

/// Pure presentation contract for the shared in-workout control dock: exactly
/// two equal actions (Pause/Resume and Finish), stacked at accessibility sizes.
public enum WorkoutDockLayout: Equatable, Sendable {
    case horizontal, vertical

    public static func resolve(isAccessibilitySize: Bool) -> WorkoutDockLayout {
        isAccessibilitySize ? .vertical : .horizontal
    }
}

public enum WorkoutDockPresenter {
    public static let minimumTargetHeight: Double = 56

    public struct PauseContent: Equatable, Sendable {
        public let title: String
        public let systemImage: String
    }

    public static func pauseContent(isPaused: Bool) -> PauseContent {
        isPaused ? PauseContent(title: "Resume", systemImage: "play.fill")
                 : PauseContent(title: "Pause", systemImage: "pause.fill")
    }

    public static let endSystemImage = "stop.fill"

    /// Persistent primary actions, in VoiceOver traversal order. Cool Down is
    /// never one of them; it lives only in the end-confirmation dialog.
    public static let primaryActionSuffixes = ["pause", "end"]

    public static func primaryActionIds(idPrefix: String) -> [String] {
        primaryActionSuffixes.map { "\(idPrefix).\($0)" }
    }

    public static func confirmationActionIds(hasCoolDown: Bool) -> [String] {
        (hasCoolDown ? ["workout.endCoolDown"] : []) + ["workout.endConfirm", "workout.endCancel"]
    }
}
