import CadenceFeatures
import Foundation

/// User-facing formatting for the weekly Cardio Minutes disclosure.
/// Keeping this seam outside SwiftUI makes the numeric contract testable.
public enum CardioMinutesDisplay {
    public static func logged(_ minutes: Double) -> String {
        String(localized: "\(rounded(minutes)) min", bundle: FeatureLocalization.bundle)
    }

    public static func moderateEquivalent(_ minutes: Double, target: Double) -> String {
        String(localized: "\(rounded(minutes)) of \(rounded(target)) min", bundle: FeatureLocalization.bundle)
    }

    public static func unclassified(_ minutes: Double) -> String {
        String(localized: "\(rounded(minutes)) min could not be intensity-classified", bundle: FeatureLocalization.bundle)
    }

    public static func zone(_ minutes: Double) -> String {
        String(localized: "\(rounded(minutes)) min", bundle: FeatureLocalization.bundle)
    }

    private static func rounded(_ minutes: Double) -> Int {
        Int(minutes.rounded())
    }
}
