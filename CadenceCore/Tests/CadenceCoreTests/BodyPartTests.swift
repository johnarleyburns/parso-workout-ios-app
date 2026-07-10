import XCTest
@testable import CadenceCore

/// feedback batch 3 — body-part coverage for Home's "body parts this week" tile.
final class BodyPartTests: XCTestCase {

    func testEightPartsWithShouldersNotNeck() {
        XCTAssertEqual(BodyPart.allCases.count, 8)
        XCTAssertTrue(BodyPart.allCases.contains(.shoulders))
        // "neck" was swapped out — it isn't a case.
        XCTAssertNil(BodyPart(rawValue: "neck"))
    }

    func testMuscleMapping() {
        XCTAssertEqual(BodyPart.parts(forMuscleIDs: ["chest", "triceps", "front-delts"]),
                       [.chest, .triceps, .shoulders])
        XCTAssertEqual(BodyPart.parts(forMuscleIDs: ["quads", "glutes"]), [.legs])
        XCTAssertEqual(BodyPart.parts(forMuscleIDs: ["lats", "rhomboids"]), [.back])
        XCTAssertEqual(BodyPart.parts(forMuscleIDs: ["calves"]), [.calves])
        // Forearms map to no coarse part.
        XCTAssertTrue(BodyPart.parts(forMuscleIDs: ["forearms"]).isEmpty)
    }

    func testCoverageReportsHitAndMissingInOrder() {
        // A push day: chest + shoulders + triceps hit; the rest missing.
        let lists = [["chest", "triceps", "front-delts"], ["delts"]]
        let (hit, missing) = BodyPart.coverage(forMuscleLists: lists)
        XCTAssertEqual(hit, [.chest, .shoulders, .triceps])
        XCTAssertEqual(missing, [.legs, .back, .biceps, .calves, .abs])
    }

    func testFullCoverageLeavesNothingMissing() {
        let lists = BodyPart.allCases.map { part -> [String] in
            switch part {
            case .legs: return ["quads"]
            case .back: return ["lats"]
            case .chest: return ["chest"]
            case .shoulders: return ["delts"]
            case .biceps: return ["biceps"]
            case .triceps: return ["triceps"]
            case .calves: return ["calves"]
            case .abs: return ["abs"]
            }
        }
        let (hit, missing) = BodyPart.coverage(forMuscleLists: lists)
        XCTAssertEqual(hit.count, 8)
        XCTAssertTrue(missing.isEmpty)
    }

    func testPartsForCategory() {
        XCTAssertEqual(BodyPart.parts(forCategory: .push), [.chest, .shoulders, .triceps])
        XCTAssertEqual(BodyPart.parts(forCategory: .pull), [.back, .biceps])
        XCTAssertEqual(BodyPart.parts(forCategory: .legs), [.legs, .calves])
        XCTAssertEqual(BodyPart.parts(forCategory: .core), [.abs])
        XCTAssertTrue(BodyPart.parts(forCategory: .cardio).isEmpty)
        XCTAssertTrue(BodyPart.parts(forCategory: .other).isEmpty)
    }

    func testDefaultMusclesForCategory() {
        XCTAssertFalse(BodyPart.defaultMuscles(forCategory: .push).isEmpty)
        XCTAssertFalse(BodyPart.defaultMuscles(forCategory: .pull).isEmpty)
        XCTAssertFalse(BodyPart.defaultMuscles(forCategory: .legs).isEmpty)
        XCTAssertFalse(BodyPart.defaultMuscles(forCategory: .core).isEmpty)
        XCTAssertTrue(BodyPart.defaultMuscles(forCategory: .cardio).isEmpty)
    }

    func testGuessCategory() {
        XCTAssertEqual(BodyPart.guessCategory(from: "Bench Press"), .push)
        XCTAssertEqual(BodyPart.guessCategory(from: "Triceps Extension"), .push)
        XCTAssertEqual(BodyPart.guessCategory(from: "Bicep Curl"), .pull)
        XCTAssertEqual(BodyPart.guessCategory(from: "Lat Pulldown"), .pull)
        XCTAssertEqual(BodyPart.guessCategory(from: "Back Squat"), .legs)
        XCTAssertEqual(BodyPart.guessCategory(from: "Romanian Deadlift"), .legs)
        XCTAssertEqual(BodyPart.guessCategory(from: "Crunches"), .core)
        XCTAssertEqual(BodyPart.guessCategory(from: "rotary torso"), .core)
        XCTAssertNil(BodyPart.guessCategory(from: "xyzzy"))
    }
}
