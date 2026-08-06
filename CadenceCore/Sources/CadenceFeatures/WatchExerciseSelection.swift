import Foundation
import CadenceCore

public struct WatchExerciseSection: Equatable, Sendable, Identifiable {
    public var id: String { title }
    public var title: String
    public var exerciseNames: [String]
    public var otherBodyPart: BodyPart?

    public init(title: String, exerciseNames: [String], otherBodyPart: BodyPart? = nil) {
        self.title = title
        self.exerciseNames = exerciseNames
        self.otherBodyPart = otherBodyPart
    }
}

public enum WatchExerciseSelection {
    public static func defaultSections(exercises: [Exercise],
                                       recent: [Exercise],
                                       popularNames: [String] = ExerciseLibrary.popularNames,
                                       perBodyPartLimit: Int = 4) -> [WatchExerciseSection] {
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

        for part in BodyPart.allCases {
            let names = bodyPartHighlights(part: part,
                                           exercises: exercises,
                                           recent: recent,
                                           popularNames: popularNames,
                                           limit: perBodyPartLimit)
            sections.append(WatchExerciseSection(title: part.displayName,
                                                 exerciseNames: names,
                                                 otherBodyPart: part))
        }

        return sections
    }

    public static func fullList(for part: BodyPart, exercises: [Exercise]) -> [String] {
        exercises
            .filter { $0.bodyParts.contains(part) }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public static func search(_ query: String, exercises: [Exercise], limit: Int = 8) -> [Exercise] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return Array(ExerciseSearchIndex(exercises).rank(trimmed).prefix(max(0, limit)))
    }

    private static func bodyPartHighlights(part: BodyPart,
                                           exercises: [Exercise],
                                           recent: [Exercise],
                                           popularNames: [String],
                                           limit: Int) -> [String] {
        let popularSet = Set(popularNames.map { $0.lowercased() })
        let recentPart = recent
            .filter { $0.bodyParts.contains(part) }
            .map(\.name)
        let popularPart = exercises
            .filter { $0.bodyParts.contains(part) && popularSet.contains($0.name.lowercased()) }
            .map(\.name)
        let fallback = exercises
            .filter { $0.bodyParts.contains(part) }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return Array(unique(recentPart + popularPart + fallback).prefix(max(0, limit)))
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
