import XCTest
import CadenceCore
import CadenceFeatures

final class SetAlternationTests: XCTestCase {

    private func pending(_ performerID: UUID?, _ setIndex: Int) -> SessionRenderModel.PendingSetDisplay {
        SessionRenderModel.PendingSetDisplay(
            performerID: performerID,
            performerName: performerID == nil ? "Me" : "P",
            setIndex: setIndex,
            targetReps: 5,
            targetWeightKg: 60)
    }

    private func names(_ rows: [SessionRenderModel.PendingSetDisplay]) -> [Bool] {
        rows.map { $0.performerID == nil }
    }

    // MARK: - spread

    /// Field test 2026-08-20 #1 (decision D2): the exact field report. Owner owes
    /// indices 1–2, partner owes 0–2. The old column round-robin emitted
    /// Me, P, Me, P, P (same name twice); the fair queue must emit
    /// P, Me, P, Me, P.
    func testSpreadAlternatesTheFieldReportScenario() {
        let partner = UUID()
        let me = pending(nil, 1)
        let me2 = pending(nil, 2)
        let p0 = pending(partner, 0)
        let p1 = pending(partner, 1)
        let p2 = pending(partner, 2)

        let result = SetAlternation.spread([[me, me2], [p0, p1, p2]])

        XCTAssertEqual(result.map(\.setIndex), [0, 1, 1, 2, 2])
        XCTAssertEqual(names(result), [false, true, false, true, false],
                       "Same performer twice in a row while the other still owes rows")
    }

    /// Field test 2026-08-20 #1: no two consecutive rows from the same performer
    /// while at least two performers still have outstanding rows.
    func testSpreadNeverRepeatsAPerformerWhileTwoPerformersHaveRows() {
        let me = [pending(nil, 0), pending(nil, 1)]
        let a = [pending(UUID(), 0), pending(UUID(), 1)]
        let b = [pending(UUID(), 0), pending(UUID(), 1), pending(UUID(), 2)]

        let result = SetAlternation.spread([me, a, b])
        let isAlternating = zip(result, result.dropFirst())
            .allSatisfy { $0.performerID != $1.performerID }
        XCTAssertTrue(isAlternating, "Pending rows repeat a performer: \(result.map { $0.performerID })")
    }

    /// When only one performer has rows left, their remainder is emitted (the
    /// unavoidable, correct tail).
    func testSpreadSoloGroupEmitsTail() {
        let p = [pending(UUID(), 0), pending(UUID(), 1), pending(UUID(), 2)]
        let result = SetAlternation.spread([[], p])
        XCTAssertEqual(result.map(\.setIndex), [0, 1, 2])
    }

    func testSpreadIsDeterministicGivenTheSameGroups() {
        let groups = [[pending(nil, 0), pending(nil, 1), pending(nil, 2)],
                      [pending(UUID(), 0), pending(UUID(), 1)],
                      [pending(UUID(), 0)]]
        XCTAssertEqual(SetAlternation.spread(groups), SetAlternation.spread(groups))
    }

    func testSpreadEmptyGroupsReturnsEmpty() {
        XCTAssertTrue(SetAlternation.spread([[], []]).isEmpty)
    }

    // MARK: - nextPerformerID

    func testNextPerformerIDIsFirstPendingRow() {
        let partner = UUID()
        let me = pending(nil, 0)
        let p0 = pending(partner, 0)
        let id = SetAlternation.nextPerformerID(
            pendingSets: [p0, me],
            rosterOrder: [nil, partner],
            lastLoggedPerformerID: nil)
        XCTAssertEqual(id, partner, "The first pending row must win over any rotation")
    }

    func testNextPerformerIDIsFirstPendingRowForTheOwner() {
        let partner = UUID()
        let me = pending(nil, 0)
        let id = SetAlternation.nextPerformerID(
            pendingSets: [me],
            rosterOrder: [nil, partner],
            lastLoggedPerformerID: partner)
        XCTAssertNil(id, "An owner-led pending row must win over any rotation")
    }

    func testNextPerformerIDFallsBackToRosterRotation() {
        let partner = UUID()
        let id = SetAlternation.nextPerformerID(
            pendingSets: [],
            rosterOrder: [nil, partner],
            lastLoggedPerformerID: partner)
        XCTAssertNil(id, "After a partner, the rotation falls back to the owner")
    }

    func testNextPerformerIDDefaultsToOwner() {
        let partner = UUID()
        let id = SetAlternation.nextPerformerID(
            pendingSets: [],
            rosterOrder: [nil, partner],
            lastLoggedPerformerID: nil)
        XCTAssertNil(id, "Nothing logged → the owner leads a silent exercise")
    }
}
