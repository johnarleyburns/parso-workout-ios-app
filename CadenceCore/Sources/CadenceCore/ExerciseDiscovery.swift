import Foundation

/// Discovery helpers over the exercise catalog (feedback batch 8): a body-part
/// index for fast filtering, a curated "popular" shortlist so the picker can hide
/// the long tail behind a Browse/Search affordance, gap-filling suggestions for the
/// Home "body parts" quick-start, and an external EXRX.NET reference link (opened in
/// the system browser to respect EXRX's copyright — we never copy their content).
public extension ExerciseLibrary {

    /// Body parts an exercise trains, from its primary+secondary muscle ids.
    static func bodyParts(of t: ExerciseTemplate) -> Set<BodyPart> {
        BodyPart.parts(forMuscleIDs: t.muscleGroups)
    }

    /// Index: body part → the built-in exercises that train it, compound-first
    /// (compounds are the efficient choice for covering a gap), then by name.
    static let byBodyPart: [BodyPart: [ExerciseTemplate]] = {
        var index: [BodyPart: [ExerciseTemplate]] = [:]
        for t in starter {
            for part in bodyParts(of: t) { index[part, default: []].append(t) }
        }
        for (part, list) in index {
            index[part] = list.sorted {
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
    /// of the `missing` body parts as possible, fewest movements first. Used by the
    /// body-parts quick-start as a fallback / supplement to reusing a past workout.
    static func suggestions(forMissing missing: [BodyPart], limit: Int = 6) -> [ExerciseTemplate] {
        guard !missing.isEmpty else { return [] }
        var remaining = Set(missing)
        var chosen: [ExerciseTemplate] = []
        // Candidate pool: compounds first (cover more per movement), then isolations.
        let pool = starter.sorted {
            ($0.mechanics == .compound ? 0 : 1, $0.name) < ($1.mechanics == .compound ? 0 : 1, $1.name)
        }
        while !remaining.isEmpty && chosen.count < limit {
            // Pick the movement covering the most still-missing parts.
            let best = pool
                .filter { !chosen.contains($0) }
                .max { a, b in
                    bodyParts(of: a).intersection(remaining).count
                        < bodyParts(of: b).intersection(remaining).count
                }
            guard let best, !bodyParts(of: best).intersection(remaining).isEmpty else { break }
            chosen.append(best)
            remaining.subtract(bodyParts(of: best))
        }
        return chosen
    }

    /// External EXRX.NET reference for a movement — a site-scoped web search so the
    /// user lands on EXRX's own page in their browser (copyright-respecting; we link,
    /// not embed). Name is URL-encoded.
    static func exrxReferenceURL(forName name: String) -> URL? {
        let q = "site:exrx.net \(name)"
        guard let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.google.com/search?q=\(enc)")
    }
}

public extension Exercise {
    /// Body parts this (possibly custom) exercise trains, from its muscle groups.
    var bodyParts: Set<BodyPart> { BodyPart.parts(forMuscleIDs: muscleGroups) }
}
