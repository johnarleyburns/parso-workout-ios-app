import XCTest
@testable import CadenceCore

/// Pins the templates `ImportedExerciseLibrary` produces from the package-backed
/// free-exercise-db++ database.
///
/// Phase 1 of the DB++ adoption proved the swap changed nothing, because DB++
/// carries every upstream record verbatim under `source`. Phase 3 then switched the
/// transform onto DB++'s audited annotation, which deliberately **did** change the
/// muscle roles: 729 of the 873 templates now have different primary/secondary
/// lists than the hand-mapped upstream strings produced. This file is the record of
/// what they became, so a future data refresh or mapping edit cannot move them
/// again unnoticed.
final class ImportedExerciseLibraryBaselineTests: XCTestCase {

    private struct Fixture {
        let name: String
        let category: String
        let equipment: String        // "" when nil
        let force: String            // "" when nil
        let mechanics: String
        let lateral: Bool
        let primary: String          // pipe-joined MuscleGroup raw values
        let secondary: String
        let stabilizers: String
        let volumeEligible: Bool
        let trainingTypes: String
        let modalities: String
        let imageName: String        // "" when nil
        let level: String            // "" when nil
        let instructionCount: Int
    }

    /// Twenty templates spread evenly across the alphabetically sorted catalog.
    private static let fixtures: [Fixture] = [
        Fixture(name: "3/4 Sit-Up", category: "core", equipment: "bodyweight", force: "pull",
                mechanics: "compound", lateral: false, primary: "abdominals", secondary: "",
                stabilizers: "", volumeEligible: true, trainingTypes: "strength",
                modalities: "bodyweight", imageName: "3_4_Sit-Up", level: "beginner", instructionCount: 5),
        Fixture(name: "Barbell Curls Lying Against An Incline", category: "pull", equipment: "barbell", force: "pull",
                mechanics: "isolation", lateral: false, primary: "biceps", secondary: "forearms",
                stabilizers: "", volumeEligible: true, trainingTypes: "strength",
                modalities: "free_weight", imageName: "Barbell_Curls_Lying_Against_An_Incline", level: "beginner", instructionCount: 4),
        Fixture(name: "Body-Up", category: "push", equipment: "bodyweight", force: "push",
                mechanics: "isolation", lateral: false, primary: "triceps", secondary: "",
                stabilizers: "", volumeEligible: true, trainingTypes: "strength",
                modalities: "bodyweight", imageName: "Body-Up", level: "intermediate", instructionCount: 4),
        Fixture(name: "Calf Stretch Elbows Against Wall", category: "legs", equipment: "", force: "static",
                mechanics: "isolation", lateral: false, primary: "calves", secondary: "",
                stabilizers: "", volumeEligible: false, trainingTypes: "stretching",
                modalities: "other", imageName: "Calf_Stretch_Elbows_Against_Wall", level: "beginner", instructionCount: 3),
        Fixture(name: "Cross-Body Crunch", category: "core", equipment: "bodyweight", force: "pull",
                mechanics: "compound", lateral: false, primary: "abdominals", secondary: "",
                stabilizers: "", volumeEligible: true, trainingTypes: "strength",
                modalities: "bodyweight", imageName: "Cross-Body_Crunch", level: "beginner", instructionCount: 5),
        Fixture(name: "Dumbbell Lunges", category: "legs", equipment: "dumbbell", force: "push",
                mechanics: "compound", lateral: false, primary: "quadriceps|glutes", secondary: "adductors",
                stabilizers: "hamstrings|calves", volumeEligible: true, trainingTypes: "strength",
                modalities: "free_weight", imageName: "Dumbbell_Lunges", level: "beginner", instructionCount: 4),
        Fixture(name: "Floor Press", category: "push", equipment: "barbell", force: "push",
                mechanics: "compound", lateral: false, primary: "triceps|chest", secondary: "shoulders",
                stabilizers: "", volumeEligible: true, trainingTypes: "strength|powerlifting",
                modalities: "free_weight", imageName: "Floor_Press", level: "intermediate", instructionCount: 3),
        Fixture(name: "Heavy Bag Thrust", category: "plyometrics", equipment: "", force: "push",
                mechanics: "compound", lateral: false, primary: "chest", secondary: "abdominals|shoulders|triceps",
                stabilizers: "", volumeEligible: false, trainingTypes: "plyometrics",
                modalities: "other", imageName: "Heavy_Bag_Thrust", level: "beginner", instructionCount: 3),
        Fixture(name: "Jerk Balance", category: "push", equipment: "barbell", force: "push",
                mechanics: "compound", lateral: false, primary: "shoulders|triceps|quadriceps|glutes", secondary: "calves",
                stabilizers: "abdominals|traps", volumeEligible: true, trainingTypes: "strength|olympic_weightlifting",
                modalities: "free_weight", imageName: "Jerk_Balance", level: "intermediate", instructionCount: 3),
        Fixture(name: "Leverage Chest Press", category: "push", equipment: "machine", force: "push",
                mechanics: "compound", lateral: false, primary: "chest", secondary: "triceps|shoulders",
                stabilizers: "", volumeEligible: true, trainingTypes: "strength",
                modalities: "machine", imageName: "Leverage_Chest_Press", level: "beginner", instructionCount: 4),
        Fixture(name: "Machine Shoulder (Military) Press", category: "push", equipment: "machine", force: "push",
                mechanics: "compound", lateral: false, primary: "shoulders", secondary: "triceps",
                stabilizers: "abdominals", volumeEligible: true, trainingTypes: "strength",
                modalities: "machine", imageName: "Machine_Shoulder_Military_Press", level: "beginner", instructionCount: 5),
        Fixture(name: "One-Arm Kettlebell Push Press", category: "push", equipment: "kettlebell", force: "push",
                mechanics: "compound", lateral: true, primary: "shoulders|triceps|quadriceps|glutes", secondary: "calves",
                stabilizers: "abdominals|traps", volumeEligible: true, trainingTypes: "strength",
                modalities: "kettlebell", imageName: "One-Arm_Kettlebell_Push_Press", level: "intermediate", instructionCount: 3),
        Fixture(name: "Power Snatch", category: "legs", equipment: "barbell", force: "pull",
                mechanics: "compound", lateral: false, primary: "quadriceps|glutes|traps", secondary: "hamstrings|calves",
                stabilizers: "shoulders|triceps|lower_back|forearms|abdominals", volumeEligible: true, trainingTypes: "strength|olympic_weightlifting",
                modalities: "free_weight", imageName: "Power_Snatch", level: "expert", instructionCount: 5),
        Fixture(name: "Rhomboids-SMR", category: "pull", equipment: "", force: "static",
                mechanics: "compound", lateral: false, primary: "middle_back", secondary: "traps",
                stabilizers: "", volumeEligible: false, trainingTypes: "stretching",
                modalities: "foam_roll", imageName: "Rhomboids-SMR", level: "intermediate", instructionCount: 2),
        Fixture(name: "Seated Head Harness Neck Resistance", category: "pull", equipment: "", force: "pull",
                mechanics: "isolation", lateral: false, primary: "neck", secondary: "",
                stabilizers: "", volumeEligible: true, trainingTypes: "strength",
                modalities: "other", imageName: "Seated_Head_Harness_Neck_Resistance", level: "intermediate", instructionCount: 6),
        Fixture(name: "Skating", category: "cardio", equipment: "", force: "",
                mechanics: "compound", lateral: false, primary: "quadriceps", secondary: "abductors|adductors|calves|glutes|hamstrings",
                stabilizers: "", volumeEligible: false, trainingTypes: "cardio",
                modalities: "other", imageName: "Skating", level: "intermediate", instructionCount: 2),
        Fixture(name: "Squat Jerk", category: "legs", equipment: "barbell", force: "push",
                mechanics: "compound", lateral: false, primary: "quadriceps|glutes", secondary: "adductors",
                stabilizers: "lower_back|hamstrings|calves", volumeEligible: true, trainingTypes: "strength",
                modalities: "free_weight", imageName: "Squat_Jerk", level: "expert", instructionCount: 3),
        Fixture(name: "Standing Pelvic Tilt", category: "pull", equipment: "", force: "static",
                mechanics: "isolation", lateral: false, primary: "lower_back", secondary: "glutes",
                stabilizers: "", volumeEligible: false, trainingTypes: "stretching",
                modalities: "other", imageName: "Standing_Pelvic_Tilt", level: "beginner", instructionCount: 3),
        Fixture(name: "Triceps Pushdown - V-Bar Attachment", category: "push", equipment: "cable", force: "push",
                mechanics: "isolation", lateral: false, primary: "triceps", secondary: "",
                stabilizers: "", volumeEligible: true, trainingTypes: "strength",
                modalities: "cable", imageName: "Triceps_Pushdown_-_V-Bar_Attachment", level: "beginner", instructionCount: 5),
        Fixture(name: "Zottman Preacher Curl", category: "pull", equipment: "dumbbell", force: "pull",
                mechanics: "isolation", lateral: false, primary: "biceps", secondary: "forearms",
                stabilizers: "", volumeEligible: true, trainingTypes: "strength",
                modalities: "free_weight", imageName: "Zottman_Preacher_Curl", level: "intermediate", instructionCount: 6),
    ]

