import XCTest
@testable import CadenceCore

final class UnifiedPlanCoachApplyTests: XCTestCase {
    func testApplyingProgressionBumpsRevisionAndRecordsAssistance() throws {
        let current = PrescribedSet(id: UUID(), setIndex: 0, repTarget: .exact(8),
                                    load: .absoluteWeight(value: 80, unit: .kg))
        let proposed = PrescribedSet(id: current.id, setIndex: 0, repTarget: .exact(8),
                                     load: .absoluteWeight(value: 82, unit: .kg))
        let plan = plan(with: [current])
        let item = try XCTUnwrap(plan.weeks[0].days[0].sessions[0].items.first)
        let itemID = item.id
        let sessionID = plan.weeks[0].days[0].sessions[0].id
        let proposal = UnifiedPlanProgressionProposal(
            id: "progress|test", sessionID: sessionID, itemID: itemID,
            setID: current.id, exerciseKey: ExerciseKey(raw: "bench_press"),
            current: current, proposed: proposed, reason: "test",
            citationIDs: ["rpeAutoregulation"], confidence: .moderate)

        let updated = try UnifiedPlanCoachEngine.apply(proposal, to: plan,
                                                        at: Date(timeIntervalSince1970: 20))

        XCTAssertEqual(updated.revisionID, "r2")
        XCTAssertTrue(updated.assistance?.contains(.progressed) == true)
        XCTAssertEqual(updated.updatedAt, Date(timeIntervalSince1970: 20))
        XCTAssertEqual(updated.weeks[0].days[0].sessions[0].strengthSets.first, proposed)
    }

    func testStaleProgressionCannotOverwriteAnEditedSet() throws {
        let current = PrescribedSet(id: UUID(), setIndex: 0, repTarget: .exact(8))
        let plan = plan(with: [current])
        let session = plan.weeks[0].days[0].sessions[0]
        let item = try XCTUnwrap(session.items.first)
        let proposal = UnifiedPlanProgressionProposal(
            id: "progress|stale", sessionID: session.id, itemID: item.id,
            setID: current.id, exerciseKey: ExerciseKey(raw: "bench_press"),
            current: PrescribedSet(id: current.id, setIndex: 0, repTarget: .exact(7)),
            proposed: PrescribedSet(id: current.id, setIndex: 0, repTarget: .exact(9)),
            reason: "test", citationIDs: ["rpeAutoregulation"], confidence: .moderate)

        XCTAssertThrowsError(try UnifiedPlanCoachEngine.apply(proposal, to: plan)) { error in
            XCTAssertEqual(error as? UnifiedPlanCoachError, .proposalNoLongerApplies)
        }
    }

    func testApplyingAutoregulationRemovesOnlyOneWorkingSet() throws {
        let sets = (0..<3).map { index in
            PrescribedSet(id: UUID(), setIndex: index, repTarget: .exact(8))
        }
        let plan = plan(with: sets)
        let session = plan.weeks[0].days[0].sessions[0]
        let item = try XCTUnwrap(session.items.first)
        let proposal = UnifiedPlanAutoregulationProposal(
            id: "autoregulate|test", sessionID: session.id, itemID: item.id,
            direction: .reduceVolume, workingSetAdjustment: -1,
            detail: "test", citationIDs: ["sawMonitoring2016"], confidence: .moderate)

        let updated = try UnifiedPlanCoachEngine.apply(proposal, to: plan)

        XCTAssertEqual(updated.weeks[0].days[0].sessions[0].strengthSets.count, 2)
        XCTAssertTrue(updated.assistance?.contains(.autoregulated) == true)
        XCTAssertEqual(updated.revisionID, "r2")
    }

    private func plan(with sets: [PrescribedSet]) -> Plan {
        var plan = ManualPlanBuilder.blankPlan(now: Date(timeIntervalSince1970: 10))
        var session = ManualPlanBuilder.strengthSession(title: "Test session")
        session.items = [.strength(StrengthItem(
            exerciseKey: ExerciseKey(raw: "bench_press"), order: 0, sets: sets))]
        try! ManualPlanBuilder.addSession(session, to: .monday, in: &plan)
        return plan
    }
}

private extension Session {
    var strengthSets: [PrescribedSet] {
        items.flatMap { item in
            guard case let .strength(value) = item else { return [PrescribedSet]() }
            return value.sets
        }
    }
}
