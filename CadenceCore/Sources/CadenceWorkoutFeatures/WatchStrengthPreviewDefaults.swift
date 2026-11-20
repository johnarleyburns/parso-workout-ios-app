import CadenceFeatures
import Foundation
import CadenceCore

/// Defaults shown on the Watch Lift review screen. Field testing asked for the
/// review to state the values that will actually be used, not the vague
/// "Workout defaults": the last rep scheme, partners, and rest the athlete
/// chose, with explicit fallbacks on a fresh install.
public struct WatchStrengthPreviewDefaults: Equatable, Sendable {
    public static let repPatternKey = "watch.strength.preview.lastRepPattern"
    public static let partnersKey = "watch.strength.preview.lastPartners"
    public static let restSecondsKey = "watch.strength.preview.lastRestSeconds"
    public static let partnersChosenKey = "watch.strength.preview.partnersChosen"

    public static let fallbackReps = [8, 8, 8]
    public static let fallbackRestSeconds = 60

    public static func repPattern(stored: String) -> [Int] {
        let parsed = WatchCustomStrengthDefaults.parseRepPattern(stored).filter { $0 > 0 }
        return parsed.isEmpty ? fallbackReps : parsed
    }

    public static func repsText(_ reps: [Int]) -> String {
        let values = reps.isEmpty ? fallbackReps : reps
        return values.map(String.init).joined(separator: "-")
    }

    public static func restSeconds(stored: Int) -> Int {
        stored > 0 ? stored : fallbackRestSeconds
    }

    public static func restText(_ seconds: Int) -> String {
        let value = restSeconds(stored: seconds)
        if value % 60 == 0 { return "\(value / 60) min" }
        return "\(value) sec"
    }

    public static func partnerNames(stored: String,
                                    launchPartners: [String],
                                    previouslyChosen: Bool = false) -> [String] {
        if previouslyChosen { return WatchCustomStrengthDefaults.decodedPartners(from: stored) }
        let saved = WatchCustomStrengthDefaults.decodedPartners(from: stored)
        return saved.isEmpty ? WatchCustomStrengthDefaults.unique(launchPartners) : saved
    }

    public static func partnersText(_ names: [String]) -> String {
        let values = WatchCustomStrengthDefaults.unique(names)
        return values.isEmpty ? "No partner" : values.joined(separator: ", ")
    }
}