    func testTemplateCount() {
        XCTAssertEqual(ImportedExerciseLibrary.templates.count, 873)
    }

    func testSampledTemplatesMatchTheAnnotation() throws {
        let byName = Dictionary(ImportedExerciseLibrary.templates.map { ($0.name, $0) },
                                uniquingKeysWith: { a, _ in a })
        for expected in Self.fixtures {
            let actual = try XCTUnwrap(byName[expected.name], "missing template \(expected.name)")
            XCTAssertEqual(actual.category.rawValue, expected.category, expected.name)
            XCTAssertEqual(actual.equipment?.rawValue ?? "", expected.equipment, expected.name)
            XCTAssertEqual(actual.force?.rawValue ?? "", expected.force, expected.name)
            XCTAssertEqual(actual.mechanics.rawValue, expected.mechanics, expected.name)
            XCTAssertEqual(actual.isLateral, expected.lateral, expected.name)
            XCTAssertEqual(actual.primaryMuscles.joined(separator: "|"), expected.primary, expected.name)
            XCTAssertEqual(actual.secondaryMuscles.joined(separator: "|"), expected.secondary, expected.name)
            XCTAssertEqual(actual.stabilizerMuscles.map(\.rawValue).joined(separator: "|"),
                           expected.stabilizers, expected.name)
            XCTAssertEqual(actual.volumeEligible, expected.volumeEligible, expected.name)
            XCTAssertEqual(actual.trainingTypes.map(\.rawValue).joined(separator: "|"),
                           expected.trainingTypes, expected.name)
            XCTAssertEqual(actual.modalities.map(\.rawValue).joined(separator: "|"),
                           expected.modalities, expected.name)
            XCTAssertEqual(actual.imageName ?? "", expected.imageName, expected.name)
            XCTAssertEqual(actual.level ?? "", expected.level, expected.name)
            XCTAssertEqual(actual.instructions.count, expected.instructionCount, expected.name)
        }
    }

