import Foundation
import CadenceCore

/// Pure presentation shared by every Watch cardio completion screen (steady, HIIT, boxing).
public struct WatchCardioCompletionSummaryPresentation: Equatable, Sendable {
    public let hrSamples: [HRSamplePoint]
    public let averageBPM: Double?
    public let maximumBPM: Double?
    public let minutes: WatchCardioMinutesSummary?
    public var showsHeartRateChart: Bool { !hrSamples.isEmpty }
}

public enum WatchCardioCompletionSummaryPresenter {
    /// Keeps the finalized series untouched; minutes come solely from the shared accumulator
    /// and are nil without measurements.
    public static func present(samples: [HRSamplePoint], duration: TimeInterval,
                               averageBPM: Double?, maximumBPM: Double?,
                               profile: CardioIntensityProfile) -> WatchCardioCompletionSummaryPresentation {
        let summary = WatchStrengthHRCoverage.summary(samples: samples, duration: duration, profile: profile)
        return WatchCardioCompletionSummaryPresentation(
            hrSamples: samples, averageBPM: averageBPM, maximumBPM: maximumBPM,
            minutes: WatchCardioMinutesSummary.make(summary: summary))
    }
}

/// Which completion surface a finished Watch cardio workout uses. Every kind shares one.
public enum WatchCardioCompletionWorkout: Equatable, Sendable { case steady, interval, boxing }

public enum WatchCardioCompletionRoute: Equatable, Sendable {
    case richSummary

    public static func forWorkout(_ workout: WatchCardioCompletionWorkout) -> WatchCardioCompletionRoute {
        .richSummary
    }
}
