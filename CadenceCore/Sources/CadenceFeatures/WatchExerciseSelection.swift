import Foundation
import CadenceCore

public struct WatchExerciseSection: Equatable, Sendable, Identifiable {
    public var id: String { title }
    public var title: String
    public var exerciseNames: [String]
    /// The muscle group this section browses, when tapping "Show all" should open
    /// the group's full list. `nil` for the curated Recent/Popular sections.
    public var otherMuscleGroup: MuscleGroup?

    public init(title: String, exerciseNames: [String], otherMuscleGroup: MuscleGroup? = nil) {
        self.title = title
        self.exerciseNames = exerciseNames
        self.otherMuscleGroup = otherMuscleGroup
    }
}

public enum WatchExerciseSelection {
    public static func defaultSections(exercises: [Exercise],
                                       recent: [Exercise],
                                       popularNames: [String] = ExerciseLibrary.popularNames,
                                       perGroupLimit: Int = 4,
                                       groups: [MuscleGroup] = MuscleGroup.canonicalOrder
                                           .filter(\.isTrackedByDefault)) -> [WatchExerciseSection] {
        let allByName = Dictionary(exercises.map { ($0.name.lowercased(), $0) },
                                   uniquingKeysWith: { first, _ in first })
        var sections: [WatchExerciseSection] = []

        let recentNames = unique(recent.map(\.name))
        if !recentNames.isEmpty {
            sections.append(WatchExerciseSection(title: "My Last Exercises",
                                                 exerciseNames: Array(recentNames.prefix(8))))
        }

        let popular = popularNames.compactMap { allByName[$0.lowercased()]?.name }
        if !popular.isEmpty {
            sections.append(WatchExerciseSection(title: "Popular Exercises",
                                                 exerciseNames: Array(unique(popular).prefix(10))))
        }

        // Only the coach's tracked groups get a wrist section: a group the catalog
        // cannot fill (decision D4) would be an empty row on a 45mm screen. Search
        // still reaches every movement.
        for group in groups {
            let names = groupHighlights(group: group,
                                        exercises: exercises,
                                        recent: recent,
                                        popularNames: popularNames,
                                        limit: perGroupLimit)
            sections.append(WatchExerciseSection(title: group.displayName,
                                                 exerciseNames: names,
                                                 otherMuscleGroup: group))
        }

        return sections
    }

    public static func fullList(for group: MuscleGroup, exercises: [Exercise]) -> [String] {
        exercises
            .filter { $0.trainedMuscleGroups.contains(group) }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public static func search(_ query: String, exercises: [Exercise], limit: Int = 8) -> [Exercise] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return Array(ExerciseSearchIndex(exercises).rank(trimmed).prefix(max(0, limit)))
    }

    private static func groupHighlights(group: MuscleGroup,
                                        exercises: [Exercise],
                                        recent: [Exercise],
                                        popularNames: [String],
                                        limit: Int) -> [String] {
        let popularSet = Set(popularNames.map { $0.lowercased() })
        let recentGroup = recent
            .filter { $0.trainedMuscleGroups.contains(group) }
            .map(\.name)
        let popularGroup = exercises
            .filter { $0.trainedMuscleGroups.contains(group) && popularSet.contains($0.name.lowercased()) }
            .map(\.name)
        let fallback = exercises
            .filter { $0.trainedMuscleGroups.contains(group) }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return Array(unique(recentGroup + popularGroup + fallback).prefix(max(0, limit)))
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            guard seen.insert(name.lowercased()).inserted else { continue }
            out.append(name)
        }
        return out
    }
}
