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
        case .squat: {
            #if os(Linux)
            "Squat"
            #else
            String(localized: "Squat", bundle: .module)
            #endif
        }()
        case .hinge: {
            #if os(Linux)
            "Hinge"
            #else
            String(localized: "Hinge", bundle: .module)
            #endif
        }()
        case .horizontalPush: {
            #if os(Linux)
            "Horizontal Push"
            #else
            String(localized: "Horizontal Push", bundle: .module)
            #endif
        }()
        case .horizontalPull: {
            #if os(Linux)
            "Horizontal Pull"
            #else
            String(localized: "Horizontal Pull", bundle: .module)
            #endif
        }()
        case .verticalPush: {
            #if os(Linux)
            "Vertical Push"
            #else
            String(localized: "Vertical Push", bundle: .module)
            #endif
        }()
        case .verticalPull: {
            #if os(Linux)
            "Vertical Pull"
            #else
            String(localized: "Vertical Pull", bundle: .module)
            #endif
        }()
        case .carry: {
            #if os(Linux)
            "Carry"
            #else
            String(localized: "Carry", bundle: .module)
            #endif
        }()
        case .core: {
            #if os(Linux)
            "Core"
            #else
            String(localized: "Core", bundle: .module)
            #endif
        }()
        case .locomotion: {
            #if os(Linux)
            "Locomotion"
            #else
            String(localized: "Locomotion", bundle: .module)
            #endif
        }()
        case .olympic: {
            #if os(Linux)
            "Olympic"
            #else
            String(localized: "Olympic", bundle: .module)
            #endif
        }()
        case .other: {
            #if os(Linux)
            "Other"
            #else
            String(localized: "Other", bundle: .module)
            #endif
        }()
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
