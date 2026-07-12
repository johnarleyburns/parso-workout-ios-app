import Foundation

public enum MovementFamily: String, CaseIterable, Sendable, Codable {
    case squat
    case hinge
    case horizontalPush
    case horizontalPull
    case verticalPush
    case verticalPull
    case carry
    case core
    case locomotion
    case olympic
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
        case .core: "Core"
        case .locomotion: "Locomotion"
        case .olympic: "Olympic"
        case .other: "Other"
        }
    }

    public static func family(forExerciseNamed name: String,
                               primaryMuscles: [String],
                               category: String? = nil) -> MovementFamily {
        let lower = name.lowercased()

        let olympicKeywords = [
            "snatch", "clean", "jerk",
            "muscle snatch", "power snatch", "power clean",
            "hang snatch", "hang clean",
            "clean & press", "clean & jerk",
            "power-snatch", "power-clean", "power-clean",
        ]
        for kw in olympicKeywords where lower.contains(kw) {
            return .olympic
        }

        let patterns = MovementPattern.patterns(forExerciseNamed: name,
                                                 primaryMuscles: primaryMuscles,
                                                 category: category)
        if patterns.isEmpty || patterns == [.other] {
            return .other
        }

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

        for kw in squatKeywords where lower.contains(kw) { return .squat }
        for kw in hingeKeywords where lower.contains(kw) { return .hinge }
        for kw in horizontalPushKeywords where lower.contains(kw) { return .horizontalPush }
        for kw in horizontalPullKeywords where lower.contains(kw) { return .horizontalPull }
        for kw in verticalPushKeywords where lower.contains(kw) { return .verticalPush }
        for kw in verticalPullKeywords where lower.contains(kw) { return .verticalPull }
        for kw in carryKeywords where lower.contains(kw) { return .carry }
        for kw in locomotionKeywords where lower.contains(kw) { return .locomotion }
        for kw in coreKeywords where lower.contains(kw) { return .core }

        return .other
    }
}
