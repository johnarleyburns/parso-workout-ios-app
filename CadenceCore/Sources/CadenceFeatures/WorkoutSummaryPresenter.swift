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

    // MARK: Read-only exercise detail (field test 2026-08-18 #1)

    /// "180 lb x 12" — one logged set. A bodyweight set reads "BW x 12", a
    /// weighted bodyweight variant "BW + 10 lb x 12" (decision **D8**: the
    /// separator is a lowercase `x`, matching the user's wording).
    public static func setLine(_ set: WorkoutSummaryData.SetLine,
                               unit: MeasurementUnitPreference) -> String {
        "\(topLabel(topKg: set.weightKg, bodyweight: set.usesBodyweight, unit: unit)) x \(set.reps)"
    }

    /// "180 lb x 12, 190 lb x 10, 200 lb x 8" — one performer's whole exercise,
    /// in logged order.
    public static func performerSetsText(_ performer: WorkoutSummaryData.PerformerLine,
                                         unit: MeasurementUnitPreference) -> String {
        performer.sets.map { setLine($0, unit: unit) }.joined(separator: ", ")
    }

    /// Current-workout summary used by completed exercise cards and history
    /// rows: performer labels stay attached to the sets they actually logged.
    public static func doneSummary(_ line: WorkoutSummaryData.ExerciseLine,
                                   unit: MeasurementUnitPreference) -> String? {
        let performers = orderedPerformers(line)
        guard !performers.isEmpty else { return nil }
        return "Done: " + performers.map {
            "\($0.name): \(performerSetsText($0, unit: unit))"
        }.joined(separator: "; ")
    }

    /// The performers to render, "Me" first, then partners in the order the
    /// value type recorded them. Performers with no working sets are dropped.
    public static func orderedPerformers(_ line: WorkoutSummaryData.ExerciseLine)
        -> [WorkoutSummaryData.PerformerLine] {
        let present = line.performers.filter { !$0.sets.isEmpty }
        return present.filter(\.isMe) + present.filter { !$0.isMe }
    }

    /// VoiceOver value for an expanded exercise, e.g. "Me: 180 lb x 12,
    /// 190 lb x 10. Alex: 140 lb x 12."
    public static func expandedAccessibilityValue(_ line: WorkoutSummaryData.ExerciseLine,
                                                  unit: MeasurementUnitPreference) -> String {
        orderedPerformers(line)
            .map { "\($0.name): \(performerSetsText($0, unit: unit))" }
            .joined(separator: ". ")
    }
}
