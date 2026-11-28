#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchStrengthPreviewSetupTests {
    @Test func suggestedPreviewSeedsTargetsAndKeepsThemThroughStart() {
        let source = WatchLiftLaunch(title: "Personalized", exerciseNames: ["Squat"], repLadder: [],
            planPayload: .init(strength: .init(exerciseNames: ["Squat"], prescriptions: [
                .init(exerciseName: "Squat", sets: (0..<3).map { _ in .init(targetReps: 6) })])))
        let prepared = WatchStrengthPreviewSetup.prefilledSuggestion(source) { _ in
            PartnerPlanResolver.ExerciseHistory(lastSets: [.init(weightKg: 90, reps: 8)])
        }
        let setup = WatchStrengthPreviewSetup(launch: prepared)
        let started = setup.preparedLaunch(from: prepared)
        #expect(started.planPayload?.strength?.prescriptions.first?.sets.map(\.targetReps) == [8, 8, 8])
        #expect(started.planPayload?.strength?.prescriptions.first?.sets.map(\.targetWeightKg) == [90, 90, 90])
        #expect(source.planPayload?.strength?.prescriptions.first?.sets.first?.targetWeightKg == nil)
    }

    @Test func repDefaultsReplaceEveryExercisePrescriptionWithoutChangingLoadsOrSource() {
        let prescriptions = ["Squat", "Row"].map {
            PlannedExercisePrescription(exerciseName: $0, sets: [.init(targetReps: 8, targetWeightKg: 25)])
        }
        let source = WatchLiftLaunch(title: "Personalized Strength", exerciseNames: ["Squat", "Row"], repLadder: [8],
            planPayload: .init(strength: .init(exerciseNames: ["Squat", "Row"], prescriptions: prescriptions)))
        var setup = WatchStrengthPreviewSetup(launch: source)
        setup.repOverride = [12, 10, 8]
        setup.partnerNames = [" Sam ", "sam", "Jo"]
        let prepared = setup.preparedLaunch(from: source)
        #expect(prepared.repLadder == [12, 10, 8])
        #expect(prepared.planPayload?.strength?.prescriptions.map { $0.sets.map(\.targetReps) } == [[12, 10, 8], [12, 10, 8]])
        #expect(prepared.planPayload?.strength?.prescriptions[0].sets.map(\.targetWeightKg) == [25, 25, 25])
        #expect(source.planPayload?.strength?.prescriptions == prescriptions)
        #expect(setup.normalizedPartnerNames == ["Sam", "Jo"])
    }

    @Test func unchangedPreviewKeepsOriginalPrescriptionAndSyncedPartners() {
        let source = WatchLiftLaunch(title: "Previous", exerciseNames: ["Squat"], repLadder: [5, 3, 1],
            planPayload: .init(strength: .init(performers: [.owner(), .init(id: "sam-id", displayName: "Sam", isOwner: false)])))
        let setup = WatchStrengthPreviewSetup(launch: source)
        #expect(setup.partnerNames == ["Sam"])
        #expect(setup.preparedLaunch(from: source) == source)
        var solo = setup
        solo.partnerNames = []
        #expect(solo.preparedLaunch(from: source).planPayload?.strength?.performers == nil)
    }

    @Test func emptyCustomPlanBuildsDefaultsForExercisesAddedAfterStart() {
        let source = WatchLiftLaunch(title: "Custom", exerciseNames: [], repLadder: [])
        var setup = WatchStrengthPreviewSetup(launch: source)
        setup.repOverride = [10, 8]
        let launch = setup.preparedLaunch(from: source)
        #expect(WatchStrengthPreviewSetup.customDefaultPrescription(for: "Squat", payload: launch.planPayload)?
            .sets.map(\.targetReps) == [10, 8])
        #expect(WatchStrengthPreviewSetup.customDefaultPrescription(for: "Squat", payload: nil) == nil)
    }

    @Test func customWorkoutReceivesRepDefaultsAndPartnersBeforeSessionStarts() throws {
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
        #expect(model.partners.map(\.name) == ["Sam"])
        #expect(model.addExercise(named: "Squat") == .added(name: "Squat"))
        let exercise = try #require(model.exerciseList.first?.exercise)
        model.startLogSet(for: exercise)
        #expect(model.currentReps == 10)
        #expect(model.plannedWorkingSets(for: exercise).map(\.targetReps) == [10, 8])
    }
}
#endif
