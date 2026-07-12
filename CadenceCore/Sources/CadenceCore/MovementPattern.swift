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
                                 category: String? = nil) -> Set<MovementPattern> {
        let lower = name.lowercased()
        let muscles = Set(primaryMuscles)
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
            let legMuscles: Set<String> = ["quadriceps", "hamstrings", "glutes", "adductors", "abductors", "hip-flexors"]
            let pushMuscles: Set<String> = ["chest", "triceps", "front-delts"]
            let pullMuscles: Set<String> = ["lats", "biceps", "traps", "rhomboids", "rear-delts"]
            let shoulderMuscles: Set<String> = ["delts"]
            let coreMuscles: Set<String> = ["abs", "obliques", "lower-back"]

            if !muscles.isDisjoint(with: legMuscles) && muscles.isDisjoint(with: pullMuscles) {
                patterns.insert(.squat)
            }
            if muscles.contains("lower-back") || (muscles.contains("hamstrings") && muscles.contains("glutes")) {
                patterns.insert(.hinge)
            }
            if !muscles.isDisjoint(with: pushMuscles) && !muscles.contains("delts") {
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
