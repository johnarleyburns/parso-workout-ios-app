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
        return "Estimated from \(subject) previous \(exercise) sets · rounded to a loadable increment"
    }
}
