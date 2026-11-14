import Testing
@testable import CadenceFeatures

@Suite struct WatchWorkoutExerciseRowPresentationTests {
    private let name = "Incline Dumbbell Press"

    @Test func plannedProgress() {
        let p = WatchWorkoutExerciseRowPresentation(exerciseName: name, completedSetCount: 2, plannedSetCount: 3)
        #expect(p.completedSetCount == 2)
        #expect(p.isPlanned)
        #expect(abs(p.progress - 2.0 / 3.0) < 0.0001)
        #expect(!p.showsTextualProgressDetail)
        #expect(p.exerciseNameMaxLines == 2)
        #expect(WatchWorkoutExerciseRowPresentation.exerciseNameMaxLines == 2)
        #expect(p.accessibilityLabel == "Incline Dumbbell Press, 2 of 3 sets complete")
    }

    @Test func completeAndOverComplete() {
        let full = WatchWorkoutExerciseRowPresentation(exerciseName: name, completedSetCount: 3, plannedSetCount: 3)
        #expect(full.progress == 1)
        #expect(full.completedSetCount == 3)
        let over = WatchWorkoutExerciseRowPresentation(exerciseName: name, completedSetCount: 5, plannedSetCount: 3)
        #expect(over.progress == 1)
        #expect(over.completedSetCount == 5)
        #expect(over.accessibilityLabel.hasSuffix("5 of 3 sets complete"))
    }

    @Test func unplanned() {
        for (done, planned) in [(0, Int?.none), (2, 0)] {
            let p = WatchWorkoutExerciseRowPresentation(exerciseName: name, completedSetCount: done, plannedSetCount: planned)
            #expect(!p.isPlanned)
            #expect(p.progress == 0)
            #expect(p.completedSetCount == done)
            #expect(p.accessibilityLabel == "\(name), \(done) sets logged")
        }
    }

    @Test func defensiveAndVerbatimName() {
        let p = WatchWorkoutExerciseRowPresentation(exerciseName: name, completedSetCount: -4, plannedSetCount: -2)
        #expect(p.completedSetCount == 0)
        #expect(p.progress == 0)
        #expect(!p.isPlanned)
        #expect(p.accessibilityLabel == "\(name), 0 sets logged")
        let long = "Single-Arm Landmine Romanian Deadlift With Pause And Tempo"
        let l = WatchWorkoutExerciseRowPresentation(exerciseName: long, completedSetCount: 1, plannedSetCount: 3)
        #expect(l.exerciseName == long)
        #expect(l.accessibilityLabel.hasPrefix(long + ","))
        #expect(!l.accessibilityLabel.contains("…"))
    }
}
