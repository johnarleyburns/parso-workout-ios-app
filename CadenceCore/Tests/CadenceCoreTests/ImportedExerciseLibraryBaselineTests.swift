import XCTest
@testable import CadenceCore

/// Proves the free-exercise-db++ swap changed nothing about the templates we
/// produce. DB++ carries every upstream record verbatim under `source`, so the
/// transform's output must be identical to what the old `free-exercise-db.json`
/// snapshot produced. These expectations were captured from the build immediately
/// BEFORE the swap — that is what makes this a regression gate and not a tautology.
final class ImportedExerciseLibraryBaselineTests: XCTestCase {

    private struct Baseline {
        let name: String
        let category: String
        let equipment: String      // "" when nil
        let force: String          // "" when nil
        let mechanics: String
        let lateral: Bool
        let primary: String        // pipe-joined
        let secondary: String      // pipe-joined
        let imageName: String      // "" when nil
        let level: String          // "" when nil
        let instructionCount: Int
    }

    /// Twenty templates spread evenly across the alphabetically sorted catalog.
    private static let baselines: [Baseline] = [
        Baseline(name: "3/4 Sit-Up", category: "core", equipment: "bodyweight", force: "pull",
                 mechanics: "compound", lateral: false, primary: "abs", secondary: "",
                 imageName: "3_4_Sit-Up", level: "beginner", instructionCount: 5),
        Baseline(name: "Barbell Curls Lying Against An Incline", category: "pull", equipment: "barbell", force: "pull",
                 mechanics: "isolation", lateral: false, primary: "biceps", secondary: "",
                 imageName: "Barbell_Curls_Lying_Against_An_Incline", level: "beginner", instructionCount: 4),
        Baseline(name: "Body-Up", category: "push", equipment: "bodyweight", force: "push",
                 mechanics: "isolation", lateral: false, primary: "triceps", secondary: "abs|forearms",
                 imageName: "Body-Up", level: "intermediate", instructionCount: 4),
        Baseline(name: "Calf Stretch Elbows Against Wall", category: "legs", equipment: "", force: "static",
                 mechanics: "isolation", lateral: false, primary: "calves", secondary: "",
                 imageName: "Calf_Stretch_Elbows_Against_Wall", level: "beginner", instructionCount: 3),
        Baseline(name: "Cross-Body Crunch", category: "core", equipment: "bodyweight", force: "pull",
                 mechanics: "compound", lateral: false, primary: "abs", secondary: "",
                 imageName: "Cross-Body_Crunch", level: "beginner", instructionCount: 5),
        Baseline(name: "Dumbbell Lunges", category: "legs", equipment: "dumbbell", force: "push",
                 mechanics: "compound", lateral: false, primary: "quads", secondary: "calves|glutes|hamstrings",
                 imageName: "Dumbbell_Lunges", level: "beginner", instructionCount: 4),
        Baseline(name: "Floor Press", category: "push", equipment: "barbell", force: "push",
                 mechanics: "compound", lateral: false, primary: "triceps", secondary: "chest|delts",
                 imageName: "Floor_Press", level: "intermediate", instructionCount: 3),
        Baseline(name: "Heavy Bag Thrust", category: "plyometrics", equipment: "", force: "push",
                 mechanics: "compound", lateral: false, primary: "chest", secondary: "abs|delts|triceps",
                 imageName: "Heavy_Bag_Thrust", level: "beginner", instructionCount: 3),
        Baseline(name: "Jerk Balance", category: "push", equipment: "barbell", force: "push",
                 mechanics: "compound", lateral: false, primary: "delts", secondary: "glutes|hamstrings|quads|triceps",
                 imageName: "Jerk_Balance", level: "intermediate", instructionCount: 3),
        Baseline(name: "Leverage Chest Press", category: "push", equipment: "machine", force: "push",
                 mechanics: "compound", lateral: false, primary: "chest", secondary: "delts|triceps",
                 imageName: "Leverage_Chest_Press", level: "beginner", instructionCount: 4),
        Baseline(name: "Machine Shoulder (Military) Press", category: "push", equipment: "machine", force: "push",
                 mechanics: "compound", lateral: false, primary: "delts", secondary: "triceps",
                 imageName: "Machine_Shoulder_Military_Press", level: "beginner", instructionCount: 5),
        Baseline(name: "One-Arm Kettlebell Push Press", category: "push", equipment: "kettlebell", force: "push",
                 mechanics: "compound", lateral: true, primary: "delts", secondary: "calves|quads|triceps",
                 imageName: "One-Arm_Kettlebell_Push_Press", level: "intermediate", instructionCount: 3),
        Baseline(name: "Power Snatch", category: "legs", equipment: "barbell", force: "pull",
                 mechanics: "compound", lateral: false, primary: "hamstrings", secondary: "calves|glutes|lower-back|quads|delts|traps|triceps",
                 imageName: "Power_Snatch", level: "expert", instructionCount: 5),
        Baseline(name: "Rhomboids-SMR", category: "pull", equipment: "", force: "static",
                 mechanics: "compound", lateral: false, primary: "rhomboids", secondary: "traps",
                 imageName: "Rhomboids-SMR", level: "intermediate", instructionCount: 2),
        Baseline(name: "Seated Head Harness Neck Resistance", category: "pull", equipment: "", force: "pull",
                 mechanics: "isolation", lateral: false, primary: "traps", secondary: "",
                 imageName: "Seated_Head_Harness_Neck_Resistance", level: "intermediate", instructionCount: 6),
        Baseline(name: "Skating", category: "cardio", equipment: "", force: "",
                 mechanics: "compound", lateral: false, primary: "quads", secondary: "abductors|adductors|calves|glutes|hamstrings",
                 imageName: "Skating", level: "intermediate", instructionCount: 2),
        Baseline(name: "Squat Jerk", category: "legs", equipment: "barbell", force: "push",
                 mechanics: "compound", lateral: false, primary: "quads", secondary: "calves|glutes|hamstrings|delts|triceps",
                 imageName: "Squat_Jerk", level: "expert", instructionCount: 3),
        Baseline(name: "Standing Pelvic Tilt", category: "pull", equipment: "", force: "static",
                 mechanics: "isolation", lateral: false, primary: "lower-back", secondary: "glutes",
                 imageName: "Standing_Pelvic_Tilt", level: "beginner", instructionCount: 3),
        Baseline(name: "Triceps Pushdown - V-Bar Attachment", category: "push", equipment: "cable", force: "push",
                 mechanics: "isolation", lateral: false, primary: "triceps", secondary: "",
                 imageName: "Triceps_Pushdown_-_V-Bar_Attachment", level: "beginner", instructionCount: 5),
        Baseline(name: "Zottman Preacher Curl", category: "pull", equipment: "dumbbell", force: "pull",
                 mechanics: "isolation", lateral: false, primary: "biceps", secondary: "forearms",
                 imageName: "Zottman_Preacher_Curl", level: "intermediate", instructionCount: 6),
    ]

