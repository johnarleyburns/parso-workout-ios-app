import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures

final class SessionRenderModelTests: XCTestCase {

    func testCollapsedSummaryIncludesPrescriptionDimensionsAndPartners() {
        let partner = UUID()
        let context = SessionRenderModel.ExerciseContext(
            exerciseID: UUID(), name: "Bench Press", sets: [], pendingCount: 2,
            pendingReps: [8, 6], performerContexts: [
                .init(performerID: nil, label: "Me", isMe: true, lastTimeSets: [], pr: nil,
                      prRuleName: "", priorSamples: [], firstWorkingWeightKg: nil, repLadders: []),
                .init(performerID: partner, label: "Sam", isMe: false, lastTimeSets: [], pr: nil,
                      prRuleName: "", priorSamples: [], firstWorkingWeightKg: nil, repLadders: [])
            ], pendingSets: [
                .init(performerID: nil, performerName: "Me", setIndex: 0, targetReps: 8, targetWeightKg: 60),
                .init(performerID: partner, performerName: "Sam", setIndex: 0, targetReps: 6, targetWeightKg: 60)
            ])
        let summary = SessionRenderModel.compactSummary(context: context, unit: .kilograms)
        XCTAssertTrue(summary.contains("sets"))
        XCTAssertTrue(summary.contains("reps"))
        XCTAssertTrue(summary.contains("60"))
        XCTAssertTrue(summary.contains("Sam"))
    }

    // MARK: - Signature ignores keystroke state

    func testSignatureIgnoresKeystrokeState() {
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 5, latestSetUpdate: Date(),
            exerciseIDs: [UUID()], plannedNames: ["Bench"], rosterIDs: [],
            prRule: .estimated1RM, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 5, latestSetUpdate: sig1.latestSetUpdate,
            exerciseIDs: sig1.exerciseIDs, plannedNames: sig1.plannedNames, rosterIDs: [],
            prRule: .estimated1RM, formula: .epley)

