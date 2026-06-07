import Foundation

/// Dual lb/kg weight entry math (field-testing §04, decisions #4/#15). Storage
/// stays canonical kg; the UI lets the user type either unit and auto-fills the
/// other with the exact conversion (optionally plate-rounded). Pure & testable.
public enum UnitEntry {

    /// Canonical kilograms for a value typed in `unit`.
    public static func kilograms(_ value: Double, unit: MeasurementUnitPreference) -> Double {
        WorkoutMath.canonical(value, from: unit)
    }

    /// The exact equivalent value shown in the opposite field.
    public static func opposite(of value: Double,
                                unit: MeasurementUnitPreference) -> (unit: MeasurementUnitPreference, value: Double) {
        let kg = WorkoutMath.canonical(value, from: unit)
        let other: MeasurementUnitPreference = (unit == .kilograms) ? .pounds : .kilograms
        return (other, WorkoutMath.display(kg, in: other))
    }

    /// Rounds a kg weight to the nearest plate increment expressed in the
    /// display unit (default 2.5 — i.e. nearest 2.5 lb or 2.5 kg). Off by
    /// default in the UI (decision #15); storage keeps the exact entry unless
    /// the user opts in.
    public static func plateRounded(kg: Double,
                                    unit: MeasurementUnitPreference,
                                    increment: Double = 2.5) -> Double {
        guard increment > 0 else { return kg }
        let display = WorkoutMath.display(kg, in: unit)
        let rounded = (display / increment).rounded() * increment
        return WorkoutMath.canonical(rounded, from: unit)
    }
}
