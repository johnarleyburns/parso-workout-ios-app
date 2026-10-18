import Foundation
import CadenceCore

/// Durable, deduplicated Watch strength heart-rate capture. Fed by both
/// `HKLiveWorkoutBuilder` callbacks and polling/relay refreshes; relay
/// heartbeats and retries are transport events and must never call `record`.
///
/// Policy:
/// - A reading with a HealthKit sample end is deduplicated by that end time.
/// - A reading without one (BLE) is kept at most once per `bleMinimumInterval`
///   unless its BPM changed by `bleChangeThreshold` or more.
/// - Storage is bounded by `HRSampleNormalizer.maximumStoredSamples`; when
///   exceeded the series is deterministically downsampled (first/last and
///   per-bucket min/max kept).
/// - Only `reset()` (workout end/discard/new workout) clears it.
public struct WatchHeartRateSampleRecorder: Sendable {
    public static let bleMinimumInterval: TimeInterval = 5
    public static let bleChangeThreshold = 3.0

    public private(set) var samples: [HRSamplePoint] = []
    public private(set) var observedCount = 0
    public private(set) var duplicateCount = 0
    private var seenSampleEnds = Set<TimeInterval>()
    private var lastBLE: HRSamplePoint?
    private let maxStored: Int

    public init(maxStored: Int = HRSampleNormalizer.maximumStoredSamples) {
        self.maxStored = maxStored
    }

    /// Returns true when a new point was persisted.
    @discardableResult
    public mutating func record(bpm: Double, sampleEnd: Date?, now: Date, sessionStart: Date) -> Bool {
        observedCount += 1
        guard bpm.isFinite, bpm >= HRSampleNormalizer.minimumBPM, bpm <= HRSampleNormalizer.maximumBPM else { return false }
        let when = sampleEnd ?? now
        let t = max(0, when.timeIntervalSince(sessionStart))
        if let sampleEnd {
            let key = sampleEnd.timeIntervalSince1970
            guard seenSampleEnds.insert(key).inserted else { duplicateCount += 1; return false }
        } else if let last = lastBLE {
            let changed = abs(bpm - last.bpm) >= Self.bleChangeThreshold
            guard t - last.t >= Self.bleMinimumInterval || (changed && t - last.t >= 1) else {
                duplicateCount += 1
                return false
            }
        }
        let point = HRSamplePoint(t: t, bpm: bpm)
        if sampleEnd == nil { lastBLE = point }
        samples.append(point)
        if samples.count > maxStored {
            samples = HRSampleNormalizer.normalize(samples, maxCount: maxStored * 3 / 4)
        }
        return true
    }

    /// The series clamped to the completed session interval.
    public func finalSamples(duration: TimeInterval) -> [HRSamplePoint] {
        HRSampleNormalizer.normalize(samples, duration: max(0, duration), maxCount: maxStored)
    }

    public mutating func reset() { self = WatchHeartRateSampleRecorder(maxStored: maxStored) }
}
