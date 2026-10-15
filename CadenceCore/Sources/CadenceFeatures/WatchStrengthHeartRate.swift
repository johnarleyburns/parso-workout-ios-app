import Foundation
import CadenceCore

/// Property-list transport for Watch-recorded strength heart rate: flat
/// `[t0, bpm0, t1, bpm1, …]` doubles, safe for `transferUserInfo`.
public enum WatchStrengthHeartRate {
    public static let transportKey = "hr_samples"

    public static func encode(_ samples: [HRSamplePoint]) -> [Double] {
        samples.flatMap { [$0.t, $0.bpm] }
    }

    public static func decode(_ value: Any?) -> [HRSamplePoint] {
        guard let flat = value as? [Double] else { return [] }
        return stride(from: 0, to: flat.count - 1, by: 2).map {
            HRSamplePoint(t: flat[$0], bpm: flat[$0 + 1])
        }
    }
}
