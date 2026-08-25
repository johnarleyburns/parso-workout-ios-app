import XCTest
@testable import CadenceCore

final class MovementFamilyTests: XCTestCase {

    // MARK: - Olympic family

    func testSnatchVariantsMapToOlympic() {
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Snatch", primaryMuscles: ["delts", "traps"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Double Kettlebell Snatch", primaryMuscles: ["delts", "traps"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Kettlebell Snatch", primaryMuscles: ["delts", "traps"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Dumbbell Snatch", primaryMuscles: ["delts", "traps"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Power Snatch", primaryMuscles: ["delts", "hamstrings"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Hang Snatch", primaryMuscles: ["delts", "hamstrings"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Muscle Snatch", primaryMuscles: ["delts"]), .olympic)
    }

    func testCleanJerkVariantsMapToOlympic() {
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Clean", primaryMuscles: ["traps", "hamstrings"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Clean & Jerk", primaryMuscles: ["delts", "traps", "quads"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Clean & Press", primaryMuscles: ["delts", "triceps"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Power Clean", primaryMuscles: ["traps", "hamstrings"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Hang Clean", primaryMuscles: ["traps", "hamstrings"]), .olympic)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Jerk", primaryMuscles: ["delts", "triceps"]), .olympic)
    }

    // MARK: - Hinge family

    func testHingeVariantsMapToHinge() {
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Deadlift", primaryMuscles: ["hamstrings", "lower-back"]), .hinge)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Romanian Deadlift", primaryMuscles: ["hamstrings", "glutes"]), .hinge)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Trap Bar Deadlift", primaryMuscles: ["hamstrings"]), .hinge)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Good Morning", primaryMuscles: ["hamstrings", "lower-back"]), .hinge)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Hip Thrust", primaryMuscles: ["glutes"]), .hinge)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Kettlebell Swing", primaryMuscles: ["glutes", "hamstrings"]), .hinge)
    }

    // MARK: - Squat family

    func testSquatVariantsMapToSquat() {
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Back Squat", primaryMuscles: ["quads"]), .squat)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Bulgarian Split Squat", primaryMuscles: ["quads"]), .squat)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Leg Press", primaryMuscles: ["quads"]), .squat)
    }

    // MARK: - Press / pull families

    func testPushPullVariants() {
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Bench Press", primaryMuscles: ["chest"]), .horizontalPush)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Barbell Row", primaryMuscles: ["lats"]), .horizontalPull)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Overhead Press", primaryMuscles: ["delts"]), .verticalPush)
        XCTAssertEqual(MovementFamily.family(forExerciseNamed: "Pull-Up", primaryMuscles: ["lats"]), .verticalPull)
    }

    // MARK: - Olympic keywords produce non-empty MovementPattern

    func testOlympicKeywordsProduceNonEmptyPatterns() {
        let snatchPatterns = MovementPattern.patterns(forExerciseNamed: "Snatch",
                                                       primaryMuscles: ["delts", "traps"])
        XCTAssertFalse(snatchPatterns.isEmpty, "Snatch should produce at least one movement pattern")
        XCTAssertTrue(snatchPatterns.contains(.hinge), "Snatch (triple-extension) should include hinge")
        XCTAssertTrue(snatchPatterns.contains(.verticalPush), "Snatch should include vertical push")

        let cleanPatterns = MovementPattern.patterns(forExerciseNamed: "Clean & Jerk",
                                                      primaryMuscles: ["delts", "traps", "quads"])
        XCTAssertFalse(cleanPatterns.isEmpty, "Clean & Jerk should produce at least one pattern")
        XCTAssertTrue(cleanPatterns.contains(.hinge))
        XCTAssertTrue(cleanPatterns.contains(.verticalPush))

        let powerCleanPatterns = MovementPattern.patterns(forExerciseNamed: "Power Clean",
                                                           primaryMuscles: ["traps", "hamstrings"])
        XCTAssertFalse(powerCleanPatterns.isEmpty, "Power Clean should produce at least one pattern")
    }

    // MARK: - Canonical name

    func testCanonicalNameStripsEquipmentAndLaterality() {
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Double Kettlebell Snatch"), "snatch")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Kettlebell Snatch"), "snatch")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Dumbbell Snatch"), "snatch")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Single Kettlebell Snatch"), "snatch")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Snatch"), "snatch")
    }

    func testCanonicalNameStripsBarbellAndPosition() {
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Barbell Bench Press"), "bench press")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Seated Dumbbell Overhead Press"), "overhead press")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Standing Barbell Curl"), "curl")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Alternate Dumbbell Curl"), "curl")
    }

    func testCanonicalNameStripsGripQualifiers() {
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Lat Pulldown - Pronated Grip"), "lat pulldown")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Lat Pulldown Pronated Grip"), "lat pulldown")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Lat Pulldown - Supinated Grip"), "lat pulldown")
    }

    func testCanonicalNamePreservesCoreMovement() {
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Deadlift"), "deadlift")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Back Squat"), "back squat")
        XCTAssertEqual(ExerciseNameCanonicalizer.canonicalName("Pull-Up"), "pull-up")
    }

    // MARK: - Fallback to other

    func testUnknownExerciseFallsBackToOther() {
        let family = MovementFamily.family(forExerciseNamed: "Xyzzy Plate Hold",
                                            primaryMuscles: ["forearms"])
        XCTAssertEqual(family, .other)
    }
}