        XCTAssertEqual(sig1, sig2, "Same structural state → equal signature")
    }

    func testSignatureChangesOnSetCountChange() {
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 5, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 6, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)

        XCTAssertNotEqual(sig1, sig2)
    }

    func testSignatureChangesOnExerciseOrderChange() {
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [UUID()], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [UUID()], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)

        XCTAssertNotEqual(sig1, sig2, "Different exercise ID lists → different signatures")
    }

    func testSignatureChangesOnPRRuleChange() {
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .estimated1RM, formula: .epley)

        XCTAssertNotEqual(sig1, sig2)
    }

    func testSignatureChangesOnFormulaChange() {
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .estimated1RM, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .estimated1RM, formula: .brzycki)

        XCTAssertNotEqual(sig1, sig2)
    }

    func testSignatureChangesOnLatestSetUpdate() {
        let now = Date()
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 5, latestSetUpdate: now,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 5, latestSetUpdate: now.addingTimeInterval(1),
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)

        XCTAssertNotEqual(sig1, sig2)
    }

    // MARK: - Cache rebuild count proofs

    func testEqualSignatureNeverRebuilds() {
        let cache = SessionHistoryCache()
        let sig = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)

        // First call always rebuilds
        cache.refresh(signature: sig) {
            SessionRenderModel.State(contexts: [], prSetIDs: [])
        }
        XCTAssertEqual(cache.rebuildCount, 1)

        // 50 more calls with same signature → no rebuilds
        for _ in 0..<50 {
            cache.refresh(signature: sig) {
                SessionRenderModel.State(contexts: [], prSetIDs: [])
            }
        }
        XCTAssertEqual(cache.rebuildCount, 1, "50 equal signatures should produce 0 additional rebuilds")
    }

    func testChangedSignatureRebuildsOnce() {
        let cache = SessionHistoryCache()
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 1, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)

        cache.refresh(signature: sig1) {
            SessionRenderModel.State(contexts: [], prSetIDs: [])
        }
        XCTAssertEqual(cache.rebuildCount, 1)

        cache.refresh(signature: sig2) {
            SessionRenderModel.State(contexts: [], prSetIDs: [])
        }
        XCTAssertEqual(cache.rebuildCount, 2, "Different signature should rebuild exactly once")

        // Repeated same signature → no further rebuilds
        cache.refresh(signature: sig2) {
            SessionRenderModel.State(contexts: [], prSetIDs: [])
        }
        XCTAssertEqual(cache.rebuildCount, 2)
    }

    // MARK: - wouldBePR parity

    func testWouldBePRWithNoPriorSamplesReturnsFalse() {
        let state = SessionRenderModel.State(contexts: [], prSetIDs: [])
        let result = state.wouldBePR(weightKg: 100, reps: 5, isWarmup: false,
                                      rule: .topWeight, formula: .epley,
                                      for: UUID())
        XCTAssertFalse(result, "No matching context → can't be a PR")
    }

    func testWouldBePRAgainstCachedSamples() {
        let sample = SetSample(weight: 80, reps: 5, isWarmup: false)
        let pc = SessionRenderModel.PerformerContext(
            performerID: nil, label: "Me", isMe: true,
            lastTimeSets: [], pr: 80, prRuleName: "Top weight",
            priorSamples: [sample], firstWorkingWeightKg: 80, repLadders: [])
        let exerciseID = UUID()
        let ctx = SessionRenderModel.ExerciseContext(
            exerciseID: exerciseID, name: "Bench",
            sets: [], pendingCount: 0, pendingReps: [],
            performerContexts: [pc])
        let state = SessionRenderModel.State(contexts: [ctx], prSetIDs: [])

        // Same weight → not a PR
        XCTAssertFalse(state.wouldBePR(weightKg: 80, reps: 5, isWarmup: false,
                                        rule: .topWeight, formula: .epley,
                                        for: exerciseID))

        // Higher weight → PR
        XCTAssertTrue(state.wouldBePR(weightKg: 100, reps: 5, isWarmup: false,
                                       rule: .topWeight, formula: .epley,
                                       for: exerciseID))

        // Warmup → never a PR
        XCTAssertFalse(state.wouldBePR(weightKg: 100, reps: 5, isWarmup: true,
                                        rule: .topWeight, formula: .epley,
                                        for: exerciseID))
    }

    // MARK: - Parity: build against a fixture store

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    func testBuildCreatesContextsForLoggedExercises() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Test", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)

        let state = SessionRenderModel.build(
            session: session, prRule: .topWeight, formula: .epley,
            allPeople: try WorkoutRepository.allPeople(ctx))

        XCTAssertEqual(state.contexts.count, 1, "One logged exercise → one context")
        XCTAssertEqual(state.contexts[0].name, "Bench Press")
        XCTAssertEqual(state.contexts[0].sets.count, 1)
        XCTAssertEqual(state.contexts[0].sets[0].weight, 80)
        XCTAssertEqual(state.contexts[0].sets[0].reps, 5)
    }

    func testPRSetIDsContainsPRSet() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Test", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let set = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)

        let state = SessionRenderModel.build(
            session: session, prRule: .topWeight, formula: .epley,
            allPeople: try WorkoutRepository.allPeople(ctx))

        // First set ever is a PR
        XCTAssertTrue(state.prSetIDs.contains(set.id))
    }

    func testBuildEmptySessionReturnsNoContexts() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)

        let state = SessionRenderModel.build(
            session: session, prRule: .topWeight, formula: .epley,
            allPeople: try WorkoutRepository.allPeople(ctx))

        XCTAssertTrue(state.contexts.isEmpty)
        XCTAssertTrue(state.prSetIDs.isEmpty)
    }

    func testPartnerContextsSeparated() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Alice", in: ctx)
        let session = try WorkoutRepository.createSession(title: "Test", partnerIDs: [partner.id.uuidString], in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        // Owner set
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        // Partner set
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 10,
                                          performedBy: partner, in: ctx)

        let state = SessionRenderModel.build(
            session: session, prRule: .topWeight, formula: .epley,
            allPeople: try WorkoutRepository.allPeople(ctx))

        XCTAssertEqual(state.contexts.count, 1)
        let card = state.contexts[0]

        // Owner sets should include weight 80
        let ownerSets = card.sets.filter { $0.isOwnerSet }
        XCTAssertEqual(ownerSets.count, 1)
        XCTAssertEqual(ownerSets[0].weight, 80)

        // Partner sets should include weight 60
        let partnerSets = card.sets.filter { !$0.isOwnerSet }
        XCTAssertEqual(partnerSets.count, 1)
        XCTAssertEqual(partnerSets[0].weight, 60)

        // Partner attribution is preserved in SetDisplay
        XCTAssertNotNil(partnerSets[0].performedBy)
        XCTAssertEqual(partnerSets[0].performedBy?.name, "Alice")
    }

    func testExerciseContextHasPRInfo() throws {
        let ctx = try makeContext()
        // Session 1: baseline at 50 kg
        let s1 = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: s1, exercise: bench, weightKg: 50, reps: 8, in: ctx)

        // Session 2: new set at 100 kg, PR = 50 from session 1
        let s2 = try WorkoutRepository.createSession(in: ctx)
        _ = try WorkoutRepository.addSet(to: s2, exercise: bench, weightKg: 100, reps: 5, in: ctx)

        let state = SessionRenderModel.build(
            session: s2, prRule: .topWeight, formula: .epley,
            allPeople: try WorkoutRepository.allPeople(ctx))

        let card = state.contexts[0]
        XCTAssertEqual(card.performerContexts.count, 1)
        XCTAssertEqual(card.performerContexts[0].label, "Me")
        XCTAssertEqual(card.performerContexts[0].isMe, true)
        // Top weight PR from prior session = 50 kg
        XCTAssertEqual(card.performerContexts[0].pr, 50)
    }

    func testExcludingCurrentSessionFromPR() throws {
        let ctx = try makeContext()

        // Session 1: set a baseline PR at 80 kg
        let s1 = try WorkoutRepository.createSession(in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: s1, exercise: bench, weightKg: 80, reps: 5, in: ctx)

        // Session 2: add a new PR at 100 kg
        let s2 = try WorkoutRepository.createSession(in: ctx)
        let set100 = try WorkoutRepository.addSet(to: s2, exercise: bench, weightKg: 100, reps: 5, in: ctx)

        let state = SessionRenderModel.build(
            session: s2, prRule: .topWeight, formula: .epley,
            allPeople: try WorkoutRepository.allPeople(ctx))

        // PR info should exclude current session, so PR = 80 (from s1)
        let card = state.contexts[0]
        XCTAssertEqual(card.performerContexts[0].pr, 80, "PR should exclude current session sets")

        // But the current session's set of 100 IS still counted as a PR against previous history
        XCTAssertTrue(state.prSetIDs.contains(set100.id), "100 kg should be all-time PR v/s session 1's 80")
    }

    // MARK: - signature computed from session

    func testSignatureComputedFromSessionMatchesStructuralState() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)

        let sig = SessionRenderModel.signature(session: session, prRule: .topWeight, formula: OneRepMaxFormula.epley)
        XCTAssertEqual(sig.setCount, 0)
        XCTAssertEqual(sig.exerciseIDs, [UUID]())
        XCTAssertEqual(sig.prRule, PRRule.topWeight)
    }

    // MARK: - Stored partner plans (field test 2026-08-18 #4, decision D11)

    /// A partner with no history of their own: the pending set must come from
    /// the plan the editor stored for THEM, not from the owner's prescription.
    func testPendingSetsUseThePerformersStoredPrescriptionWhenPresent() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Alice", in: ctx)
        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        session.plannedPrescriptions = [PlannedExercisePrescription(
            exerciseName: "Bench Press",
            sets: [PlannedSetPrescription(targetReps: 5, targetWeightKg: 100)])]
        session.plannedPerformerPrescriptions = [
            PlannedPerformerPrescription(performerID: nil, exercises: session.plannedPrescriptions),
            PlannedPerformerPrescription(performerID: partner.id.uuidString, exercises: [
                PlannedExercisePrescription(
                    exerciseName: "Bench Press",
                    sets: [PlannedSetPrescription(targetReps: 12, targetWeightKg: 40)])])
        ]

        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx))

        let partnerPending = state.contexts[0].pendingSets.filter { $0.performerID == partner.id }
        XCTAssertEqual(partnerPending.map(\.targetReps), [12],
                       "The partner's pending set ignored their own stored plan")
        XCTAssertEqual(partnerPending.map(\.targetWeightKg), [40],
                       "The partner's pending set took the owner's weight")
    }

    func testPendingSetsFallBackToTheOwnerPrescriptionWhenAbsent() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Alice", in: ctx)
        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        session.plannedPrescriptions = [PlannedExercisePrescription(
            exerciseName: "Bench Press",
            sets: [PlannedSetPrescription(targetReps: 7, targetWeightKg: 100)])]

        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx))

        let partnerPending = state.contexts[0].pendingSets.filter { $0.performerID == partner.id }
        XCTAssertEqual(partnerPending.map(\.targetReps), [7],
                       "A legacy session (no performer data) must behave exactly as before")
    }

    /// Field test 2026-08-19 #1 reverses the 2026-08-18 policy: an entered plan
    /// is the prescription, not merely a starting hint. Every set index the plan
    /// covers uses the planned reps AND the planned load; history only fills what
    /// the plan leaves unsaid.
    func testStoredPlanOutranksThePartnersOwnHistory() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Alice", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        let past = try WorkoutRepository.createSession(title: "Last week", in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 45, reps: 20,
                                          performedBy: partner, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 45, reps: 18,
                                          performedBy: partner, in: ctx)

        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        session.plannedPerformerPrescriptions = [
            PlannedPerformerPrescription(performerID: partner.id.uuidString, exercises: [
                PlannedExercisePrescription(
                    exerciseName: "Bench Press",
                    sets: [PlannedSetPrescription(targetReps: 12, targetWeightKg: 40),
                           PlannedSetPrescription(targetReps: 12, targetWeightKg: 40)])])
        ]

        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx))

        let partnerPending = state.contexts[0].pendingSets
            .filter { $0.performerID == partner.id }
            .sorted { $0.setIndex < $1.setIndex }
        XCTAssertEqual(partnerPending.count, 2,
                       "The stored plan decides how many sets the partner has left")
        XCTAssertEqual(partnerPending.map(\.targetReps), [12, 12],
                       "Every planned set must honour the plan the user entered")
        XCTAssertTrue(partnerPending.allSatisfy { $0.targetWeightKg == 40 },
                      "The entered plan's load was discarded in favour of history")
    }

    /// Where the plan says nothing — a set index it does not cover — the
    /// performer's own history still fills in.
    func testHistoryFillsSetsThePlanDoesNotCover() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Alice", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        let past = try WorkoutRepository.createSession(title: "Last week", in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 45, reps: 20,
                                          performedBy: partner, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 45, reps: 18,
                                          performedBy: partner, in: ctx)

        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        session.plannedPrescriptions = [PlannedExercisePrescription(
            exerciseName: "Bench Press",
            sets: [PlannedSetPrescription(targetReps: 5, targetWeightKg: 100),
                   PlannedSetPrescription(targetReps: 5, targetWeightKg: 100)])]
        session.plannedPerformerPrescriptions = [
            PlannedPerformerPrescription(performerID: partner.id.uuidString, exercises: [
                PlannedExercisePrescription(
                    exerciseName: "Bench Press",
                    sets: [PlannedSetPrescription(targetReps: 12, targetWeightKg: nil)])])
        ]

        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx))

        let partnerPending = state.contexts[0].pendingSets
            .filter { $0.performerID == partner.id }
            .sorted { $0.setIndex < $1.setIndex }
        XCTAssertEqual(partnerPending[0].targetReps, 12, "Planned reps must win at index 0")
        XCTAssertEqual(partnerPending[0].targetWeightKg, 45,
                       "A plan with no load falls through to the partner's own working weight")
    }

    /// Field test 2026-08-19 #3: a partner who has never done THIS lift still has
    /// hundreds of sets on others. Their habitual rep count beats the generic 5.
    func testPartnerWithoutMovementHistoryUsesTheirHabitualReps() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Alice", in: ctx)
        let squat = try WorkoutRepository.findOrCreateExercise(named: "Back Squat", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        let past = try WorkoutRepository.createSession(title: "Last week", in: ctx)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(to: past, exercise: squat, weightKg: 30, reps: 20,
                                              performedBy: partner, in: ctx)
        }

        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        session.plannedRepLadder = [5, 5]

        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx),
                                             recentSessions: try WorkoutRepository.allSessions(ctx))

        let partnerPending = state.contexts[0].pendingSets.filter { $0.performerID == partner.id }
        XCTAssertEqual(partnerPending.map(\.targetReps), [20, 20],
                       "The partner defaulted to the owner's ladder instead of their own usual reps")
    }

    /// Field test 2026-08-19 #1: partners take turns, so the outstanding rows
    /// alternate rather than listing everything one person owes first.
    func testPendingSetsAlternateBetweenPerformers() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Alice", in: ctx)
        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        session.plannedRepLadder = [5, 5, 5]

        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx))

        // The owner has logged set 1, so they owe indices 1 and 2; the partner
        // owes 0, 1 and 2. The card must read partner-0, me-1, partner-1, …
        let order = state.contexts[0].pendingSets.map { ($0.performerID == nil, $0.setIndex) }
        XCTAssertEqual(order.map(\.1), [1, 0, 2, 1, 2],
                       "Pending rows are not round-robined across performers")
        XCTAssertEqual(order.map(\.0), [true, false, true, false, false])
    }
}
