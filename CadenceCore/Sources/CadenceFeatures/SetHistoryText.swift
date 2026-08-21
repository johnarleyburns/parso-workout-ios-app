import Foundation
import CadenceCore

/// The set editor's per-performer history captions (field test 2026-08-20 issue
/// 3, decision D8). The *formatting* lives here so it is unit-testable; the
/// SwiftData lookups that feed it stay in the view.
public enum SetHistoryText {

    /// "Last set 185 lb × 8 · RPE 7" for the most recent working set of the
    /// selected performer on this movement in the current session. `nil` when it
    /// is their first set of the movement (or none is logged yet) — never a
    /// fabricated default.
    public static func lastSetThisSession(_ set: SetEntry?,
                                          unit: MeasurementUnitPreference) -> String? {
        guard let set else { return nil }
        let effort = set.rpe.map { " · RPE \(Int($0.rounded()))" } ?? ""
        return "Last set \(Format.setLine(set, unit: unit))\(effort)"
    }
}
