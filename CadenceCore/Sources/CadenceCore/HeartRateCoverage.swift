import Foundation

/// Where a strength session's stored heart-rate series came from.
public enum HeartRateSource: String, Codable, Sendable {
    case watchHealthKit, watchBLE, phone, repairedHealthKit
}

/// Privacy-safe coverage metadata stored beside a session's HR samples.
/// Carries counts and offsets only — never HealthKit identifiers or raw values.
public struct HeartRateCoverage: Codable, Equatable, Sendable {
    public var source: HeartRateSource
    public var sampleCount: Int
    public var firstOffset: TimeInterval
    public var lastOffset: TimeInterval
    public var largestGap: TimeInterval
    public var recordedAt: Date

    public init(source: HeartRateSource, sampleCount: Int, firstOffset: TimeInterval,
                lastOffset: TimeInterval, largestGap: TimeInterval, recordedAt: Date) {
        self.source = source
        self.sampleCount = sampleCount
        self.firstOffset = firstOffset
        self.lastOffset = lastOffset
        self.largestGap = largestGap
        self.recordedAt = recordedAt
    }

    public static func measure(_ samples: [HRSamplePoint], source: HeartRateSource,
                               at date: Date = Date()) -> HeartRateCoverage {
        let sorted = samples.sorted { $0.t < $1.t }
        var gap = 0.0
        for (a, b) in zip(sorted, sorted.dropFirst()) { gap = max(gap, b.t - a.t) }
        return HeartRateCoverage(source: source, sampleCount: sorted.count,
                                 firstOffset: sorted.first?.t ?? 0, lastOffset: sorted.last?.t ?? 0,
                                 largestGap: gap, recordedAt: date)
    }
}

/// Honest description of how much of a session HR actually observed.
public enum HeartRateCoverageState: Equatable, Sendable {
    case none
    case complete
    case incomplete(unclassifiedFraction: Double)

    /// Unclassified share above which the summary must say coverage was incomplete.
    public static let incompleteThreshold = 0.25

    public static func evaluate(summary: CardioMinuteSummary?, sampleCount: Int) -> HeartRateCoverageState {
        guard sampleCount > 0, let summary, summary.actualDuration > 0 else { return .none }
        let fraction = summary.unclassifiedDuration / summary.actualDuration
        return fraction > incompleteThreshold ? .incomplete(unclassifiedFraction: fraction) : .complete
    }
}

/// Canonical validate / sort / dedupe / downsample used by Watch capture,
/// phone import and Apple Health repair.
public enum HRSampleNormalizer {
    public static let minimumBPM = 30.0
    public static let maximumBPM = 240.0
    /// Upper bound on a transported / stored series.
    public static let maximumStoredSamples = 1_500
    /// Slack past the session end tolerated before a sample is out of window.
    public static let windowTolerance: TimeInterval = 5

    /// Drops non-finite, impossible-BPM and out-of-window samples (when `duration` is known),
    /// sorts by time, keeps one sample per timestamp (the last), and downsamples
    /// deterministically to at most `maxCount`. Downsampling keeps the first and last sample
    /// and, per bucket, the min and max BPM, so extrema and coverage survive. It never
    /// inserts samples, so gaps are never bridged.
    public static func normalize(_ samples: [HRSamplePoint], duration: TimeInterval? = nil,
                                 maxCount: Int = maximumStoredSamples) -> [HRSamplePoint] {
        let limit: Double? = duration.flatMap { $0.isFinite ? $0 + windowTolerance : nil }
        var valid = samples.filter { s in
            s.t.isFinite && s.bpm.isFinite && s.bpm >= minimumBPM && s.bpm <= maximumBPM && s.t >= 0
                && (limit.map { s.t <= $0 } ?? true)
        }
        if let duration, duration.isFinite {
            valid = valid.map { HRSamplePoint(t: min($0.t, duration), bpm: $0.bpm) }
        }
        valid = valid.enumerated().sorted { a, b in
            a.element.t != b.element.t ? a.element.t < b.element.t : a.offset < b.offset
        }.map { $0.element }
        var deduped: [HRSamplePoint] = []
        for sample in valid {
            if let last = deduped.last, last.t == sample.t { deduped[deduped.count - 1] = sample }
            else { deduped.append(sample) }
        }
        return downsample(deduped, maxCount: maxCount)
    }

    static func downsample(_ sorted: [HRSamplePoint], maxCount: Int) -> [HRSamplePoint] {
        let limit = max(4, maxCount)
        guard sorted.count > limit, let first = sorted.first, let last = sorted.last else { return sorted }
        let buckets = (limit - 2) / 2
        let span = max(last.t - first.t, .leastNonzeroMagnitude)
        var groups = [[HRSamplePoint]](repeating: [], count: buckets)
        for sample in sorted.dropFirst().dropLast() {
            let index = min(buckets - 1, Int((sample.t - first.t) / span * Double(buckets)))
            groups[index].append(sample)
        }
        var out = [first]
        for group in groups where !group.isEmpty {
            let lo = group.min { $0.bpm < $1.bpm }!, hi = group.max { $0.bpm < $1.bpm }!
            out.append(contentsOf: lo.t <= hi.t ? (lo.t == hi.t ? [lo] : [lo, hi]) : [hi, lo])
        }
        out.append(last)
        return out
    }
}

/// The prior HR fields of a session, kept locally for one-step restore after a repair.
public struct HeartRateBackup: Codable, Equatable, Sendable {
    public var samples: [HRSamplePoint]
    public var summary: CardioMinuteSummary?
    public var coverage: HeartRateCoverage?
    public init(samples: [HRSamplePoint], summary: CardioMinuteSummary?, coverage: HeartRateCoverage?) {
        self.samples = samples; self.summary = summary; self.coverage = coverage
    }
}
