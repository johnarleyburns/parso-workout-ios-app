import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct CoachRouterTests {

    private func strengthSession(exercises: [CoachSession.RecommendedExercise]?) -> CoachSession {
        CoachSession(id: "s", kind: .strength, title: "Upper",
                     exercises: exercises, launchPayload: .strengthPlan("upper"))
    }

    private func cardioSession(type: String, minutes: Int? = 30) -> CoachSession {
        CoachSession(id: "c", kind: .moderateAerobic, title: "Cardio",
                     launchPayload: .cardio(type: type, durationMinutes: minutes))
    }

    // The load-bearing rule: a strength recommendation ALWAYS routes to an editor,
    // never a live recorder.
    @Test func strengthWithExercisesOpensPlanEditor() {
        let ex = CoachSession.RecommendedExercise(name: "Bench Press", sets: 3, repsLow: 8, loadKg: 60)
        let route = CoachRouter.destination(for: strengthSession(exercises: [ex]))
        guard case .planEditor = route else {
            Issue.record("expected planEditor, got \(route)")
            return
        }
    }

    @Test func strengthWithoutExercisesOpensEmptyEditorNeverRecorder() {
        let route = CoachRouter.destination(for: strengthSession(exercises: nil))
        #expect(route == .emptyEditor(title: "Upper"))
    }

    @Test func everyStrengthKindRoutesToAnEditor() {
        for exercises in [nil, [CoachSession.RecommendedExercise(name: "Squat", sets: 3, repsLow: 5, loadKg: 100)]] {
            let route = CoachRouter.destination(for: strengthSession(exercises: exercises))
            switch route {
            case .planEditor, .emptyEditor: break
            default: Issue.record("strength must route to an editor, got \(route)")
            }
        }
    }

    @Test func cardioModalitiesRoute() {
        #expect(CoachRouter.destination(for: cardioSession(type: "walk")) == .outdoorCardio(.walk))
        #expect(CoachRouter.destination(for: cardioSession(type: "run")) == .outdoorCardio(.run))
        #expect(CoachRouter.destination(for: cardioSession(type: "cycle")) == .outdoorCardio(.cycle))
        #expect(CoachRouter.destination(for: cardioSession(type: "swim")) == .swim)
        #expect(CoachRouter.destination(for: cardioSession(type: "hiit")) == .interval(.hiit))
        #expect(CoachRouter.destination(for: cardioSession(type: "boxing")) == .interval(.boxing))
        #expect(CoachRouter.destination(for: cardioSession(type: "rowing", minutes: 20))
                       == .timerCardio(type: .rowing, suggestedMinutes: 20))
        #expect(CoachRouter.destination(for: cardioSession(type: "elliptical", minutes: 25))
                       == .timerCardio(type: .other, suggestedMinutes: 25))
    }

    @Test func recoveryAndRestRouteToNone() {
        let rest = CoachSession(id: "r", kind: .rest, title: "Rest", launchPayload: .rest)
        #expect(CoachRouter.destination(for: rest) == CoachRoute.none)
    }

    @Test func addOnAction() {
        #expect(CoachRouter.addOnAction(status: .encouraged) == .launch)
        #expect(CoachRouter.addOnAction(status: .neutral) == .launch)
        #expect(CoachRouter.addOnAction(status: .warn) == .warn)
    }
}
