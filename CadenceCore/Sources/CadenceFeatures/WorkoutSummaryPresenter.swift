import Foundation
import CadenceCore

/// Pure formatting for the post-workout summary (test-pyramid Phase 1): the
/// heaviest-set label and the VoiceOver summary of an HR series. Moved out of
/// `WorkoutSummaryView`; the view keeps its SwiftUI/Charts/Map rendering.
public enum WorkoutSummaryPresenter {

    /// "100 kg" (the heaviest set), or for bodyweight: "BW" / "BW + 10 kg".
    public static func topLabel(topKg: Double, bodyweight: Bool,
                                unit: MeasurementUnitPreference) -> String {
        if bodyweight {
            return topKg > 0 ? "BW + \(Format.weight(topKg, unit: unit, decimals: 0))" : "BW"
        }
        return Format.weight(topKg, unit: unit, decimals: 0)
    }

    /// Spoken summary of an HR series for VoiceOver (the chart itself is opaque).
    public static func hrChartAXSummary(_ bpms: [Double]) -> String {
        let valid = bpms.filter { $0 > 0 }
        guard !valid.isEmpty else { return "No heart rate samples" }
        let lo = Int(valid.min() ?? 0)
        let hi = Int(valid.max() ?? 0)
        let avg = Int(valid.reduce(0, +) / Double(valid.count))
        return "Average \(avg), range \(lo) to \(hi) beats per minute, \(valid.count) samples"
    }
}
