import Foundation

/// User-facing formatting for the weekly Cardio Minutes disclosure.
/// Keeping this seam outside SwiftUI makes the numeric contract testable.
public enum CardioMinutesDisplay {
    public static func logged(_ minutes: Double) -> String {
        String(localized: "\(rounded(minutes)) min", bundle: .module)
    }

    public static func moderateEquivalent(_ minutes: Double, target: Double) -> String {
        String(localized: "\(rounded(minutes)) of \(rounded(target)) min", bundle: .module)
    }

    public static func unclassified(_ minutes: Double) -> String {
        String(localized: "\(rounded(minutes)) min could not be intensity-classified", bundle: .module)
    }

    public static func zone(_ minutes: Double) -> String {
        String(localized: "\(rounded(minutes)) min", bundle: .module)
    }

    private static func rounded(_ minutes: Double) -> Int {
        Int(minutes.rounded())
    }
}
