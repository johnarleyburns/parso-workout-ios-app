import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchAddExercisePresentationTests {

    @Test func muscleGroupPolicyShowsEveryCanonicalGroup() {
        #expect(WatchAddExercisePresentation.muscleGroupSectionTitle == "Muscle groups")
        let groups = WatchAddExercisePresentation.visibleMuscleGroups
        #expect(groups == MuscleGroup.canonicalOrder)
        #expect(Set(groups).count == groups.count)
        for group in [MuscleGroup.neck, .rotatorCuff, .hipFlexors, .tibialis] {
            #expect(groups.contains(group))
        }
        #expect(!WatchAddExercisePresentation.offersMoreMuscles)
        #expect(!WatchAddExercisePresentation.offersRecentExercises)
    }

    @Test func resultRowReservesTwoLinesAndOpensPreview() {
        let name = "Barbell Romanian Deadlift With Extra Long Descriptive Suffix"
        #expect(WatchAddExercisePresentation.rowTitle(for: name) == name)
        #expect(WatchAddExercisePresentation.exerciseNameMaxLines == 2)
        #expect(!WatchAddExercisePresentation.usesMarqueeForNames)
        #expect(WatchAddExercisePresentation.rowAction == .openPreview)
        #expect(WatchAddExercisePresentation.rowAction != .addImmediately)
        #expect(WatchAddExercisePresentation.rowAccessibilityLabel(for: name).contains(name))
        #expect(WatchAddExercisePresentation.rowAccessibilityHint.lowercased().contains("before adding"))
    }

    @Test func previewDetailToggleAndLayout() {
        #expect(WatchAddExercisePresentation.detailToggleTitle(isExpanded: false) == "Show detail")
        #expect(WatchAddExercisePresentation.detailToggleTitle(isExpanded: true) == "Hide detail")
        #expect(WatchAddExercisePresentation.detailPlacement == .belowActions)
        #expect(WatchAddExercisePresentation.backTreatment == .leadingChevronOnly)
        #expect(WatchAddExercisePresentation.backAccessibilityLabel == "Back to exercises")
        #expect(WatchAddExercisePresentation.minimumTouchHeight >= 44)
    }
}
