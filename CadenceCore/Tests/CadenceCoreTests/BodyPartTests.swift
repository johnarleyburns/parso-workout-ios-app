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
}
