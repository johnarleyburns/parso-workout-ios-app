import Testing
@testable import CadenceFeatures

struct WorkoutDockPresenterTests {
    @Test func pauseAndResumeContent() {
        #expect(WorkoutDockPresenter.pauseContent(isPaused: false)
            == .init(title: "Pause", systemImage: "pause.fill"))
        #expect(WorkoutDockPresenter.pauseContent(isPaused: true)
            == .init(title: "Resume", systemImage: "play.fill"))
        #expect(WorkoutDockPresenter.endSystemImage == "stop.fill")
    }

    @Test func layoutFollowsDynamicType() {
        #expect(WorkoutDockLayout.resolve(isAccessibilitySize: false) == .horizontal)
        #expect(WorkoutDockLayout.resolve(isAccessibilitySize: true) == .vertical)
    }

    @Test func primaryDockHasOnlyPauseThenEnd() {
        for prefix in ["workout", "outdoor", "record", "interval", "swim"] {
            #expect(WorkoutDockPresenter.primaryActionIds(idPrefix: prefix)
                == ["\(prefix).pause", "\(prefix).end"])
        }
        #expect(WorkoutDockPresenter.minimumTargetHeight >= 56)
    }

    @Test func coolDownOnlyInConfirmationWhenSupplied() {
        #expect(WorkoutDockPresenter.confirmationActionIds(hasCoolDown: true)
            == ["workout.endCoolDown", "workout.endConfirm", "workout.endCancel"])
        #expect(WorkoutDockPresenter.confirmationActionIds(hasCoolDown: false)
            == ["workout.endConfirm", "workout.endCancel"])
    }
}
