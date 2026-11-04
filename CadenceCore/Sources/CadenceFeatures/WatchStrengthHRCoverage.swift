import Foundation
import CadenceCore

/// Watch strength-summary HR coverage. Uses the same shared presentation as the iPhone summary,
/// so the wording and classification are never duplicated in a view. Every number comes from one
/// `CardioMinuteAccumulator` summary, which is the only gap-credit policy.
public enum WatchStrengthHRCoverage {
    /// The single accumulator summary for these inputs (nil without samples or duration).
    public static func summary(samples: [HRSamplePoint], duration: TimeInterval,
                               profile: CardioIntensityProfile) -> CardioMinuteSummary? {
        samples.isEmpty || duration <= 0 ? nil
            : CardioMinuteAccumulator.summarize(duration: duration, samples: samples, profile: profile)
    }

    public static func presentation(samples: [HRSamplePoint], duration: TimeInterval,
                                    profile: CardioIntensityProfile,
                                    pending: Bool) -> HeartRateCoveragePresentation {
        presentation(summary: summary(samples: samples, duration: duration, profile: profile),
                     sampleCount: samples.count, pending: pending)
    }

    public static func presentation(summary: CardioMinuteSummary?, sampleCount: Int,
                                    pending: Bool) -> HeartRateCoveragePresentation {
        HeartRateCoveragePresentation.make(
            state: HeartRateCoverageState.evaluate(summary: summary, sampleCount: sampleCount),
            sampleCount: sampleCount, pending: pending)
    }

    /// Neutral note for meaningful unclassified time; nil when there is none worth showing.
    public static func unclassifiedNote(summary: CardioMinuteSummary?) -> String? {
        guard let summary, summary.unclassifiedDuration >= 60 else { return nil }
        let minutes = Int((summary.unclassifiedDuration / 60).rounded())
        return String(localized: "\(minutes) min unclassified — heart-rate measurements were missing.",
                      bundle: .module)
    }
}
