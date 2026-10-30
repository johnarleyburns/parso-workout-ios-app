import Foundation
import CadenceCore

/// Pure parsing + range validation for the Watch Set Card's native text entry (weight / reps).
/// Numeric input is interpreted in the current display unit; nothing is ever clamped.
public enum WatchSetEntryParser {
    public enum Entry: Equatable, Sendable {
        case weight(Double) // display-unit value
        case reps(Int)
    }

    public enum Failure: Error, Equatable, Sendable {
        case empty
        case notANumber
        case wrongUnit
        case outOfRange
        case fractionalReps
    }

    private static let poundSuffixes = ["pounds", "pound", "lbs", "lb"]
    private static let kilogramSuffixes = ["kilograms", "kilogram", "kgs", "kg"]

    public static func weight(
        _ raw: String,
        unit: MeasurementUnitPreference,
        range: ClosedRange<Double>,
        locale: Locale = .current
    ) -> Result<Double, Failure> {
        var text = normalized(raw)
        guard !text.isEmpty else { return .failure(.empty) }
        let (matching, other) = unit == .pounds ? (poundSuffixes, kilogramSuffixes) : (kilogramSuffixes, poundSuffixes)
        if other.contains(where: { text.hasSuffix($0) }) { return .failure(.wrongUnit) }
        if let suffix = matching.first(where: { text.hasSuffix($0) }) {
            text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard let value = number(text, locale: locale) else {
            return .failure(text.isEmpty ? .empty : .notANumber)
        }
        guard range.contains(value) else { return .failure(.outOfRange) }
        return .success(value)
    }

    public static func reps(_ raw: String, range: ClosedRange<Int> = 1...100, locale: Locale = .current)
        -> Result<Int, Failure> {
        let text = normalized(raw)
        guard !text.isEmpty else { return .failure(.empty) }
        guard let value = number(text, locale: locale) else { return .failure(.notANumber) }
        guard value == value.rounded() else { return .failure(.fractionalReps) }
        guard value >= Double(range.lowerBound), value <= Double(range.upperBound) else {
            return .failure(.outOfRange)
        }
        return .success(Int(value))
    }

    // MARK: Copy

    public static func weightMessage(for failure: Failure, unit: MeasurementUnitPreference,
                                     range: ClosedRange<Double>) -> String {
        switch failure {
        case .wrongUnit:
            return String(localized: "Use \(unit.abbreviation) for this workout.", bundle: .module)
        case .empty, .notANumber, .outOfRange, .fractionalReps:
            let lower = Int(range.lowerBound), upper = Int(range.upperBound)
            return String(localized: "Say or enter a weight from \(lower) to \(upper) \(unit.abbreviation).", bundle: .module)
        }
    }

    public static func repsMessage(for failure: Failure, range: ClosedRange<Int> = 1...100) -> String {
        String(localized: "Reps must be a whole number from \(range.lowerBound) to \(range.upperBound).", bundle: .module)
    }

    // MARK: Helpers

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// Parses a plain decimal in the locale's format, falling back to the POSIX form ("12.5").
    private static func number(_ text: String, locale: Locale) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," || $0 == "-" || $0 == "+" }) else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        if let parsed = formatter.number(from: trimmed)?.doubleValue, parsed.isFinite { return parsed }
        if let parsed = Double(trimmed), parsed.isFinite { return parsed }
        return nil
    }
}
