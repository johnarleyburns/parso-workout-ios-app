import CadenceFeatures
import Foundation

public enum WeightSuggestionCopy {
    public static func source(performerName: String?, exercise: String) -> String {
        let owner = performerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject: String
        if let owner, !owner.isEmpty {
            subject = "\(owner)'s"
        } else {
            subject = "your"
        }
        return {
            #if os(Linux)
            "Estimated from \(subject) previous \(exercise) sets · rounded to a loadable increment"
            #else
            String(localized: "Estimated from \(subject) previous \(exercise) sets · rounded to a loadable increment", bundle: FeatureLocalization.bundle)
            #endif
        }()
    }
}
