import Foundation
import CadenceCore

/// Cardio minutes earned by a finished watch workout, split by intensity from its heart-rate
/// samples (below moderate / moderate / vigorous). Nil without usable HR, since the split would
/// otherwise be a guess. The total counts toward the weekly cardio minutes.
public struct WatchCardioMinutesSummary: Equatable, Sendable {
    public let belowModerateMinutes: Double
    public let moderateMinutes: Double
    public let vigorousMinutes: Double
    public let totalMinutes: Double

    /// Minutes come solely from the shared phone classifier; unmeasured time stays unclassified
    /// (so `totalMinutes` is the classified time, never the full session).
    public static func make(
        hrSamples: [HRSamplePoint],
        sessionDuration: TimeInterval,
        profile: CardioIntensityProfile
    ) -> WatchCardioMinutesSummary? {
        guard hrSamples.count >= 2 else { return nil }
        return make(summary: CardioMinuteAccumulator.summarize(
            duration: sessionDuration, samples: hrSamples, profile: profile))
    }

    /// Splits an already-computed shared summary, so callers never summarize twice.
    public static func make(summary: CardioMinuteSummary?) -> WatchCardioMinutesSummary? {
        guard let summary else { return nil }
        guard summary.classifiedDuration > 0 else { return nil }
        return WatchCardioMinutesSummary(
            belowModerateMinutes: summary.belowModerateDuration / 60,
            moderateMinutes: summary.moderateDuration / 60,
            vigorousMinutes: summary.vigorousDuration / 60,
            totalMinutes: summary.classifiedDuration / 60)
    }
}
