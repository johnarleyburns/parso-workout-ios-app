import Foundation

public enum MovementPattern: String, CaseIterable, Sendable, Codable {
    case squat
    case hinge
    case horizontalPush
    case horizontalPull
    case verticalPush
    case verticalPull
    case carry
    case locomotion
    case core
    case other

    public var displayName: String {
        switch self {
        case .squat: "Squat"
        case .hinge: "Hinge"
        case .horizontalPush: "Horizontal Push"
        case .horizontalPull: "Horizontal Pull"
        case .verticalPush: "Vertical Push"
        case .verticalPull: "Vertical Pull"
        case .carry: "Carry"
        case .locomotion: "Locomotion"
        case .core: "Core"
        case .other: "Other"
        }
    }

    public var isLowerBody: Bool {
        switch self {
        case .squat, .hinge, .locomotion: true
        default: false
        }
    }

    public var isUpperBody: Bool {
        switch self {
        case .horizontalPush, .horizontalPull, .verticalPush, .verticalPull: true
        default: false
        }
    }

    public static func patterns(forExerciseNamed name: String,
                                 primaryMuscles: [String],
                                 category: String? = nil,
                                 databasePatternIDs: [String] = []) -> Set<MovementPattern> {
        // free-exercise-db++ classifies every movement against a canonical pattern
        // vocabulary that was derived from the literature rather than from the
        // movement's name. When we have one, trust it over the keyword heuristic.
        let annotated = Set(databasePatternIDs.compactMap(MovementPattern.init(databasePatternID:)))
        if !annotated.isEmpty { return annotated }

        let lower = name.lowercased()
        let muscles = Set(MuscleGroup.canonicalize(primaryMuscles).map(\.rawValue))
        var patterns = Set<MovementPattern>()

        let squatKeywords = ["squat", "lunge", "leg press", "bulgarian", "step-up", "step up"]
        let hingeKeywords = ["deadlift", "romanian", "good morning", "hip thrust", "glute bridge",
                             "kettlebell swing", "pull through", "back extension", "hyperextension"]
        let horizontalPushKeywords = ["bench press", "push-up", "push up", "dip", "chest press",
                                       "pec deck", "cable crossover", "fly", "floor press"]
        let horizontalPullKeywords = ["row", "face pull", "pullover", "pull-over", "reverse fly",
                                       "rear delt"]
        let verticalPushKeywords = ["overhead press", "shoulder press", "military press",
                                     "arnold press", "lateral raise", "front raise", "upright row"]
        let verticalPullKeywords = ["pull-up", "pull up", "chin-up", "chin up", "lat pulldown",
                                     "pulldown", "pull down"]
        let carryKeywords = ["carry", "farmer", "suitcase", "yoke"]
        let locomotionKeywords = ["run", "walk", "jog", "sprint", "cycle", "swim", "row", "rowing"]
        let coreKeywords = ["crunch", "sit-up", "sit up", "plank", "leg raise", "ab", "russian twist",
                            "pallof", "wood chop", "hanging knee"]
        let olympicKeywords = ["snatch", "clean", "jerk", "muscle snatch", "power snatch",
                               "power clean", "hang snatch", "hang clean",
                               "clean & press", "clean & jerk"]

        for kw in squatKeywords where lower.contains(kw) { patterns.insert(.squat) }
        for kw in hingeKeywords where lower.contains(kw) { patterns.insert(.hinge) }
        for kw in horizontalPushKeywords where lower.contains(kw) { patterns.insert(.horizontalPush) }
        for kw in horizontalPullKeywords where lower.contains(kw) { patterns.insert(.horizontalPull) }
        for kw in verticalPushKeywords where lower.contains(kw) { patterns.insert(.verticalPush) }
        for kw in verticalPullKeywords where lower.contains(kw) { patterns.insert(.verticalPull) }
        for kw in carryKeywords where lower.contains(kw) { patterns.insert(.carry) }
        for kw in locomotionKeywords where lower.contains(kw) { patterns.insert(.locomotion) }
        for kw in coreKeywords where lower.contains(kw) { patterns.insert(.core) }
        for kw in olympicKeywords where lower.contains(kw) {
            patterns.insert(.hinge)
            patterns.insert(.verticalPush)
        }

        if patterns.isEmpty {
            // Muscle sets are canonical `MuscleGroup` raw values (DB++ adoption).
            let legMuscles: Set<String> = ["quadriceps", "hamstrings", "glutes", "adductors",
                                           "abductors", "hip_flexors", "tibialis"]
            let pushMuscles: Set<String> = ["chest", "triceps"]
            let pullMuscles: Set<String> = ["lats", "biceps", "traps", "middle_back"]
            let shoulderMuscles: Set<String> = ["shoulders", "rotator_cuff"]
            let coreMuscles: Set<String> = ["abdominals", "lower_back"]

            if !muscles.isDisjoint(with: legMuscles) && muscles.isDisjoint(with: pullMuscles) {
                patterns.insert(.squat)
            }
            if muscles.contains("lower_back") || (muscles.contains("hamstrings") && muscles.contains("glutes")) {
                patterns.insert(.hinge)
            }
            if !muscles.isDisjoint(with: pushMuscles) && !muscles.contains("shoulders") {
                patterns.insert(.horizontalPush)
            }
            if !muscles.isDisjoint(with: pullMuscles) && !muscles.contains("biceps") {
                patterns.insert(.horizontalPull)
            }
            if !muscles.isDisjoint(with: shoulderMuscles) {
                patterns.insert(.verticalPush)
            }
            if !muscles.isDisjoint(with: coreMuscles) {
                patterns.insert(.core)
            }
        }

        if patterns.isEmpty { patterns.insert(.other) }
        return patterns
    }
}