    /// Order is what keeps the curated/imported merge stable across launches.
    func testTemplateOrderFollowsSortedExerciseIDs() {
        let templateNames = ImportedExerciseLibrary.templates.map(\.name)
        let expected = TrainingEngineBridge.exerciseRecords
            .compactMap { ImportedExerciseLibrary.template(from: $0)?.name }
        XCTAssertEqual(templateNames, expected)
    }

    /// The specific attributions the old hand-mapping got wrong. Each of these was
    /// verified against the DB++ annotation and its cited literature.
    func testAnnotationCorrectsTheOldHandMapping() throws {
        let byName = Dictionary(ImportedExerciseLibrary.templates.map { ($0.name, $0) },
                                uniquingKeysWith: { a, _ in a })

        // Was primary "hamstrings" — a snatch is not a hamstring movement.
        let snatch = try XCTUnwrap(byName["Power Snatch"])
        XCTAssertEqual(snatch.directMuscles, [.quadriceps, .glutes, .traps])
        XCTAssertEqual(snatch.trainingTypes, [.strength, .olympicWeightlifting])

        // Was primary "traps": upstream `neck` used to be folded into traps because
        // our old catalog had no neck. DB++ does.
        let neck = try XCTUnwrap(byName["Seated Head Harness Neck Resistance"])
        XCTAssertEqual(neck.directMuscles, [.neck])

        // Was primary "triceps" only; the chest is a prime mover in a floor press.
        let floorPress = try XCTUnwrap(byName["Floor Press"])
        XCTAssertEqual(floorPress.directMuscles, [.triceps, .chest])
        XCTAssertEqual(floorPress.trainingTypes, [.strength, .powerlifting])

        // Hamstrings and calves were credited as secondary work in a lunge. They
        // stabilise; they no longer earn half a set each.
        let lunge = try XCTUnwrap(byName["Dumbbell Lunges"])
        XCTAssertEqual(lunge.directMuscles, [.quadriceps, .glutes])
        XCTAssertEqual(lunge.indirectMuscles, [.adductors])
        XCTAssertTrue(lunge.stabilizerMuscles.contains(.hamstrings))
        XCTAssertEqual(lunge.volumeCredits[.hamstrings], nil)
    }

    /// Volume eligibility is what stops a stretch inflating the weekly set count.
    func testNonVolumeMovementsKeepTheirMusclesButEarnNoCredit() throws {
        let stretches = ImportedExerciseLibrary.templates.filter {
            $0.trainingTypes.contains(.stretching)
        }
        XCTAssertEqual(stretches.count, 123)
        for stretch in stretches {
            XCTAssertFalse(stretch.volumeEligible, stretch.name)
            XCTAssertTrue(stretch.directMuscles.isEmpty, stretch.name)
            XCTAssertFalse(stretch.primaryMuscles.isEmpty,
                           "\(stretch.name) must stay browsable by muscle")
            XCTAssertTrue(stretch.volumeCredits.isEmpty, stretch.name)
        }
        XCTAssertEqual(ImportedExerciseLibrary.templates.filter(\.volumeEligible).count, 673)
    }

    /// No template may carry a muscle string the volume engine cannot resolve.
    func testEveryTemplateMuscleIsCanonical() {
        for template in ImportedExerciseLibrary.templates + ExerciseLibrary.starter {
            for id in template.primaryMuscles + template.secondaryMuscles {
                XCTAssertNotNil(MuscleGroup(rawValue: id),
                                "\(template.name) carries non-canonical muscle id \(id)")
            }
            XCTAssertTrue(Set(template.primaryMuscles).isDisjoint(with: Set(template.secondaryMuscles)),
                          "\(template.name) repeats a muscle across primary/secondary")
        }
    }
}