    func testTemplateCountUnchangedByDatabaseSwap() {
        XCTAssertEqual(ImportedExerciseLibrary.templates.count, 873)
    }

    func testSampledTemplatesAreUnchangedByDatabaseSwap() throws {
        let byName = Dictionary(ImportedExerciseLibrary.templates.map { ($0.name, $0) },
                                uniquingKeysWith: { a, _ in a })
        for expected in Self.baselines {
            let actual = try XCTUnwrap(byName[expected.name], "missing template \(expected.name)")
            XCTAssertEqual(actual.category.rawValue, expected.category, expected.name)
            XCTAssertEqual(actual.equipment?.rawValue ?? "", expected.equipment, expected.name)
            XCTAssertEqual(actual.force?.rawValue ?? "", expected.force, expected.name)
            XCTAssertEqual(actual.mechanics.rawValue, expected.mechanics, expected.name)
            XCTAssertEqual(actual.isLateral, expected.lateral, expected.name)
            XCTAssertEqual(actual.primaryMuscles.joined(separator: "|"), expected.primary, expected.name)
            XCTAssertEqual(actual.secondaryMuscles.joined(separator: "|"), expected.secondary, expected.name)
            XCTAssertEqual(actual.imageName ?? "", expected.imageName, expected.name)
            XCTAssertEqual(actual.level ?? "", expected.level, expected.name)
            XCTAssertEqual(actual.instructions.count, expected.instructionCount, expected.name)
        }
    }

    /// Order is what keeps the curated/imported merge stable across launches.
    func testTemplateOrderFollowsSortedExerciseIDs() {
        let templateNames = ImportedExerciseLibrary.templates.map(\.name)
        let expected = ExerciseDatabase.records
            .compactMap { ImportedExerciseLibrary.template(from: $0)?.name }
        XCTAssertEqual(templateNames, expected)
    }
}
