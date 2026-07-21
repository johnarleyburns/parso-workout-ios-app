import Foundation

/// Pure functions — no I/O, fully unit-testable. Used by trends/PRs.
public enum WorkoutMath {

    // MARK: Estimated 1RM

    /// Epley estimated one-rep max. Returns the weight unchanged at 1 rep,
    /// and 0 for non-positive reps.
    static func epley1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    /// Brzycki estimated one-rep max. Undefined at 37+ reps (formula breaks
    /// down); clamps to a safe value there.
    static func brzycki1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        if reps == 1 { return weight }
        let denom = 1.0278 - 0.0278 * Double(reps)
        guard denom > 0 else { return weight * 2 } // degenerate; cap
        return weight / denom
    }

    /// Estimated 1RM using the chosen formula.
    public static func estimated1RM(weight: Double, reps: Int, formula: OneRepMaxFormula) -> Double {
        switch formula {
        case .epley: return epley1RM(weight: weight, reps: reps)
        case .brzycki: return brzycki1RM(weight: weight, reps: reps)
        }
    }

    // MARK: Volume

    /// Volume for a single set = weight × reps.
    public static func volume(weight: Double, reps: Int) -> Double {
        weight * Double(max(0, reps))
    }

    // MARK: Unit conversion

    private static let lbPerKg = 2.2046226218487757

    static func kgToLb(_ kg: Double) -> Double { kg * lbPerKg }
    public static func lbToKg(_ lb: Double) -> Double { lb / lbPerKg }

    /// Convert a canonical-kg weight into the user's display unit.
    public static func display(_ kg: Double, in unit: MeasurementUnitPreference) -> Double {
        switch unit {
        case .kilograms: return kg
        case .pounds: return kgToLb(kg)
        }
    }

    /// Convert a value entered in the user's display unit back to canonical kg.
    public static func canonical(_ value: Double, from unit: MeasurementUnitPreference) -> Double {
        switch unit {
        case .kilograms: return value
        case .pounds: return lbToKg(value)
        }
    }

    /// Total tonnage (volume load) rendered in the user's unit (issue 7): metric
    /// tonnes for kg, US (short) tons for pounds. `volumeKg` is Σ(weight×reps) in
    /// canonical kg. Returns e.g. "12.4 t" / "13.7 tn".
    public static func tonnageLabel(volumeKg: Double, unit: MeasurementUnitPreference) -> String {
        switch unit {
        case .kilograms:
            let tonnes = volumeKg / 1000
            return "\(SetTarget.trimmed((tonnes * 10).rounded() / 10)) t"
        case .pounds:
            let tons = kgToLb(volumeKg) / 2000
            return "\(SetTarget.trimmed((tons * 10).rounded() / 10)) tn"
        }
    }
}

/// Which formula to use for estimated 1RM (REQUIREMENTS §9 open question).
public enum OneRepMaxFormula: String, CaseIterable, Codable, Sendable, Identifiable {
    case epley, brzycki
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .epley: return "Epley"
        case .brzycki: return "Brzycki"
        }
    }
}

/// Global weight unit preference (REQUIREMENTS §9 open question).
public enum MeasurementUnitPreference: String, CaseIterable, Codable, Sendable, Identifiable {
    case kilograms, pounds
    public var id: String { rawValue }
    public var abbreviation: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }
    public var displayName: String {
        switch self {
        case .kilograms: return "Kilograms (kg)"
        case .pounds: return "Pounds (lb)"
        }
    }
}

/// Global distance unit preference for cardio (independent of weight).
public enum DistanceUnitPreference: String, CaseIterable, Codable, Sendable, Identifiable {
    case kilometers, miles
    public var id: String { rawValue }
    public var abbreviation: String {
        switch self {
        case .kilometers: return "km"
        case .miles: return "mi"
        }
    }
    public var displayName: String {
        switch self {
        case .kilometers: return "Kilometers (km)"
        case .miles: return "Miles (mi)"
        }
    }

    public static func unitDefault() -> DistanceUnitPreference {
        Locale.current.measurementSystem == .us ? .miles : .kilometers
    }
}

/// How a personal record is defined (FR-1.4, configurable).
public enum PRRule: String, CaseIterable, Codable, Sendable, Identifiable {
    case topWeight        // heaviest weight lifted
    case estimated1RM     // best estimated 1RM
    case topVolume        // best single-set volume (weight × reps)
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .topWeight: return "Heaviest weight"
        case .estimated1RM: return "Best estimated 1RM"
        case .topVolume: return "Best set volume"
        }
    }
}
