import Foundation
import CadenceCore

/// Semantic heart-rate zone color, so the Apple-Watch-style palette can live
/// headlessly in CadenceFeatures while the `Color` mapping stays in the app
/// target (field-test batch 2026-08-20 issue 7). The palette is the Watch's:
/// Z1 cyan, Z2 green, Z3 yellow, Z4 orange, Z5 red; anything out of range is
/// neutral (secondary).
public enum HRZoneTint: Equatable, Sendable {
    case zone1, zone2, zone3, zone4, zone5, neutral

    public static func tint(for zone: Int) -> HRZoneTint {
        switch zone {
        case 1: .zone1
        case 2: .zone2
        case 3: .zone3
        case 4: .zone4
        case 5: .zone5
        default: .neutral
        }
    }
}

/// Pure copy for the shared `LiveHRBigView` readout (field-test batch 2026-08-20
/// issue 7): the zone line ("Z3 · Aerobic" plus an optional average suffix) and
/// the big BPM text. The view renders the zone part in the zone color and the
/// average suffix in secondary, so the pieces are exposed separately rather than
/// forcing the view to parse a combined string.
public enum LiveHRPresenter {

    /// "Z3 · Aerobic" — zone label + `CardioMath.zoneName`. The part rendered in
    /// the zone color.
    public static func zoneLine(zone: Int) -> String {
        "Z\(zone) · \(CardioMath.zoneName(zone))"
    }

    /// " · Avg 138 bpm", or "" when there is no average. The part rendered in
    /// secondary.
    public static func avgSuffix(avgHR: Double?) -> String {
        guard let avgHR else { return "" }
        return " · Avg \(Int(avgHR.rounded())) bpm"
    }

    /// "Z3 · Aerobic" or "Z3 · Aerobic · Avg 138 bpm" — the full subtitle.
    public static func subtitle(zone: Int, avgHR: Double?) -> String {
        zoneLine(zone: zone) + avgSuffix(avgHR: avgHR)
    }

    /// "143" or "—" for the big number.
    public static func bpmText(_ bpm: Double?) -> String {
        guard let bpm else { return "—" }
        return "\(Int(bpm.rounded()))"
    }
}