public extension MovementPattern {
    /// Maps a free-exercise-db++ movement pattern id onto our coarse pattern.
    ///
    /// Isolation and single-joint patterns (`elbow_flexion`, `knee_extension`,
    /// `grip`, the neck and forearm patterns …) deliberately return `nil`: our
    /// vocabulary has no bucket for them, and the caller's keyword heuristic gives
    /// a better answer than forcing them into one.
    init?(databasePatternID id: String) {
        switch id {
        case "squat", "squat_quad_bias", "leg_press", "step_up", "lunge":
            self = .squat
        case "hip_hinge", "conventional_deadlift", "sumo_deadlift", "rack_pull",
             "hip_extension", "glute_ham_raise", "kettlebell_swing", "olympic_clean",
             "olympic_snatch", "olympic_clean_pull", "olympic_snatch_pull",
             "olympic_clean_and_jerk", "kettlebell_clean", "kettlebell_snatch",
             "kettlebell_sumo_high_pull":
            self = .hinge
        case "horizontal_press", "incline_press", "decline_press",
             "horizontal_press_triceps_bias", "chest_fly", "dip_chest_bias":
            self = .horizontalPush
        case "horizontal_pull", "reverse_fly", "face_pull", "upright_row", "shrug":
            self = .horizontalPull
        case "vertical_press", "push_press", "olympic_jerk", "kettlebell_jerk",
             "strongman_overhead", "thruster", "snatch_balance", "dip_triceps_bias",
             "bent_press":
            self = .verticalPush
        case "vertical_pull", "muscle_up", "rope_climb", "pullover":
            self = .verticalPull
        case "loaded_carry", "farmer_carry", "strongman_carry", "sled_push", "sled_pull",
             "drag_with_press", "power_stairs", "atlas_stone_load", "loaded_object_load",
             "tire_flip":
            self = .carry
        case "spider_crawl", "battle_ropes", "medicine_ball_slam":
            self = .locomotion
        case "trunk_flexion", "trunk_extension", "trunk_rotation", "lateral_flexion",
             "anti_extension", "anti_rotation", "kettlebell_windmill",
             "kettlebell_figure8", "kettlebell_pirate_ships":
            self = .core
        default:
            return nil
        }
    }
}
