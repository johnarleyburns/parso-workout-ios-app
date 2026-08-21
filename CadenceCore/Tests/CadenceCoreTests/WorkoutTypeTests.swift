import XCTest
@testable import CadenceCore

final class WorkoutTypeTests: XCTestCase {

    // MARK: WorkoutType.rowing (field-test batch 2026-08-20 P8)

    func testRowingWorkoutTypePresent() {
        XCTAssertTrue(WorkoutType.allCases.contains(.rowing))
    }

    func testRowingDisplayNameAndSymbol() {
        XCTAssertEqual(WorkoutType.rowing.displayName, "Rowing")
        XCTAssertEqual(WorkoutType.rowing.symbol, "figure.rower")
    }

    func testRowingUsesGPS() {
        // Decision D1 (Option A): Rowing is a GPS box like Cycle.
        XCTAssertTrue(WorkoutType.rowing.usesGPS)
    }

    func testRowingMapsToCardioType() {
        XCTAssertEqual(WorkoutType.rowing.cardioType, .rowing)
    }

    func testRowingIsNotStrength() {
        XCTAssertFalse(WorkoutType.rowing.isStrength)
    }

    // MARK: CardioDistanceKind

    func testCardioDistanceKindRowing() {
        XCTAssertEqual(CardioType.rowing.distanceKind, .rowing)
    }

    func testCardioDistanceKindExistingTypes() {
        XCTAssertEqual(CardioType.run.distanceKind, .walkingRunning)
        XCTAssertEqual(CardioType.walk.distanceKind, .walkingRunning)
        XCTAssertEqual(CardioType.cycle.distanceKind, .cycling)
        XCTAssertEqual(CardioType.swim.distanceKind, .swimming)
        XCTAssertEqual(CardioType.boxing.distanceKind, .walkingRunning)
        XCTAssertEqual(CardioType.hiit.distanceKind, .walkingRunning)
        XCTAssertEqual(CardioType.other.distanceKind, .walkingRunning)
    }

    // MARK: CardioType model facts the boxes rely on

    func testRowingSymbolIsFigureRower() {
        XCTAssertEqual(CardioType.rowing.symbol, "figure.rower")
    }

    func testRowingDisplayName() {
        XCTAssertEqual(CardioType.rowing.displayName, "Rowing")
    }

    func testRowingUsesGPSLikeCycle() {
        XCTAssertTrue(CardioType.rowing.usesGPS)
        XCTAssertTrue(CardioType.cycle.usesGPS)
    }
}
