import Foundation
import CadenceCore

/// Property-list transport for Watch-recorded strength heart rate: flat
/// `[t0, bpm0, t1, bpm1, …]` doubles, safe for `transferUserInfo`.
public enum WatchStrengthHeartRate {
    public static let transportKey = "hr_samples"

    public static func encode(_ samples: [HRSamplePoint]) -> [Double] {
        samples.flatMap { [$0.t, $0.bpm] }
    }

    /// Hard cap on transported doubles (2 per sample) so a hostile or corrupt payload
    /// cannot balloon memory.
    public static let maximumTransportDoubles = HRSampleNormalizer.maximumStoredSamples * 4

    /// Defensive decode: odd-length, oversized, non-finite, impossible-BPM and
    /// out-of-window data yields `[]` or is dropped; the rest is sorted and normalized.
    /// `duration` (seconds) bounds the window when known.
    public static func decode(_ value: Any?, duration: TimeInterval? = nil) -> [HRSamplePoint] {
        guard let flat = value as? [Double], flat.count % 2 == 0,
              flat.count <= maximumTransportDoubles else { return [] }
        let raw = stride(from: 0, to: flat.count, by: 2).map { HRSamplePoint(t: flat[$0], bpm: flat[$0 + 1]) }
        return HRSampleNormalizer.normalize(raw, duration: duration)
    }
}
