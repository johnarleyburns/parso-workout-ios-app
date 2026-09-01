import Foundation

/// Public-domain exercise data (free-exercise-db++, Unlicense — see `CREDITS.md`)
/// transformed **on-device** into our own taxonomy. DB++ owns the bundled database;
/// `TrainingEngineBridge` supplies a stable app-facing record snapshot so this
/// transform does not duplicate its decoder or leak package types.
public enum ImportedExerciseLibrary {

    // MARK: Mapping tables (their coarse taxonomy → ours)

    /// upstream equipment → our `Equipment`. "e-z curl bar" folds into
    /// barbell; "foam roll" / "exercise ball" / "medicine ball" / "other" / null have
    /// no faithful facet and stay `nil` (equipment is optional) rather than mislabel.
    static let equipmentMap: [String: Equipment] = [
        "barbell": .barbell, "dumbbell": .dumbbell, "cable": .cable,
        "machine": .machine, "body only": .bodyweight, "bands": .band,
        "kettlebells": .kettlebell, "e-z curl bar": .barbell,
    ]

    // MARK: Pure transform

    /// Our movement-split category, derived from their `category`, the primary
    /// muscle's body region, and `force` (push/pull). Cardio and plyometrics carry
    /// straight over; strength movements split by region then push/pull.
    static func category(primaryGroups: [MuscleGroup], force: Force?, rawCategory: String) -> ExerciseCategory {
        switch rawCategory {
        case "cardio": return .cardio
        case "plyometrics": return .plyometrics
        default: break
        }
        guard let region = primaryGroups.first?.region else {
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
    /// `MuscleGroup` value, satisfying catalog integrity).
    static func template(from record: TrainingEngineBridge.ExerciseRecord) -> ExerciseTemplate? {
        let direct = MuscleGroup.canonicalize(record.direct)
        let indirect = MuscleGroup.canonicalize(record.indirect)
            .filter { !direct.contains($0) }
        let stabilizers = MuscleGroup.canonicalize(record.stabilizers)
            .filter { !direct.contains($0) && !indirect.contains($0) }

        // Non-volume movements (stretching, plyometrics, cardio) carry an empty
        // `direct` list by construction, so fall back to the upstream primary
        // muscles: they stay searchable and browsable by muscle, they simply never
        // earn volume credit (decision D3).
        let fallbackPrimary = MuscleGroup.canonicalize(record.primaryMuscles)
        let fallbackSecondary = MuscleGroup.canonicalize(record.secondaryMuscles)
            .filter { !fallbackPrimary.contains($0) }
        let primary = direct.isEmpty ? fallbackPrimary : direct
        let secondary = direct.isEmpty ? fallbackSecondary : indirect
        guard !primary.isEmpty else { return nil }

        let force = record.force.flatMap { Force(rawValue: $0) }
        let mechanics = record.mechanic.flatMap { Mechanics(rawValue: $0) } ?? .compound
        let equipment = record.equipment.flatMap { equipmentMap[$0.lowercased()] }
        let cat = category(primaryGroups: primary, force: force, rawCategory: record.category)
        return ExerciseTemplate(
            record.name, cat, equipment, force, mechanics,
            primary: primary.map(\.rawValue), secondary: secondary.map(\.rawValue),
            lateral: isLateral(record.name),
            instructions: record.instructions,
            imageName: record.images.isEmpty ? nil : record.exerciseId,
            level: record.level,
            direct: direct, indirect: indirect, stabilizers: stabilizers,
            volumeEligible: record.volumeEligible,
            trainingTypes: trainingTypes(for: record),
            modalities: modalities(for: record),
            sportContexts: sportContexts(for: record),
            movementPatternIDs: record.patterns,
            annotationConfidence: record.confidence.flatMap(AnnotationConfidence.init(rawValue:)),
            sourceExerciseID: record.exerciseId
        )
    }

    private static func trainingTypes(for record: TrainingEngineBridge.ExerciseRecord) -> [ExerciseTrainingType] {
        switch record.category {
        case "cardio": return [.cardio]
        case "plyometrics": return [.plyometrics]
        case "stretching": return [.stretching]
        case "powerlifting": return [.strength, .powerlifting]
        case "olympic weightlifting": return [.strength, .olympicWeightlifting]
        case "strongman": return [.strength, .strongman]
        default: return [.strength]
        }
    }

    private static func modalities(for record: TrainingEngineBridge.ExerciseRecord) -> [ExerciseModality] {
        let equipment = record.equipment?.lowercased()
        var result: [ExerciseModality]
        switch equipment {
        case "body only": result = [.bodyweight]
        case "barbell", "dumbbell", "e-z curl bar": result = [.freeWeight]
        case "cable": result = [.cable]
        case "machine": result = [.machine]
        case "bands": result = [.band]
        case "kettlebells": result = [.kettlebell]
        case "medicine ball": result = [.medicineBall]
        case "foam roll": result = [.foamRoll]
        default: result = [.other]
        }

        let name = record.name.lowercased()
        if name.contains("rope") || name.contains("ropes") { result.append(.rope) }
        if name.contains("sled") || name.contains("prowler") || name.contains("drag") { result.append(.sled) }
        if name.contains("stone") || name.contains("keg") || name.contains("tire")
            || name.contains("yoke") || name.contains("sandbag") || name.contains("conan") {
            result.append(.loadedObject)
        }
        return result
    }

    private static func sportContexts(for record: TrainingEngineBridge.ExerciseRecord) -> [ExerciseSportContext] {
        var result: [ExerciseSportContext] = [.generalFitness]
        switch record.category {
        case "powerlifting": result.append(.powerlifting)
        case "olympic weightlifting": result.append(.weightlifting)
        case "strongman": result.append(.strongman)
        default: break
        }

        let name = record.name.lowercased()
        if name.contains("iron cross") || name.contains("ring dip") || name.contains("muscle up") {
            result.append(.gymnastics)
        }
        if name.contains("kettlebell thruster") || name.contains("kipping muscle up") {
            result.append(.crossfit)
        }
        return result
    }

    // MARK: Bundled data

    /// The transformed public-domain catalog (lazy; built once from DB++'s bundled
    /// database). Empty if the package database is unavailable so the app still seeds
    /// the curated catalog. Records arrive already sorted by `exerciseId`.
    public static let templates: [ExerciseTemplate] =
        TrainingEngineBridge.exerciseRecords.compactMap(template(from:))
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
