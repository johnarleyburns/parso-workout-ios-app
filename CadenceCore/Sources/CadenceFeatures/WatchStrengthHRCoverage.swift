import Foundation
import CadenceCore

/// Watch strength-summary HR coverage. Uses the same shared presentation as the iPhone summary,
/// so the wording and classification are never duplicated in a view.
public enum WatchStrengthHRCoverage {
    public static func presentation(samples: [HRSamplePoint], duration: TimeInterval,
                                    profile: CardioIntensityProfile,
                                    pending: Bool) -> HeartRateCoveragePresentation {
        let summary = samples.isEmpty || duration <= 0 ? nil
            : CardioMinuteAccumulator.summarize(duration: duration, samples: samples, profile: profile)
        return HeartRateCoveragePresentation.make(
            state: HeartRateCoverageState.evaluate(summary: summary, sampleCount: samples.count),
            sampleCount: samples.count, pending: pending)
    }
}
