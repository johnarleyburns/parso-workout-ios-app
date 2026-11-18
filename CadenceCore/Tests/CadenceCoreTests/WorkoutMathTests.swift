import Testing
@testable import CadenceCore

struct WorkoutMathTests {

    @Test func epleyAtSingleRepEqualsWeight() {
        #expect(abs(WorkoutMath.epley1RM(weight: 100, reps: 1) - 100) <= 0.0001)
    }

    @Test func epleyMultiRep() {
        // 100 * (1 + 5/30) = 116.6667
        #expect(abs(WorkoutMath.epley1RM(weight: 100, reps: 5) - 116.6667) <= 0.001)
    }

    @Test func epleyZeroOrNegativeRepsIsZero() {
        #expect(WorkoutMath.epley1RM(weight: 100, reps: 0) == 0)
        #expect(WorkoutMath.epley1RM(weight: 100, reps: -3) == 0)
    }

    @Test func brzyckiSingleRep() {
        #expect(abs(WorkoutMath.brzycki1RM(weight: 100, reps: 1) - 100) <= 0.0001)
    }

    @Test func brzyckiMultiRep() {
        // 100 / (1.0278 - 0.0278*5) = 112.512
        #expect(abs(WorkoutMath.brzycki1RM(weight: 100, reps: 5) - 112.512) <= 0.01)
    }

    @Test func brzyckiDegenerateHighReps() {
        #expect(WorkoutMath.brzycki1RM(weight: 100, reps: 40) > 0)
    }

    @Test func estimated1RMDispatch() {
        #expect(WorkoutMath.estimated1RM(weight: 100, reps: 5, formula: .epley) ==
                       WorkoutMath.epley1RM(weight: 100, reps: 5))
        #expect(WorkoutMath.estimated1RM(weight: 100, reps: 5, formula: .brzycki) ==
                       WorkoutMath.brzycki1RM(weight: 100, reps: 5))
    }

    @Test func volume() {
        #expect(abs(WorkoutMath.volume(weight: 102.5, reps: 5) - 512.5) <= 0.0001)
        #expect(WorkoutMath.volume(weight: 100, reps: -1) == 0)
    }

    @Test func unitConversionRoundTrip() {
        let kg = 102.5
        let lb = WorkoutMath.kgToLb(kg)
        #expect(abs(WorkoutMath.lbToKg(lb) - kg) <= 1e-9)
        #expect(abs(lb - 225.97) <= 0.01)
    }

    @Test func displayAndCanonical() {
        #expect(WorkoutMath.display(100, in: .kilograms) == 100)
        #expect(abs(WorkoutMath.display(100, in: .pounds) - 220.46) <= 0.01)
        #expect(abs(WorkoutMath.canonical(220.462, from: .pounds) - 100) <= 0.01)
        #expect(WorkoutMath.canonical(100, from: .kilograms) == 100)
    }
}
