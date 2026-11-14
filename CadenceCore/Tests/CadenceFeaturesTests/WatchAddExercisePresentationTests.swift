import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchAddExercisePresentationTests: XCTestCase {

    func testMuscleGroupPolicyShowsEveryCanonicalGroup() {
        XCTAssertEqual(WatchAddExercisePresentation.muscleGroupSectionTitle, "Muscle groups")
        let groups = WatchAddExercisePresentation.visibleMuscleGroups
        XCTAssertEqual(groups, MuscleGroup.canonicalOrder)
        XCTAssertEqual(Set(groups).count, groups.count)
        for group in [MuscleGroup.neck, .rotatorCuff, .hipFlexors, .tibialis] {
            XCTAssertTrue(groups.contains(group))
        }
        XCTAssertFalse(WatchAddExercisePresentation.offersMoreMuscles)
        XCTAssertFalse(WatchAddExercisePresentation.offersRecentExercises)
    }

    func testResultRowReservesTwoLinesAndOpensPreview() {
        let name = "Barbell Romanian Deadlift With Extra Long Descriptive Suffix"
        XCTAssertEqual(WatchAddExercisePresentation.rowTitle(for: name), name)
        XCTAssertEqual(WatchAddExercisePresentation.exerciseNameMaxLines, 2)
        XCTAssertFalse(WatchAddExercisePresentation.usesMarqueeForNames)
        XCTAssertEqual(WatchAddExercisePresentation.rowAction, .openPreview)
        XCTAssertNotEqual(WatchAddExercisePresentation.rowAction, .addImmediately)
        XCTAssertTrue(WatchAddExercisePresentation.rowAccessibilityLabel(for: name).contains(name))
        XCTAssertTrue(WatchAddExercisePresentation.rowAccessibilityHint.lowercased().contains("before adding"))
    }

    func testPreviewDetailToggleAndLayout() {
        XCTAssertEqual(WatchAddExercisePresentation.detailToggleTitle(isExpanded: false), "Show detail")
        XCTAssertEqual(WatchAddExercisePresentation.detailToggleTitle(isExpanded: true), "Hide detail")
        XCTAssertEqual(WatchAddExercisePresentation.detailPlacement, .belowActions)
        XCTAssertEqual(WatchAddExercisePresentation.backTreatment, .leadingChevronOnly)
        XCTAssertEqual(WatchAddExercisePresentation.backAccessibilityLabel, "Back to exercises")
        XCTAssertGreaterThanOrEqual(WatchAddExercisePresentation.minimumTouchHeight, 44)
    }
}
