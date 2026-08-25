import Foundation

/// Discovery helpers over the exercise catalog (feedback batch 8): a muscle-group
/// index for fast filtering, a curated "popular" shortlist so the picker can hide
/// the long tail behind a Browse/Search affordance, and gap-filling suggestions for
/// the Home muscle-group quick-start. P2 retired the external EXRX.NET link in favor
/// of an in-app detail (public-domain instructions + images now ship on-device).
public extension ExerciseLibrary {

    /// Muscle groups an exercise trains, by DB++ role.
    static func muscleGroups(of t: ExerciseTemplate) -> Set<MuscleGroup> {
        t.trainedMuscleGroups
    }

    /// Index: muscle group → the built-in exercises that train it, compound-first
    /// (compounds are the efficient choice for covering a gap), then by name.
    static let byMuscleGroup: [MuscleGroup: [ExerciseTemplate]] = {
        var index: [MuscleGroup: [ExerciseTemplate]] = [:]
        for t in starter {
            for group in muscleGroups(of: t) { index[group, default: []].append(t) }
        }
        for (group, list) in index {
            index[group] = list.sorted {
                if ($0.mechanics == .compound) != ($1.mechanics == .compound) {
                    return $0.mechanics == .compound
                }
                return $0.name < $1.name
            }
        }
        return index
    }()

    /// A curated shortlist of widely-known movements shown first in the picker, so
    /// the full catalog stays one tap ("Browse all") / a search away. Every name
    /// resolves to a built-in template.
    static let popularNames: [String] = [
        "Bench Press", "Back Squat", "Deadlift", "Overhead Press", "Pull-Up",
        "Barbell Row", "Romanian Deadlift", "Dumbbell Bench Press", "Lat Pulldown",
        "Dumbbell Curl", "Triceps Pushdown", "Leg Press", "Hip Thrust", "Plank",
        "Push-Up", "Dumbbell Lateral Raise", "Bulgarian Split Squat",
        "Seated Cable Row", "Leg Extension", "Lying Leg Curl",
    ]

    static let popular: [ExerciseTemplate] = popularNames.compactMap { byName[$0.lowercased()] }

    /// Greedy set-cover: pick exercises (compounds first) that together cover as many
    /// of the `missing` muscle groups as possible, fewest movements first. Used by the
    /// quick-start as a fallback / supplement to reusing a past workout.
    static func suggestions(forMissing missing: [MuscleGroup], limit: Int = 6) -> [ExerciseTemplate] {
        guard !missing.isEmpty else { return [] }
        var remaining = Set(missing)
        var chosen: [ExerciseTemplate] = []
        // Candidate pool: compounds first (cover more per movement), then isolations.
        let pool = starter.sorted {
            ($0.mechanics == .compound ? 0 : 1, $0.name) < ($1.mechanics == .compound ? 0 : 1, $1.name)
        }
        while !remaining.isEmpty && chosen.count < limit {
            // Pick the movement covering the most still-missing groups.
            let best = pool
                .filter { !chosen.contains($0) }
                .max { a, b in
                    muscleGroups(of: a).intersection(remaining).count
                        < muscleGroups(of: b).intersection(remaining).count
                }
            guard let best, !muscleGroups(of: best).intersection(remaining).isEmpty else { break }
            chosen.append(best)
            remaining.subtract(muscleGroups(of: best))
        }
        return chosen
    }
}

public extension Exercise {
    /// The muscle groups this (possibly custom) exercise trains — the picker's and
    /// facet index's classification dimension. Reads the DB++ roles that already
    /// back `volumeCredits`, so the picker and the volume ledger cannot disagree;
    /// a movement that credits no volume still classifies by its muscle lists so
    /// it stays findable under a group.
    var trainedMuscleGroups: Set<MuscleGroup> {
        let credited = Set(volumeCredits.keys)
        if !credited.isEmpty { return credited }
        return Set(MuscleGroup.canonicalize(primaryMuscles + secondaryMuscles))
    }

    /// The de-duplicated facet chips shown in the exercise detail (level, equipment,
    /// mechanics, force, category). `force` and `category` both read "Push"/"Pull"
    /// for pressing/pulling movements, so identical labels are collapsed (fixes the
    /// duplicated "Push" pill). Order is preserved.
    var displayFacetTags: [String] {
        ExerciseFacetTagBuilder.tags(level: level, equipment: equipmentValue,
                                     mechanics: mechanicsValue, force: forceValue,
                                     category: categoryValue)
    }
}

/// Pure builder for the exercise-detail facet chips, kept out of the `@Model` so it
/// is headlessly `swift test`-verifiable. Collapses labels that repeat (force and
/// category both say "Push" for pressing movements).
public enum ExerciseFacetTagBuilder {
    public static func tags(level: String?, equipment: Equipment?, mechanics: Mechanics?,
                            force: Force?, category: ExerciseCategory?) -> [String] {
        var tags: [String] = []
        if let level { tags.append(level.capitalized) }
        if let equipment { tags.append(equipment.displayName) }
        if let mechanics { tags.append(mechanics == .compound ? "Compound" : "Isolation") }
        if let force { tags.append(force.rawValue.capitalized) }
        if let category { tags.append(category.displayName) }
        var seen = Set<String>()
        return tags.filter { seen.insert($0.lowercased()).inserted }
    }
}

public extension ExerciseTemplate {
    /// The muscle groups this catalog movement trains. Same rule as `Exercise`:
    /// DB++ roles first, muscle lists as the fallback for non-eligible movements.
    var trainedMuscleGroups: Set<MuscleGroup> {
        let credited = Set(volumeCredits.keys)
        if !credited.isEmpty { return credited }
        return Set(MuscleGroup.canonicalize(primaryMuscles + secondaryMuscles))
    }
}
