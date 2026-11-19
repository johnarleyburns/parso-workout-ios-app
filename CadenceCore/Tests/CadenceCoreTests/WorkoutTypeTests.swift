import Testing
@testable import CadenceCore

struct WorkoutTypeTests {

    // MARK: WorkoutType.rowing (field-test batch 2026-08-20 P8)

    @Test func rowingWorkoutTypePresent() {
        #expect(WorkoutType.allCases.contains(.rowing))
    }

    @Test func rowingDisplayNameAndSymbol() {
        #expect(WorkoutType.rowing.displayName == "Rowing")
        #expect(WorkoutType.rowing.symbol == "figure.rower")
    }

    @Test func stairsDisplayNamePreservesStoredRawValue() {
        #expect(WorkoutType.stairClimber.rawValue == "stairClimber")
        #expect(WorkoutType.stairClimber.displayName == "Stairs")
        #expect(CardioType.stairClimber.displayName == "Stairs")
        #expect(CardioType(rawValue: "stairClimber") == .stairClimber)
    }

    @Test func rowingUsesGPS() {
        // Decision D1 (Option A): Rowing is a GPS box like Cycle.
        #expect(WorkoutType.rowing.usesGPS)
    }

    @Test func rowingMapsToCardioType() {
        #expect(WorkoutType.rowing.cardioType == .rowing)
    }

    @Test func rowingIsNotStrength() {
        #expect(!WorkoutType.rowing.isStrength)
    }

    // MARK: CardioDistanceKind

    @Test func cardioDistanceKindRowing() {
        #expect(CardioType.rowing.distanceKind == .rowing)
    }

    @Test func cardioDistanceKindExistingTypes() {
        #expect(CardioType.run.distanceKind == .walkingRunning)
        #expect(CardioType.walk.distanceKind == .walkingRunning)
        #expect(CardioType.cycle.distanceKind == .cycling)
        #expect(CardioType.swim.distanceKind == .swimming)
        #expect(CardioType.boxing.distanceKind == .walkingRunning)
        #expect(CardioType.hiit.distanceKind == .walkingRunning)
        #expect(CardioType.other.distanceKind == .walkingRunning)
    }

    // MARK: CardioType model facts the boxes rely on

    @Test func rowingSymbolIsFigureRower() {
        #expect(CardioType.rowing.symbol == "figure.rower")
    }

    @Test func rowingDisplayName() {
        #expect(CardioType.rowing.displayName == "Rowing")
    }

    @Test func rowingUsesGPSLikeCycle() {
        #expect(CardioType.rowing.usesGPS)
        #expect(CardioType.cycle.usesGPS)
    }
}
