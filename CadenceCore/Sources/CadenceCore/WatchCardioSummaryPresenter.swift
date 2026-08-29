import Foundation

public struct WatchCardioSummaryPresentation: Equatable, Sendable {
    public let hrSamples: [HRSamplePoint]
    public let averageBPM: Double?
    public let maximumBPM: Double?

    public var showsHeartRate: Bool { !hrSamples.isEmpty }

    public init(hrSamples: [HRSamplePoint], maxPoints: Int = HRSampling.defaultMaxPoints) {
        let valid = hrSamples.filter { $0.t.isFinite && $0.t >= 0 && $0.bpm.isFinite && $0.bpm > 0 }
        self.hrSamples = HRSampling.downsample(valid, maxPoints: maxPoints)
        let values = valid.map(\.bpm)
        self.averageBPM = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        self.maximumBPM = values.max()
    }
}

public enum WatchCardioSummaryPresenter {
    public static func present(hrSamples: [HRSamplePoint], maxPoints: Int = HRSampling.defaultMaxPoints)
        -> WatchCardioSummaryPresentation {
        WatchCardioSummaryPresentation(hrSamples: hrSamples, maxPoints: maxPoints)
    }
}
