import CadenceFeatures
import Foundation

/// User-facing formatting for the weekly Cardio Minutes disclosure.
/// Keeping this seam outside SwiftUI makes the numeric contract testable.
public enum CardioMinutesDisplay {
    public static func logged(_ minutes: Double) -> String {
        {
            #if os(Linux)
            "\(rounded(minutes)) min"
            #else
            String(localized: "\(rounded(minutes)) min", bundle: FeatureLocalization.bundle)
            #endif
        }()
    }

    public static func moderateEquivalent(_ minutes: Double, target: Double) -> String {
        {
            #if os(Linux)
            "\(rounded(minutes)) of \(rounded(target)) min"
            #else
            String(localized: "\(rounded(minutes)) of \(rounded(target)) min", bundle: FeatureLocalization.bundle)
            #endif
        }()
    }

    /// "63/300 min" -- the Home card's "Guideline credit" row.
    public static func guidelineCreditFraction(_ minutes: Double, target: Double) -> String {
        {
            #if os(Linux)
            "\(rounded(minutes))/\(rounded(target)) min"
            #else
            String(localized: "\(rounded(minutes))/\(rounded(target)) min", bundle: FeatureLocalization.bundle)
            #endif
        }()
    }

    public static func unclassified(_ minutes: Double) -> String {
        {
            #if os(Linux)
            "\(rounded(minutes)) min could not be intensity-classified"
            #else
            String(localized: "\(rounded(minutes)) min could not be intensity-classified", bundle: FeatureLocalization.bundle)
            #endif
        }()
    }

    /// Replaces `unclassified(_:)` wherever the caller also has the user's
    /// actual below-moderate attribution threshold (BPM) to show, so the
    /// unattributed-minutes line names the real number instead of speaking
    /// only in jargon. Falls back to `unclassified(_:)`'s wording when no
    /// threshold is known (e.g. no maximum HR on file at all).
    public static func unattributed(_ minutes: Double, thresholdBPM: Double?) -> String {
        guard let thresholdBPM else { return unclassified(minutes) }
        let bpm = Int(thresholdBPM.rounded())
        return {
            #if os(Linux)
            "\(rounded(minutes)) min unattributed — below minimum attribution HR of \(bpm)"
            #else
            String(localized: "\(rounded(minutes)) min unattributed — below minimum attribution HR of \(bpm)", bundle: FeatureLocalization.bundle)
            #endif
        }()
    }

    public static func zone(_ minutes: Double) -> String {
        {
            #if os(Linux)
            "\(rounded(minutes)) min"
            #else
            String(localized: "\(rounded(minutes)) min", bundle: FeatureLocalization.bundle)
            #endif
        }()
    }

    private static func rounded(_ minutes: Double) -> Int {
        Int(minutes.rounded())
    }
}
