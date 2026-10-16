import XCTest
import CadenceCore
@testable import CadenceFeatures

final class CoachWatchTodayBridgeTests: XCTestCase {
    private func session(_ id: String, _ payload: CoachSession.LaunchPayload,
                         exercises: [CoachSession.RecommendedExercise]? = nil) -> CoachSession {
        CoachSession(id: id, kind: .moderateAerobic, title: "Boxing conditioning", subtitle: "",
                     durationMinutes: 25, exercises: exercises, modality: nil, intensity: nil,
                     trainingLoadTags: [], citationIds: [], launchPayload: payload,
                     systemsTrained: [], evidenceCategory: nil)
    }

    func testCardioSuggestionProjectsToWatch() throws {
        let s = try XCTUnwrap(CoachWatchTodayBridge.watchSession(
            from: session("box", .cardio(type: "boxing", durationMinutes: 25))))
        XCTAssertEqual(s.kind, .cardio)
        XCTAssertEqual(s.label, "Boxing conditioning")
        XCTAssertEqual(s.cardioType, "boxing")
        XCTAssertEqual(s.durationMinutes, 25)
    }

    func testStrengthSuggestionCarriesExerciseNames() throws {
        let s = try XCTUnwrap(CoachWatchTodayBridge.watchSession(
            from: session("str", .strengthPlan("p"), exercises: [.init(name: "Bench Press")])))
        XCTAssertEqual(s.kind, .strength)
        XCTAssertEqual(s.exerciseNames, ["Bench Press"])
    }

    func testAssessmentIsNotProjected() {
        XCTAssertNil(CoachWatchTodayBridge.watchSession(from: session("a", .assessment)))
    }
}
