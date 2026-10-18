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

    public static func make(hrSamples: [HRSamplePoint], maxHR: Double) -> WatchCardioMinutesSummary? {
        guard hrSamples.count >= 2, let last = hrSamples.map(\.t).max(), last > 0 else { return nil }
        let session = CardioZoneAggregator.Session(
            modality: .other, intensity: .easy, durationMinutes: last / 60,
            hrSamples: hrSamples.map { .init(t: $0.t, bpm: $0.bpm) })
        let profile = CardioZoneAggregator.intensityProfile(for: session, maxHR: maxHR)
        guard profile.totalMinutes > 0 else { return nil }
        return WatchCardioMinutesSummary(belowModerateMinutes: profile.easyMinutes,
                                         moderateMinutes: profile.moderateMinutes,
                                         vigorousMinutes: profile.vigorousMinutes,
                                         totalMinutes: profile.totalMinutes)
    }
}
