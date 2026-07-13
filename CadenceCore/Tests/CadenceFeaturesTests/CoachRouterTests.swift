import XCTest
import CadenceCore
import CadenceFeatures

final class CoachRouterTests: XCTestCase {

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
    func testStrengthWithExercisesOpensPlanEditor() {
        let ex = CoachSession.RecommendedExercise(name: "Bench Press", sets: 3, repsLow: 8, loadKg: 60)
        let route = CoachRouter.destination(for: strengthSession(exercises: [ex]))
        guard case .planEditor = route else { return XCTFail("expected planEditor, got \(route)") }
    }

    func testStrengthWithoutExercisesOpensEmptyEditorNeverRecorder() {
        let route = CoachRouter.destination(for: strengthSession(exercises: nil))
        XCTAssertEqual(route, .emptyEditor(title: "Upper"))
    }

    func testEveryStrengthKindRoutesToAnEditor() {
        for exercises in [nil, [CoachSession.RecommendedExercise(name: "Squat", sets: 3, repsLow: 5, loadKg: 100)]] {
            let route = CoachRouter.destination(for: strengthSession(exercises: exercises))
            switch route {
            case .planEditor, .emptyEditor: break
            default: XCTFail("strength must route to an editor, got \(route)")
            }
        }
    }

    func testCardioModalitiesRoute() {
        XCTAssertEqual(CoachRouter.destination(for: cardioSession(type: "walk")), .outdoorCardio(.walk))
        XCTAssertEqual(CoachRouter.destination(for: cardioSession(type: "run")), .outdoorCardio(.run))
        XCTAssertEqual(CoachRouter.destination(for: cardioSession(type: "cycle")), .outdoorCardio(.cycle))
        XCTAssertEqual(CoachRouter.destination(for: cardioSession(type: "swim")), .swim)
        XCTAssertEqual(CoachRouter.destination(for: cardioSession(type: "hiit")), .interval(.hiit))
        XCTAssertEqual(CoachRouter.destination(for: cardioSession(type: "boxing")), .interval(.boxing))
        XCTAssertEqual(CoachRouter.destination(for: cardioSession(type: "rowing", minutes: 20)),
                       .timerCardio(type: .rowing, suggestedMinutes: 20))
        XCTAssertEqual(CoachRouter.destination(for: cardioSession(type: "elliptical", minutes: 25)),
                       .timerCardio(type: .other, suggestedMinutes: 25))
    }

    func testRecoveryAndRestRouteToNone() {
        let rest = CoachSession(id: "r", kind: .rest, title: "Rest", launchPayload: .rest)
        XCTAssertEqual(CoachRouter.destination(for: rest), CoachRoute.none)
    }

    func testAddOnAction() {
        XCTAssertEqual(CoachRouter.addOnAction(status: .encouraged), .launch)
        XCTAssertEqual(CoachRouter.addOnAction(status: .neutral), .launch)
        XCTAssertEqual(CoachRouter.addOnAction(status: .warn), .warn)
    }
}
