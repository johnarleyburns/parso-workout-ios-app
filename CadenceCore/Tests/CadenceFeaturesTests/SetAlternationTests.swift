import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct SetAlternationTests {

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
    @Test func spreadAlternatesTheFieldReportScenario() {
        let partner = UUID()
        let me = pending(nil, 1)
        let me2 = pending(nil, 2)
        let p0 = pending(partner, 0)
        let p1 = pending(partner, 1)
        let p2 = pending(partner, 2)

        let result = SetAlternation.spread([[me, me2], [p0, p1, p2]])

        #expect(result.map(\.setIndex) == [0, 1, 1, 2, 2])
        #expect(names(result) == [false, true, false, true, false],
                       "Same performer twice in a row while the other still owes rows")
    }

    /// Field test 2026-08-20 #1: no two consecutive rows from the same performer
    /// while at least two performers still have outstanding rows.
    @Test func spreadNeverRepeatsAPerformerWhileTwoPerformersHaveRows() {
        let me = [pending(nil, 0), pending(nil, 1)]
        let a = [pending(UUID(), 0), pending(UUID(), 1)]
        let b = [pending(UUID(), 0), pending(UUID(), 1), pending(UUID(), 2)]

        let result = SetAlternation.spread([me, a, b])
        let isAlternating = zip(result, result.dropFirst())
            .allSatisfy { $0.performerID != $1.performerID }
        #expect(isAlternating, "Pending rows repeat a performer: \(result.map { $0.performerID })")
    }

    /// When only one performer has rows left, their remainder is emitted (the
    /// unavoidable, correct tail).
    @Test func spreadSoloGroupEmitsTail() {
        let p = [pending(UUID(), 0), pending(UUID(), 1), pending(UUID(), 2)]
        let result = SetAlternation.spread([[], p])
        #expect(result.map(\.setIndex) == [0, 1, 2])
    }

    @Test func spreadIsDeterministicGivenTheSameGroups() {
        let groups = [[pending(nil, 0), pending(nil, 1), pending(nil, 2)],
                      [pending(UUID(), 0), pending(UUID(), 1)],
                      [pending(UUID(), 0)]]
        #expect(SetAlternation.spread(groups) == SetAlternation.spread(groups))
    }

    @Test func spreadEmptyGroupsReturnsEmpty() {
        #expect(SetAlternation.spread([[], []]).isEmpty)
    }

    // MARK: - nextPerformerID

    @Test func nextPerformerIDIsFirstPendingRow() {
        let partner = UUID()
        let me = pending(nil, 0)
        let p0 = pending(partner, 0)
        let id = SetAlternation.nextPerformerID(
            pendingSets: [p0, me],
            rosterOrder: [nil, partner],
            lastLoggedPerformerID: nil)
        #expect(id == partner, "The first pending row must win over any rotation")
    }

    @Test func nextPerformerIDIsFirstPendingRowForTheOwner() {
        let partner = UUID()
        let me = pending(nil, 0)
        let id = SetAlternation.nextPerformerID(
            pendingSets: [me],
            rosterOrder: [nil, partner],
            lastLoggedPerformerID: partner)
        #expect(id == nil, "An owner-led pending row must win over any rotation")
    }

    @Test func nextPerformerIDFallsBackToRosterRotation() {
        let partner = UUID()
        let id = SetAlternation.nextPerformerID(
            pendingSets: [],
            rosterOrder: [nil, partner],
            lastLoggedPerformerID: partner,
            hasLoggedWorkingSet: true)
        #expect(id == nil, "After a partner, the rotation falls back to the owner")
    }

    @Test func nextPerformerIDDefaultsToFirstConfiguredPerformer() {
        let partner = UUID()
        let id = SetAlternation.nextPerformerID(
            pendingSets: [],
            rosterOrder: [partner, nil],
            lastLoggedPerformerID: nil)
        #expect(id == partner, "Nothing logged → the configured first performer leads")
    }

    @Test func nextPerformerIDAdvancesAfterOwnerEvenWhenPendingOwnerRowLeads() {
        let partner = UUID()
        let id = SetAlternation.nextPerformerID(
            pendingSets: [pending(nil, 0), pending(partner, 0)],
            rosterOrder: [nil, partner],
            lastLoggedPerformerID: nil,
            hasLoggedWorkingSet: true)
        #expect(id == partner, "After Me logs, Add Set must advance to the partner")
    }

    @Test func nextPerformerIDCyclesThreeConfiguredPerformers() {
        let sam = UUID()
        let alex = UUID()
        #expect(SetAlternation.nextPerformerID(
            pendingSets: [], rosterOrder: [nil, sam, alex],
            lastLoggedPerformerID: sam, hasLoggedWorkingSet: true) == alex)
        #expect(SetAlternation.nextPerformerID(
            pendingSets: [], rosterOrder: [nil, sam, alex],
            lastLoggedPerformerID: alex, hasLoggedWorkingSet: true) == nil)
    }

    @Test func nextPerformerIDRecoversWhenLastPerformerWasRemoved() {
        let removed = UUID()
        let partner = UUID()
        #expect(SetAlternation.nextPerformerID(
            pendingSets: [], rosterOrder: [nil, partner],
            lastLoggedPerformerID: removed, hasLoggedWorkingSet: true) == nil)
    }

    @Test func nextPerformerIDEmptyRosterIsSafe() {
        #expect(SetAlternation.nextPerformerID(
            pendingSets: [], rosterOrder: [], lastLoggedPerformerID: nil,
            hasLoggedWorkingSet: true) == nil)
    }

    @Test func currentPendingUsesInterleavedFirstRowNotPerformerSetIndex() {
        let partner = UUID()
        let completed = SessionRenderModel.SetDisplay(
            setID: UUID(), weight: 57, reps: 8, rpe: nil, isWarmup: false,
            usesBodyweight: false, isOwnerSet: true, performedBy: nil,
            isAllTimePR: false)
        let partnerPending = pending(partner, 0)
        let ownerPending = pending(nil, 1)
        let context = SessionRenderModel.ExerciseContext(
            exerciseID: UUID(), name: "Cable Row", sets: [completed],
            pendingCount: 2, pendingReps: [], performerContexts: [],
            pendingSets: [partnerPending, ownerPending], hasPlannedWork: true)

        #expect(context.isCurrentPending(partnerPending))
        #expect(!context.isCurrentPending(ownerPending))
    }

    @Test func repeatTargetsTheFirstPendingPartnerInsteadOfOwnersLastSet() {
        let partner = UUID()
        let partnerPending = pending(partner, 0)

        #expect(SetAlternation.performerForRepeat(
            pendingSets: [partnerPending], fallbackPerformerID: nil) == partner)
        #expect(SetAlternation.performerForRepeat(
            pendingSets: [], fallbackPerformerID: nil) == nil)
    }

    @Test func repeatTracksEachPartnerInTheInterleavedQueue() {
        let firstPartner = UUID()
        let secondPartner = UUID()
        let first = pending(firstPartner, 0)
        let second = pending(secondPartner, 0)

        #expect(SetAlternation.performerForRepeat(
            pendingSets: [first, second], fallbackPerformerID: nil) == firstPartner)
        #expect(SetAlternation.performerForRepeat(
            pendingSets: [second], fallbackPerformerID: firstPartner) == secondPartner)
    }
}
