import Foundation

/// Public-domain exercise data (free-exercise-db++, Unlicense — see `CREDITS.md`)
/// transformed **on-device** into our own taxonomy. The document ships as a bundled
/// package resource and is decoded by `ExerciseDatabase`; the transform here is a
/// pure, `swift test`-verifiable function that maps the upstream record DB++ carries
/// under `source` onto our `MuscleCatalog` ids, `Equipment`, and movement-split
/// `ExerciseCategory`. Strength-pivot P2 (D2).
///
/// DB++'s own annotation layer — direct/indirect/stabilizer muscle roles, volume
/// eligibility, movement classification — is decoded and available on
/// `ExerciseDatabase.Record`, and is consumed from phase 3 of the DB++ adoption
/// onward. This file deliberately still reads only `source`, which is byte-identical
/// to the free-exercise-db snapshot it replaced.
public enum ImportedExerciseLibrary {

    // MARK: Mapping tables (their coarse taxonomy → ours)

    /// upstream muscle string → our `MuscleCatalog` id. Their taxonomy is
    /// coarser (17 buckets); this hand-checked table is the curation step (plan §02).
    /// "middle back" → rhomboids and "neck" → traps are the only non-obvious calls.
    static let muscleMap: [String: String] = [
        "abdominals": "abs", "abductors": "abductors", "adductors": "adductors",
        "biceps": "biceps", "calves": "calves", "chest": "chest",
        "forearms": "forearms", "glutes": "glutes", "hamstrings": "hamstrings",
        "lats": "lats", "lower back": "lower-back", "middle back": "rhomboids",
        "neck": "traps", "quadriceps": "quads", "shoulders": "delts",
        "traps": "traps", "triceps": "triceps",
    ]

    /// upstream equipment → our `Equipment`. "e-z curl bar" folds into
    /// barbell; "foam roll" / "exercise ball" / "medicine ball" / "other" / null have
    /// no faithful facet and stay `nil` (equipment is optional) rather than mislabel.
    static let equipmentMap: [String: Equipment] = [
        "barbell": .barbell, "dumbbell": .dumbbell, "cable": .cable,
        "machine": .machine, "body only": .bodyweight, "bands": .band,
        "kettlebells": .kettlebell, "e-z curl bar": .barbell,
    ]

    // MARK: Pure transform

    /// Maps their muscle strings → unique `MuscleCatalog` ids, preserving order and
    /// dropping any we don't recognize (none, given the table covers all 17).
    static func muscleIDs(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for m in raw {
            if let id = muscleMap[m.lowercased()], seen.insert(id).inserted { out.append(id) }
        }
        return out
    }

    /// Our movement-split category, derived from their `category`, the primary
    /// muscle's body region, and `force` (push/pull). Cardio and plyometrics carry
    /// straight over; strength movements split by region then push/pull.
    static func category(primaryIDs: [String], force: Force?, rawCategory: String) -> ExerciseCategory {
        switch rawCategory {
        case "cardio": return .cardio
        case "plyometrics": return .plyometrics
        default: break
        }
        guard let region = primaryIDs.first.flatMap({ MuscleCatalog.muscle($0)?.region }) else {
            return .other
        }
        switch region {
        case .legs, .glutes: return .legs
        case .core: return .core
        case .chest, .shoulders, .arms, .back, .fullBody:
            switch force {
            case .push: return .push
            case .pull: return .pull
            default:
                if region == .back { return .pull }
                if region == .chest || region == .shoulders { return .push }
                return .other
            }
        }
    }

    /// Unilateral/isolateral heuristic from the movement name (our `isLateral` flag).
    static func isLateral(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("single-arm") || n.contains("single arm")
            || n.contains("single-leg") || n.contains("single leg")
            || n.contains("one-arm") || n.contains("one arm")
            || n.contains("one-leg") || n.contains("one leg")
    }

    /// Transform one database record into our `ExerciseTemplate`, or `nil` if it maps
    /// to no known muscle (so every imported entry is guaranteed to have ≥1
    /// `MuscleCatalog` id, satisfying catalog integrity).
    static func template(from record: ExerciseDatabase.Record) -> ExerciseTemplate? {
        let e = record.source
        let primary = muscleIDs(e.primaryMuscles)
        guard !primary.isEmpty else { return nil }
        let secondary = muscleIDs(e.secondaryMuscles).filter { !primary.contains($0) }
        let force = e.force.flatMap { Force(rawValue: $0) }
        let mechanics = e.mechanic.flatMap { Mechanics(rawValue: $0) } ?? .compound
        let equipment = e.equipment.flatMap { equipmentMap[$0.lowercased()] }
        let cat = category(primaryIDs: primary, force: force, rawCategory: e.category)
        return ExerciseTemplate(
            e.name, cat, equipment, force, mechanics,
            primary: primary, secondary: secondary, lateral: isLateral(e.name),
            instructions: e.instructions,
            imageName: e.images.isEmpty ? nil : e.id,
            level: e.level
        )
    }

    // MARK: Bundled data

    /// The transformed public-domain catalog (lazy; decoded once from the bundled
    /// resource). Empty if the resource is missing/corrupt so the app still seeds the
    /// curated catalog. Order follows `ExerciseDatabase.records`, which is sorted by
    /// `exerciseId`, so merges stay stable.
    public static let templates: [ExerciseTemplate] =
        ExerciseDatabase.records.compactMap(template(from:))
}

public extension ExerciseLibrary {
    /// The upstream repository, shown as a tappable attribution link and opened in
    /// Safari on tap. This is displayed, never fetched by the app (NFR-3).
    static let exerciseRepoURL = URL(string: "https://github.com/yuhonas/free-exercise-db")!

    /// The annotation layer we actually vendor, which carries the upstream data
    /// verbatim and adds the evidence-audited muscle roles. Displayed, never fetched.
    static let exerciseAnnotationRepoURL =
        URL(string: "https://github.com/johnarleyburns/free-exercise-db-plusplus")!

    /// Local file URLs for an exercise's bundled images, in display order.
    /// Resolves from `Bundle.module` via `ExerciseImageCatalog` — there is no
    /// runtime network path. Empty when the exercise has no bundled photography.
    static func imageURLs(forImageName name: String?) -> [URL] {
        guard let name, !name.isEmpty else { return [] }
        return ExerciseImageCatalog.imageURLs(forImageName: name)
    }
}
