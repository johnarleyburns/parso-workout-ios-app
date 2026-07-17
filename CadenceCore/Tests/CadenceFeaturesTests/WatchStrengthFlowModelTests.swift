import XCTest
import SwiftData
@testable import CadenceFeatures
import CadenceCore

final class WatchStrengthFlowModelTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try CadenceStore.makeModelContainer(inMemory: true)
        context = ModelContext(container)
        _ = try WorkoutRepository.seedStarterLibraryIfNeeded(context)
    }

    override func tearDown() {
        container = nil
        context = nil
    }

    func makeModel() -> WatchStrengthFlowModel {
        WatchStrengthFlowModel(context: context, unit: .kilograms, cooldownDefault: 5, restDefault: 90)
    }

    func simpleExercise(named name: String) -> Exercise {
        try! WorkoutRepository.findOrCreateExercise(named: name, in: context)
    }

    // MARK: - Stage transitions

    func testStart_showsHome() {
        let m = makeModel()
        m.start()
        XCTAssertEqual(m.stage, .home)
        XCTAssertNil(m.session)
    }

    func testGoToAddExercise() {
        let m = makeModel()
        m.start()
        m.goToAddExercise()
        if case .addExercise = m.stage {} else { XCTFail("Expected addExercise stage") }
    }

    func testAddExercise_returnsToHome() {
        let m = makeModel()
        m.start()
        m.addExercise(named: "Bench Press")
        XCTAssertEqual(m.pendingExercises, ["Bench Press"])
        XCTAssertEqual(m.stage, .home)
    }

    func testLogSet_createsSessionLazily() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertNotNil(m.session)
        XCTAssertEqual(m.stage, .rest)
    }

    func testLogSet_ownerSet_countsVolume() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.currentWeight = 100; m.currentReps = 5
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertEqual(m.setCount, 1)
        XCTAssertGreaterThan(m.volume, 0)
    }

    func testWarmupSet_excludedFromVolume() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.toggleWarmup()
        m.currentWeight = 60; m.currentReps = 10
        _ = m.logSet()
        XCTAssertEqual(m.setCount, 0)
        XCTAssertEqual(m.volume, 0, accuracy: 0.1)
    }

    func testLogSetPayload_includesWarmupFlag() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.toggleWarmup()
        _ = m.logSet()
        XCTAssertEqual(m.lastSyncPayload?["is_warmup"] as? Bool, true)
    }

    func testFinish_withSets_transitionsToCooldown() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        if case .cooldown = m.stage {} else { XCTFail("Expected cooldown stage") }
    }

    func testFinish_emptySession_autoDiscards() {
        let m = makeModel()
        m.start()
        m.finish()
        XCTAssertEqual(m.stage, .discarded)
    }

    func testSkipCooldown_goesToSummary() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        m.skipCooldown()
        XCTAssertEqual(m.stage, .summary)
    }

    func testCompleteCooldown_goesToSummary() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        m.completeCooldown()
        XCTAssertEqual(m.stage, .summary)
    }

    func testCancel_beforeCreate_noDiscardPayload() {
        let m = makeModel()
        m.start()
        m.cancel()
        XCTAssertEqual(m.stage, .discarded)
        XCTAssertNil(m.discardPayload)
    }

    func testCancel_afterSync_emitsDiscardPayload() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.cancel()
        XCTAssertEqual(m.stage, .discarded)
        XCTAssertNotNil(m.discardPayload)
        XCTAssertEqual(m.discardPayload?["action"] as? String, "discard_session")
    }

    // MARK: - Partners

    func testAddPartner() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        XCTAssertEqual(m.partners.count, 1)
        XCTAssertEqual(m.partners.first?.name, "Jo")
    }

    func testPartnerRotation_afterLogSet() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertEqual(m.currentPerformerIndex, 1)
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertEqual(m.currentPerformerIndex, 2)
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertEqual(m.currentPerformerIndex, 0)
    }

    func testSelectPerformer() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        m.selectPerformer(at: 1)
        XCTAssertEqual(m.currentPerformerIndex, 1)
    }

    func testRemovePartner() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        m.removePartner(at: 0)
        XCTAssertEqual(m.partners.count, 1)
        XCTAssertEqual(m.partners.first?.name, "Sam")
    }

    func testPartnerSet_excludedFromVolume() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.currentWeight = 80; m.currentReps = 8
        m.startLogSet(for: ex); _ = m.logSet()
        m.startLogSet(for: ex); _ = m.logSet()
        m.startLogSet(for: ex); _ = m.logSet()
        XCTAssertGreaterThan(m.setCount, 0)
    }

    // MARK: - Sync payloads

    func testLogSetPayload_includesPerformedBy() {
        let m = makeModel()
        m.start()
        m.addPartner(named: "Jo")
        m.addPartner(named: "Sam")
        m.addPartner(named: "Max")
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        m.selectPerformer(at: 1)
        _ = m.logSet()
        XCTAssertEqual(m.lastPerformedByName, "Sam")
        XCTAssertNotNil(m.lastSyncPayload?["performed_by_id"])
    }

    func testLogSetPayload_includesSetId() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        XCTAssertNotNil(m.lastSyncPayload?["set_id"])
    }

    func testEndSessionPayload() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finish()
        m.skipCooldown()
        let payload = m.endSessionPayload()
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?["action"] as? String, "end_session")
    }

    func testDurationText() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.startLogSet(for: ex)
        _ = m.logSet()
        let text = m.durationText
        XCTAssertFalse(text.isEmpty)
    }

    func testPreviousSetHint() {
        let m = makeModel()
        m.start()
        let ex = try! WorkoutRepository.findOrCreateExercise(named: "TestPress", equipment: nil, in: context)
        m.currentWeight = 100; m.currentReps = 8
        m.startLogSet(for: ex)
        _ = m.logSet()
        m.finishRest()
        m.startLogSet(for: ex)
        let hint = m.previousSetHint
        XCTAssertNotNil(hint)
        XCTAssertTrue(hint!.contains("Previous:"))
    }
}
