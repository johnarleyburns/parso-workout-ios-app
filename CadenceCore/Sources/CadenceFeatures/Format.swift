import Foundation
import CadenceCore

/// Shared display formatting. Weights are stored canonical-kg; these helpers
/// convert to the user's unit for display and parse entry back to kg.
///
/// Moved verbatim out of the app's `Shared/Formatting.swift` (test-pyramid Phase 1)
/// so it is headlessly testable under `swift test`. It never needed SwiftUI — the
/// original file `import SwiftUI`'d without using it.
public enum Format {

    public static func weight(_ kg: Double, unit: MeasurementUnitPreference, decimals: Int = 1) -> String {
        let value = WorkoutMath.display(kg, in: unit)
        let n = NSNumber(value: value)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = decimals
        return (f.string(from: n) ?? "\(value)") + " " + unit.abbreviation
    }

    public static func weightValue(_ kg: Double, unit: MeasurementUnitPreference, decimals: Int = 1) -> String {
        let value = WorkoutMath.display(kg, in: unit)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = decimals
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Compact previous-set reference, e.g. "60×8".
    public static func previousShort(_ kg: Double, reps: Int, unit: MeasurementUnitPreference) -> String {
        "\(weightValue(kg, unit: unit))×\(reps)"
    }

    public static func setLine(_ set: SetEntry, unit: MeasurementUnitPreference) -> String {
        if set.usesBodyweight {
            let added = set.weight > 0 ? " + \(weightValue(set.weight, unit: unit)) \(unit.abbreviation)" : ""
            return "BW\(added) × \(set.reps)"
        }
        return "\(weightValue(set.weight, unit: unit)) \(unit.abbreviation) × \(set.reps)"
    }

    public static func setLineDual(_ set: SetEntry, preferredUnit: MeasurementUnitPreference) -> String {
        let alt: MeasurementUnitPreference = preferredUnit == .kilograms ? .pounds : .kilograms
        if set.usesBodyweight {
            if set.weight > 0 {
                return "BW + \(weightValue(set.weight, unit: preferredUnit)) \(preferredUnit.abbreviation) (\(weightValue(set.weight, unit: alt)) \(alt.abbreviation)) × \(set.reps)"
            }
            return "BW × \(set.reps)"
        }
        return "\(weightValue(set.weight, unit: preferredUnit)) \(preferredUnit.abbreviation) (\(weightValue(set.weight, unit: alt)) \(alt.abbreviation)) × \(set.reps)"
    }

    public static func distance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    public static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, sec) }
        return String(format: "%d:%02d", m, sec)
    }

    public static func clock(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    public static func sets(_ value: Double) -> String {
        let whole = value.rounded(.toNearestOrEven)
        if abs(value - whole) < 0.001 {
            return "\(Int(whole))"
        }
        return String(format: "%.1f", value)
    }

    public static func integer(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    public static func heartRate(_ bpm: Double?) -> String {
        guard let bpm else { return "—" }
        return "\(Int(bpm.rounded())) bpm"
    }

    /// A prescription line for a `PlanItem` (round4b §B-1).
    /// Reps/distance + the Rx load. Per decision #2 the canonical lb is always
    /// shown, with the user's preferred unit appended only when it differs.
    public static func prescription(_ item: PlanItem, ladder: [Int]?, unit: MeasurementUnitPreference,
                                    assessedE1RM: Double? = nil) -> String {
        var parts: [String] = []
        if let ladder, !ladder.isEmpty {
            parts.append(ladder.map(String.init).joined(separator: "-") + " reps")
        } else if let reps = item.reps {
            parts.append("\(reps) reps")
        }
        if let d = item.distanceM { parts.append(distance(d)) }
        var line = parts.joined(separator: " · ")
        if let pct = item.loadPercentage {
            let pctStr = "\(Int(pct * 100))%"
            if let e1rm = assessedE1RM {
                let loadKg = (e1rm * pct * 10).rounded() / 10
                let loadStr = weight(loadKg, unit: unit)
                line += line.isEmpty ? "\(pctStr) (\(loadStr))" : " @ \(pctStr) (\(loadStr))"
            } else {
                line += line.isEmpty ? pctStr : " @ \(pctStr)"
            }
        } else if let load = rxLoad(male: item.loadLb, female: item.loadLbFemale, unit: unit) {
            line += line.isEmpty ? load : " @ \(load)"
        }
        if let note = item.note { line += " (\(note))" }
        return line
    }

    /// "95/65 lb" (pref lb) or "95/65 lb (43/29 kg)" (pref kg). nil when no load.
    public static func rxLoad(male: Double?, female: Double?, unit: MeasurementUnitPreference) -> String? {
        guard let male else { return nil }
        func lbStr(_ lb: Double) -> String { Format.integer(Int(lb.rounded())) }
        let lbPart: String
        if let female, female != male {
            lbPart = "\(lbStr(male))/\(lbStr(female)) lb"
        } else {
            lbPart = "\(lbStr(male)) lb"
        }
        guard unit == .kilograms else { return lbPart }
        func kgStr(_ lb: Double) -> String { Format.integer(Int(WorkoutMath.lbToKg(lb).rounded())) }
        let kgPart: String
        if let female, female != male {
            kgPart = "\(kgStr(male))/\(kgStr(female)) kg"
        } else {
            kgPart = "\(kgStr(male)) kg"
        }
        return "\(lbPart) (\(kgPart))"
    }
}
