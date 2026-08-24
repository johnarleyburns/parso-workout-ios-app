import Foundation
import CadenceCore

/// Prepared, SwiftUI-free state for the on-demand suggested-workout chooser.
public enum SuggestedWorkoutState: Equatable, Sendable {
    case idle
    case calculating
    case ready(SuggestedWorkoutBundle)
    case failed(message: String)
}

public struct SuggestedWorkoutChoice: Equatable, Sendable, Identifiable {
    public let option: SuggestedWorkoutOption
    public let title: String
    /// What kind of training this style is.
    public let styleDescription: String
    public let subtitle: String
    public let isDisabled: Bool

    public var id: SuggestedWorkoutStyle { option.style }
}

public enum SuggestedWorkoutPresenter {
    public static let navigationTitle = "View Suggested Workout"
    public static let calculatingTitle = "Calculating suggested workouts…"
    public static let aboutAccessibilityLabel = "About suggested workouts"
    public static let chooserIntro = "Every plan closes the same weekly gaps — pick the kind of training you want to do it with. You can review and edit any plan before starting."
    public static let choosingAPlan = "Every style aims at the same \(suggestedWorkoutTargetSetsPerGroup) weekly sets for each muscle group you track, under one \(suggestedWorkoutPlannedSetCap)-set safety cap, so a capped plan can still show remaining gaps. What changes between them is the movements. A style that cannot reach a muscle borrows a general strength movement rather than leaving the gap open, and the chooser says how many movements came from the style itself."

    public static func choices(for bundle: SuggestedWorkoutBundle) -> [SuggestedWorkoutChoice] {
        bundle.options.map(choice(for:))
    }

    public static func choice(for option: SuggestedWorkoutOption) -> SuggestedWorkoutChoice {
        let style = option.style
        let gaps = remainingGapText(option)
        let trim = option.capTrimmingOccurred ? " Safety cap trimmed the final exercises." : ""
        if !option.isLaunchable {
            return SuggestedWorkoutChoice(
                option: option,
                title: style.displayName,
                styleDescription: style.subtitle,
                subtitle: "No available \(style.displayName.lowercased()) exercises cover this week's gaps.",
                isDisabled: true)
        }
        return SuggestedWorkoutChoice(
            option: option,
            title: style.displayName,
            styleDescription: style.subtitle,
            subtitle: "\(option.plannedSetTotal) planned sets · \(styleShareText(option)) · \(gaps)\(trim)",
            isDisabled: false)
    }

    /// How much of the plan came from the chosen style rather than the general
    /// strength fallback. Disclosed, never hidden: a style narrows the movements
    /// but is not allowed to leave a gap unaddressed on purpose (NFR-8).
    public static func styleShareText(_ option: SuggestedWorkoutOption) -> String {
        let name = option.style.displayName.lowercased()
        let inStyle = option.inStyleExerciseCount
        let total = option.exercises.count
        guard total > 0 else { return "no movements" }
        return inStyle == total
            ? "all \(name) movements"
            : "\(inStyle) of \(total) \(name) movements"
    }

    public static func remainingGapText(_ option: SuggestedWorkoutOption) -> String {
        let gaps = option.unresolvedDeficits
        guard !gaps.isEmpty else { return "All current gaps covered" }
        let names = gaps.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map(displayName)
        return "Remaining gaps: \(names.joined(separator: ", "))"
    }

    public static func editablePlan(for option: SuggestedWorkoutOption,
                                    ladder: [Int]? = nil,
                                    unit: MeasurementUnitPreference,
                                    warmupMinutes: Int,
                                    cooldownMinutes: Int) -> EditablePlan {
        EditablePlan.from(plan: option.plan, ladder: ladder, unit: unit,
                          warmupMinutes: warmupMinutes, cooldownMinutes: cooldownMinutes)
    }

    /// Plain-language algorithm steps for the About sheet. Kept here so tests
    /// prevent the explanation and engine contract from drifting apart.
    public static let aboutSteps = [
        "Starts with this week's completed sets, credited from published movement analyses: a set counts once for a muscle the movement trains directly, half for one it trains indirectly, and not at all for one that only stabilises.",
        "Calculates a \(suggestedWorkoutTargetSetsPerGroup)-set weekly gap for every muscle group you track.",
        "Considers the largest remaining gap first; equal gaps use a fixed largest-to-smallest muscle order.",
        "Fills the plan from your chosen training style first — Olympic lifts for Olympic, carries and loads for Strongman, and so on — scoring each unused movement only for muscles still in deficit, with credit capped at the remaining gap. Equal scores for one muscle prefer compound movements, then movements involving more muscles.",
        "Falls back to general strength movements only where the style has nothing left that closes a gap, so a style narrows the movements without leaving a gap unaddressed on purpose.",
        "Adds each winning movement with your set preference, then trims from the end to a \(suggestedWorkoutPlannedSetCap)-set safety cap and recomputes what is still uncovered.",
        "Produces a deterministic suggestion to review and edit, not a medical prescription or guarantee of an individualized optimum."
    ]

    public static let pseudocode = [
        "deficits = max(0, \(suggestedWorkoutTargetSetsPerGroup) - completedSets) for each tracked muscle group",
        "while a deficit remains: muscle = largest deficit; ties use descending muscle mass",
        "score each unused movement = sum(min(remaining gap, planned sets × direct/indirect credit))",
        "on equal score for that muscle: in-style > out-of-style; compound > isolation; then more muscles involved",
        "pass 1 considers only movements of the chosen style; pass 2 considers every movement",
        "remove tail movements above the \(suggestedWorkoutPlannedSetCap)-set cap; recompute remaining gaps"
    ]

    public static var citationIDs: [String] { suggestedWorkoutCitationIDs }

    public static var citationsResolve: Bool {
        citationIDs.allSatisfy { CitationRegistry.citation(forId: $0) != nil }
    }

    /// UI-facing source content is deliberately citation-neutral. Views resolve
    /// the IDs through `CitationRegistry` and render the resulting `CitationLink`.
    public static var aboutContentContainsRawCitationID: Bool {
        let content = (aboutSteps + pseudocode).joined(separator: " ")
        return citationIDs.contains(where: content.contains)
    }

    private static func displayName(_ identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}
