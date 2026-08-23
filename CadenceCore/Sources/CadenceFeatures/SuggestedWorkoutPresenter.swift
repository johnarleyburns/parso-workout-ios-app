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
    public let subtitle: String
    public let isDisabled: Bool

    public var id: SuggestedWorkoutTier { option.tier }
}

public enum SuggestedWorkoutPresenter {
    public static let navigationTitle = "View Suggested Workout"
    public static let calculatingTitle = "Calculating suggested workouts…"
    public static let aboutAccessibilityLabel = "About suggested workouts"

    public static func choices(for bundle: SuggestedWorkoutBundle) -> [SuggestedWorkoutChoice] {
        bundle.options.map(choice(for:))
    }

    public static func choice(for option: SuggestedWorkoutOption) -> SuggestedWorkoutChoice {
        let title: String = switch option.tier {
        case .minimum: "Minimum Workout"
        case .medium: "Medium Workout"
        case .maximal: "Maximal Workout"
        }
        let gaps = remainingGapText(option)
        let trim = option.capTrimmingOccurred ? " Safety cap trimmed the final exercises." : ""
        if !option.isLaunchable {
            return SuggestedWorkoutChoice(
                option: option,
                title: title,
                subtitle: "No available exercises cover the remaining muscle-group gaps.",
                isDisabled: true)
        }
        return SuggestedWorkoutChoice(
            option: option,
            title: title,
            subtitle: "\(option.plannedSetTotal) planned sets · \(gaps)\(trim)",
            isDisabled: false)
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
        "Starts with completed direct and indirect sets for the current week.",
        "Represents each exercise across the canonical muscle catalog and calculates independent 4, 8, and 12-set deficits.",
        "Considers the largest remaining deficit first; equal deficits use a fixed largest-to-smallest muscle order.",
        "Scores unused exercises only for muscles still in deficit: direct sets receive whole credit, indirect sets receive half credit, and credit stops at the remaining gap. Equal scores for one muscle prefer compound movements, then movements involving more muscles.",
        "Adds the best-scoring unused exercise with your set preference, then trims from the end to the 20, 30, or 40-set safety cap.",
        "Produces a deterministic suggestion to review and edit, not a medical prescription or guarantee of an individualized optimum."
    ]

    public static let pseudocode = [
        "for tier in [4, 8, 12]: deficits = max(0, tier - completedSets)",
        "while a deficit remains: muscle = largest deficit; ties use descending muscle mass",
        "score each unused exercise = sum(min(remaining gap, planned sets × direct/indirect credit))",
        "on equal score for that muscle: compound > isolation; then more muscles involved",
        "add the winning exercise, subtract its capped credit, and repeat",
        "remove tail exercises above the 20 / 30 / 40-set cap; recompute remaining gaps"
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
