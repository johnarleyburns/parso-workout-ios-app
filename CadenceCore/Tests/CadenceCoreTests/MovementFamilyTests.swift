import Testing
@testable import CadenceCore

struct MovementFamilyTests {

    // MARK: - Olympic family

    @Test func snatchVariantsMapToOlympic() {
        #expect(MovementFamily.family(forExerciseNamed: "Snatch", primaryMuscles: ["delts", "traps"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Double Kettlebell Snatch", primaryMuscles: ["delts", "traps"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Kettlebell Snatch", primaryMuscles: ["delts", "traps"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Dumbbell Snatch", primaryMuscles: ["delts", "traps"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Power Snatch", primaryMuscles: ["delts", "hamstrings"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Hang Snatch", primaryMuscles: ["delts", "hamstrings"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Muscle Snatch", primaryMuscles: ["delts"]) == .olympic)
    }

    @Test func cleanJerkVariantsMapToOlympic() {
        #expect(MovementFamily.family(forExerciseNamed: "Clean", primaryMuscles: ["traps", "hamstrings"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Clean & Jerk", primaryMuscles: ["delts", "traps", "quads"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Clean & Press", primaryMuscles: ["delts", "triceps"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Power Clean", primaryMuscles: ["traps", "hamstrings"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Hang Clean", primaryMuscles: ["traps", "hamstrings"]) == .olympic)
        #expect(MovementFamily.family(forExerciseNamed: "Jerk", primaryMuscles: ["delts", "triceps"]) == .olympic)
    }

    // MARK: - Hinge family

    @Test func hingeVariantsMapToHinge() {
        #expect(MovementFamily.family(forExerciseNamed: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"]) == .hinge)
        #expect(MovementFamily.family(forExerciseNamed: "Romanian Deadlift", primaryMuscles: ["hamstrings", "glutes"]) == .hinge)
        #expect(MovementFamily.family(forExerciseNamed: "Trap Bar Deadlift", primaryMuscles: ["hamstrings"]) == .hinge)
        #expect(MovementFamily.family(forExerciseNamed: "Good Morning", primaryMuscles: ["hamstrings", "lower-back"]) == .hinge)
        #expect(MovementFamily.family(forExerciseNamed: "Hip Thrust", primaryMuscles: ["glutes"]) == .hinge)
        #expect(MovementFamily.family(forExerciseNamed: "Kettlebell Swing", primaryMuscles: ["glutes", "hamstrings"]) == .hinge)
    }

    // MARK: - Squat family

    @Test func squatVariantsMapToSquat() {
        #expect(MovementFamily.family(forExerciseNamed: "Back Squat", primaryMuscles: ["quads"]) == .squat)
        #expect(MovementFamily.family(forExerciseNamed: "Bulgarian Split Squat", primaryMuscles: ["quads"]) == .squat)
        #expect(MovementFamily.family(forExerciseNamed: "Leg Press", primaryMuscles: ["quads"]) == .squat)
    }

    // MARK: - Press / pull families

    @Test func pushPullVariants() {
        #expect(MovementFamily.family(forExerciseNamed: "Bench Press", primaryMuscles: ["chest"]) == .horizontalPush)
        #expect(MovementFamily.family(forExerciseNamed: "Barbell Row", primaryMuscles: ["lats"]) == .horizontalPull)
        #expect(MovementFamily.family(forExerciseNamed: "Overhead Press", primaryMuscles: ["delts"]) == .verticalPush)
        #expect(MovementFamily.family(forExerciseNamed: "Pull-Up", primaryMuscles: ["lats"]) == .verticalPull)
    }

    // MARK: - Olympic keywords produce non-empty MovementPattern

    @Test func olympicKeywordsProduceNonEmptyPatterns() {
        let snatchPatterns = MovementPattern.patterns(forExerciseNamed: "Snatch",
                                                       primaryMuscles: ["delts", "traps"])
        #expect(!snatchPatterns.isEmpty, "Snatch should produce at least one movement pattern")
        #expect(snatchPatterns.contains(.hinge), "Snatch (triple-extension) should include hinge")
        #expect(snatchPatterns.contains(.verticalPush), "Snatch should include vertical push")

        let cleanPatterns = MovementPattern.patterns(forExerciseNamed: "Clean & Jerk",
                                                      primaryMuscles: ["delts", "traps", "quads"])
        #expect(!cleanPatterns.isEmpty, "Clean & Jerk should produce at least one pattern")
        #expect(cleanPatterns.contains(.hinge))
        #expect(cleanPatterns.contains(.verticalPush))

        let powerCleanPatterns = MovementPattern.patterns(forExerciseNamed: "Power Clean",
                                                           primaryMuscles: ["traps", "hamstrings"])
        #expect(!powerCleanPatterns.isEmpty, "Power Clean should produce at least one pattern")
    }

    // MARK: - Canonical name

    @Test func canonicalNameStripsEquipmentAndLaterality() {
        #expect(ExerciseNameCanonicalizer.canonicalName("Double Kettlebell Snatch") == "snatch")
        #expect(ExerciseNameCanonicalizer.canonicalName("Kettlebell Snatch") == "snatch")
        #expect(ExerciseNameCanonicalizer.canonicalName("Dumbbell Snatch") == "snatch")
        #expect(ExerciseNameCanonicalizer.canonicalName("Single Kettlebell Snatch") == "snatch")
        #expect(ExerciseNameCanonicalizer.canonicalName("Snatch") == "snatch")
    }

    @Test func canonicalNameStripsBarbellAndPosition() {
        #expect(ExerciseNameCanonicalizer.canonicalName("Barbell Bench Press") == "bench press")
        #expect(ExerciseNameCanonicalizer.canonicalName("Seated Dumbbell Overhead Press") == "overhead press")
        #expect(ExerciseNameCanonicalizer.canonicalName("Standing Barbell Curl") == "curl")
        #expect(ExerciseNameCanonicalizer.canonicalName("Alternate Dumbbell Curl") == "curl")
    }

    @Test func canonicalNameStripsGripQualifiers() {
        #expect(ExerciseNameCanonicalizer.canonicalName("Lat Pulldown - Pronated Grip") == "lat pulldown")
        #expect(ExerciseNameCanonicalizer.canonicalName("Lat Pulldown Pronated Grip") == "lat pulldown")
        #expect(ExerciseNameCanonicalizer.canonicalName("Lat Pulldown - Supinated Grip") == "lat pulldown")
    }

    @Test func canonicalNamePreservesCoreMovement() {
        #expect(ExerciseNameCanonicalizer.canonicalName("Deadlift") == "deadlift")
        #expect(ExerciseNameCanonicalizer.canonicalName("Back Squat") == "back squat")
        #expect(ExerciseNameCanonicalizer.canonicalName("Pull-Up") == "pull-up")
    }

    // MARK: - Fallback to other

    @Test func unknownExerciseFallsBackToOther() {
        let family = MovementFamily.family(forExerciseNamed: "Xyzzy Plate Hold",
                                            primaryMuscles: ["forearms"])
        #expect(family == .other)
    }
}
