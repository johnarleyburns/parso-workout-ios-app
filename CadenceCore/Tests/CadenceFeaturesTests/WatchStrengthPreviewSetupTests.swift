import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

final class WatchStrengthPreviewSetupTests: XCTestCase {
    func testRepDefaultsReplaceEveryExercisePrescriptionWithoutChangingLoadsOrSource() {
        let prescriptions = ["Squat", "Row"].map {
            PlannedExercisePrescription(exerciseName: $0, sets: [.init(targetReps: 8, targetWeightKg: 25)])
        }
        let source = WatchLiftLaunch(title: "Personalized Strength", exerciseNames: ["Squat", "Row"], repLadder: [8],
            planPayload: .init(strength: .init(exerciseNames: ["Squat", "Row"], prescriptions: prescriptions)))
        var setup = WatchStrengthPreviewSetup(launch: source)
        setup.repOverride = [12, 10, 8]
        setup.partnerNames = [" Sam ", "sam", "Jo"]
        let prepared = setup.preparedLaunch(from: source)
        XCTAssertEqual(prepared.repLadder, [12, 10, 8])
        XCTAssertEqual(prepared.planPayload?.strength?.prescriptions.map { $0.sets.map(\.targetReps) }, [[12, 10, 8], [12, 10, 8]])
        XCTAssertEqual(prepared.planPayload?.strength?.prescriptions[0].sets.map(\.targetWeightKg), [25, 25, 25])
        XCTAssertEqual(source.planPayload?.strength?.prescriptions, prescriptions)
        XCTAssertEqual(setup.normalizedPartnerNames, ["Sam", "Jo"])
    }

    func testUnchangedPreviewKeepsOriginalPrescriptionAndSyncedPartners() {
        let source = WatchLiftLaunch(title: "Previous", exerciseNames: ["Squat"], repLadder: [5, 3, 1],
            planPayload: .init(strength: .init(performers: [.owner(), .init(id: "sam-id", displayName: "Sam", isOwner: false)])))
        let setup = WatchStrengthPreviewSetup(launch: source)
        XCTAssertEqual(setup.partnerNames, ["Sam"])
        XCTAssertEqual(setup.preparedLaunch(from: source), source)
        var solo = setup
        solo.partnerNames = []
        XCTAssertNil(solo.preparedLaunch(from: source).planPayload?.strength?.performers)
    }

    func testEmptyCustomPlanBuildsDefaultsForExercisesAddedAfterStart() {
        let source = WatchLiftLaunch(title: "Custom", exerciseNames: [], repLadder: [])
        var setup = WatchStrengthPreviewSetup(launch: source)
        setup.repOverride = [10, 8]
        let launch = setup.preparedLaunch(from: source)
        XCTAssertEqual(WatchStrengthPreviewSetup.customDefaultPrescription(for: "Squat", payload: launch.planPayload)?
            .sets.map(\.targetReps), [10, 8])
        XCTAssertNil(WatchStrengthPreviewSetup.customDefaultPrescription(for: "Squat", payload: nil))
    }

    func testCustomWorkoutReceivesRepDefaultsAndPartnersBeforeSessionStarts() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let model = WatchStrengthFlowModel(context: ModelContext(container), cooldownDefault: 0, restDefault: 60)
        let source = WatchLiftLaunch(title: "Custom", exerciseNames: [], repLadder: [])
        var setup = WatchStrengthPreviewSetup(launch: source)
        setup.repOverride = [10, 8]
        setup.partnerNames = ["Sam"]
        let launch = setup.preparedLaunch(from: source)
        model.start(title: launch.title, plannedExerciseNames: launch.exerciseNames,
                    repLadder: launch.repLadder, planPayload: launch.planPayload,
                    initialPartnerNames: setup.normalizedPartnerNames, createSession: true)
        XCTAssertEqual(model.partners.map(\.name), ["Sam"])
        XCTAssertEqual(model.addExercise(named: "Squat"), .added(name: "Squat"))
        let exercise = try XCTUnwrap(model.exerciseList.first?.exercise)
        model.startLogSet(for: exercise)
        XCTAssertEqual(model.currentReps, 10)
        XCTAssertEqual(model.plannedWorkingSets(for: exercise).map(\.targetReps), [10, 8])
    }
}
