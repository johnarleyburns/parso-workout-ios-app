import Foundation

/// Timing shared by watch workout cue playback and headless regression tests.
public enum WatchWorkoutCuePolicy {
    /// Three distinct bells when strength rest completes. The spacing is longer
    /// than the bundled warning bell so every strike is heard in full.
    public static let restCompletionBellOffsets: [TimeInterval] = [0, 0.85, 1.70]
}
