#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct SessionRenderModelTests {

    @Test func collapsedSummaryIncludesPrescriptionDimensionsAndPartners() {
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
        #expect(summary.contains("sets"))
        #expect(summary.contains("reps"))
        #expect(summary.contains("60"))
        #expect(summary.contains("Sam"))
    }

    // MARK: - Signature ignores keystroke state

    @Test func signatureIgnoresKeystrokeState() {
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 5, latestSetUpdate: Date(),
            exerciseIDs: [UUID()], plannedNames: ["Bench"], rosterIDs: [],
            prRule: .estimated1RM, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 5, latestSetUpdate: sig1.latestSetUpdate,
            exerciseIDs: sig1.exerciseIDs, plannedNames: sig1.plannedNames, rosterIDs: [],
            prRule: .estimated1RM, formula: .epley)

        #expect(sig1 == sig2, "Same structural state → equal signature")
    }

    @Test func signatureChangesOnSetCountChange() {
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 5, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 6, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)

        #expect(sig1 != sig2)
    }

    @Test func signatureChangesOnExerciseOrderChange() {
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [UUID()], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [UUID()], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)

        #expect(sig1 != sig2, "Different exercise ID lists → different signatures")
    }

    @Test func signatureChangesOnPRRuleChange() {
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .estimated1RM, formula: .epley)

        #expect(sig1 != sig2)
    }

    @Test func signatureChangesOnFormulaChange() {
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .estimated1RM, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .estimated1RM, formula: .brzycki)

        #expect(sig1 != sig2)
    }

    @Test func signatureChangesOnLatestSetUpdate() {
        let now = Date()
        let sig1 = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 5, latestSetUpdate: now,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)
        let sig2 = SessionRenderModel.Signature(
            sessionID: sig1.sessionID, setCount: 5, latestSetUpdate: now.addingTimeInterval(1),
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)

        #expect(sig1 != sig2)
    }

    // MARK: - Cache rebuild count proofs

    @Test func equalSignatureNeverRebuilds() {
        let cache = SessionHistoryCache()
        let sig = SessionRenderModel.Signature(
            sessionID: UUID(), setCount: 0, latestSetUpdate: nil,
            exerciseIDs: [], plannedNames: [], rosterIDs: [],
            prRule: .topWeight, formula: .epley)

        // First call always rebuilds
        cache.refresh(signature: sig) {
            SessionRenderModel.State(contexts: [], prSetIDs: [])
        }
        #expect(cache.rebuildCount == 1)

        // 50 more calls with same signature → no rebuilds
        for _ in 0..<50 {
            cache.refresh(signature: sig) {
                SessionRenderModel.State(contexts: [], prSetIDs: [])
            }
        }
        #expect(cache.rebuildCount == 1, "50 equal signatures should produce 0 additional rebuilds")
    }

    @Test func changedSignatureRebuildsOnce() {
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
        #expect(cache.rebuildCount == 1)

        cache.refresh(signature: sig2) {
            SessionRenderModel.State(contexts: [], prSetIDs: [])
        }
        #expect(cache.rebuildCount == 2, "Different signature should rebuild exactly once")

        // Repeated same signature → no further rebuilds
        cache.refresh(signature: sig2) {
            SessionRenderModel.State(contexts: [], prSetIDs: [])
        }
        #expect(cache.rebuildCount == 2)
    }

    // MARK: - wouldBePR parity

    @Test func wouldBePRWithNoPriorSamplesReturnsFalse() {
        let state = SessionRenderModel.State(contexts: [], prSetIDs: [])
        let result = state.wouldBePR(weightKg: 100, reps: 5, isWarmup: false,
                                      rule: .topWeight, formula: .epley,
                                      for: UUID())
        #expect(!result, "No matching context → can't be a PR")
    }

    @Test func wouldBePRAgainstCachedSamples() {
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
        #expect(!state.wouldBePR(weightKg: 80, reps: 5, isWarmup: false,
                                        rule: .topWeight, formula: .epley,
                                        for: exerciseID))

        // Higher weight → PR
        #expect(state.wouldBePR(weightKg: 100, reps: 5, isWarmup: false,
                                       rule: .topWeight, formula: .epley,
                                       for: exerciseID))

        // Warmup → never a PR
        #expect(!state.wouldBePR(weightKg: 100, reps: 5, isWarmup: true,
                                        rule: .topWeight, formula: .epley,
                                        for: exerciseID))
    }

    // MARK: - Parity: build against a fixture store

    private func makeContext() throws -> ModelContext {
        ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
    }

    @Test func buildCreatesContextsForLoggedExercises() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Test", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)

        let state = SessionRenderModel.build(
            session: session, prRule: .topWeight, formula: .epley,
            allPeople: try WorkoutRepository.allPeople(ctx))

        #expect(state.contexts.count == 1, "One logged exercise → one context")
        #expect(state.contexts[0].name == "Bench Press")
        #expect(state.contexts[0].sets.count == 1)
        #expect(state.contexts[0].sets[0].weight == 80)
        #expect(state.contexts[0].sets[0].reps == 5)
    }

    @Test func prSetIDsContainsPRSet() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(title: "Test", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        let set = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)

        let state = SessionRenderModel.build(
            session: session, prRule: .topWeight, formula: .epley,
            allPeople: try WorkoutRepository.allPeople(ctx))

        // First set ever is a PR
        #expect(state.prSetIDs.contains(set.id))
    }

    @Test func buildEmptySessionReturnsNoContexts() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)

        let state = SessionRenderModel.build(
            session: session, prRule: .topWeight, formula: .epley,
            allPeople: try WorkoutRepository.allPeople(ctx))

        #expect(state.contexts.isEmpty)
        #expect(state.prSetIDs.isEmpty)
    }

    @Test func partnerContextsSeparated() throws {
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

        #expect(state.contexts.count == 1)
        let card = state.contexts[0]

        // Owner sets should include weight 80
        let ownerSets = card.sets.filter { $0.isOwnerSet }
        #expect(ownerSets.count == 1)
        #expect(ownerSets[0].weight == 80)

        // Partner sets should include weight 60
        let partnerSets = card.sets.filter { !$0.isOwnerSet }
        #expect(partnerSets.count == 1)
        #expect(partnerSets[0].weight == 60)

        // Partner attribution is preserved in SetDisplay
        #expect(partnerSets[0].performedBy != nil)
        #expect(partnerSets[0].performedBy?.name == "Alice")
    }

    @Test func exerciseContextHasPRInfo() throws {
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
        #expect(card.performerContexts.count == 1)
        #expect(card.performerContexts[0].label == "Me")
        #expect(card.performerContexts[0].isMe == true)
        // Top weight PR from prior session = 50 kg
        #expect(card.performerContexts[0].pr == 50)
    }

    @Test func excludingCurrentSessionFromPR() throws {
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
        #expect(card.performerContexts[0].pr == 80, "PR should exclude current session sets")

        // But the current session's set of 100 IS still counted as a PR against previous history
        #expect(state.prSetIDs.contains(set100.id), "100 kg should be all-time PR v/s session 1's 80")
    }

    // MARK: - signature computed from session

    @Test func signatureComputedFromSessionMatchesStructuralState() throws {
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(in: ctx)

        let sig = SessionRenderModel.signature(session: session, prRule: .topWeight, formula: OneRepMaxFormula.epley)
        #expect(sig.setCount == 0)
        #expect(sig.exerciseIDs == [UUID]())
        #expect(sig.prRule == PRRule.topWeight)
    }

    // MARK: - Stored partner plans (field test 2026-08-18 #4, decision D11)

    /// A partner with no history of their own: the pending set must come from
    /// the plan the editor stored for THEM, not from the owner's prescription.
    @Test func pendingSetsUseThePerformersStoredPrescriptionWhenPresent() throws {
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
        #expect(partnerPending.map(\.targetReps) == [12],
                       "The partner's pending set ignored their own stored plan")
        #expect(partnerPending.map(\.targetWeightKg) == [40],
                       "The partner's pending set took the owner's weight")
    }

    @Test func pendingSetsFallBackToTheOwnerPrescriptionWhenAbsent() throws {
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
        #expect(partnerPending.map(\.targetReps) == [7],
                       "A legacy session (no performer data) must behave exactly as before")
    }

    /// Field test 2026-08-19 #1 reverses the 2026-08-18 policy: an entered plan
    /// is the prescription, not merely a starting hint. Every set index the plan
    /// covers uses the planned reps AND the planned load; history only fills what
    /// the plan leaves unsaid.
    @Test func storedPlanOutranksThePartnersOwnHistory() throws {
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
        #expect(partnerPending.count == 2,
                       "The stored plan decides how many sets the partner has left")
        #expect(partnerPending.map(\.targetReps) == [12, 12],
                       "Every planned set must honour the plan the user entered")
        let allFortyKg = partnerPending.allSatisfy { $0.targetWeightKg == 40 }
        #expect(allFortyKg,
                      "The entered plan's load was discarded in favour of history")
    }

    /// Where the plan says nothing — a set index it does not cover — the
    /// performer's own history still fills in.
    @Test func historyFillsSetsThePlanDoesNotCover() throws {
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
        #expect(partnerPending[0].targetReps == 12, "Planned reps must win at index 0")
        #expect(partnerPending[0].targetWeightKg == 45,
                       "A plan with no load falls through to the partner's own working weight")
    }

    /// Field test 2026-08-19 #3: a partner who has never done THIS lift still has
    /// hundreds of sets on others. Their habitual rep count beats the generic 5.
    @Test func partnerWithoutMovementHistoryUsesTheirHabitualReps() throws {
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
        #expect(partnerPending.map(\.targetReps) == [20, 20],
                       "The partner defaulted to the owner's ladder instead of their own usual reps")
    }

    /// Field test 2026-08-19 #1: partners take turns, so the outstanding rows
    /// alternate rather than listing everything one person owes first.
    /// Field test 2026-08-20 #1 (decision D2): the alternation is a fair queue —
    /// never two consecutive rows from one performer while the other still owes
    /// rows. The old column round-robin emitted the buggy `Me,P,Me,P,P` tail.
    @Test func pendingSetsAlternateBetweenPerformers() throws {
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
        // owes 0, 1 and 2. The card must read partner-0, me-1, partner-1, me-2,
        // partner-2 — strict alternation, no same-name-twice.
        let order = state.contexts[0].pendingSets.map { ($0.performerID == nil, $0.setIndex) }
        #expect(order.map(\.1) == [0, 1, 1, 2, 2],
                       "Pending rows are not fairly spread across performers")
        #expect(order.map(\.0) == [false, true, false, true, false],
                       "Pending rows repeat a performer while the other still owes rows")
    }

    @Test func pendingRowsRespectAnExplicitPartnerFirstRoster() throws {
        let ctx = try makeContext()
        let me = try WorkoutRepository.me(in: ctx)
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Alice", in: ctx)
        let session = try WorkoutRepository.createSession(
            title: "Partner first", partnerIDs: [partner.id.uuidString, me.id.uuidString], in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        session.plannedPrescriptions = [PlannedExercisePrescription(
            exerciseName: bench.name,
            sets: [PlannedSetPrescription(targetReps: 8), PlannedSetPrescription(targetReps: 6)])]
        session.plannedExerciseNames = [bench.name]
        _ = try WorkoutRepository.addSet(to: session, exercise: bench,
                                          weightKg: 40, reps: 12, performedBy: partner, in: ctx)

        let state = SessionRenderModel.build(
            session: session, prRule: .topWeight, formula: .epley,
            allPeople: try WorkoutRepository.allPeople(ctx))

        #expect(state.contexts.first?.pendingSets.map(\.performerID) ==
                       [nil, partner.id, nil],
                       "After a partner starts, the owner must be next and rows must alternate")
    }

    /// Field test 2026-08-20 #1: the pending alternation is stable — rebuilding
    /// the same session twice yields identical pending rows.
    @Test func pendingAlternationIsDeterministicAcrossRebuilds() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Alice", in: ctx)
        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        session.plannedRepLadder = [5, 5, 5]
        let people = try WorkoutRepository.allPeople(ctx)

        let first = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: people)
        let second = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                              allPeople: people)

        #expect(first.contexts[0].pendingSets == second.contexts[0].pendingSets,
                       "Identical sessions must produce identical pending rows")
    }

    /// Field test 2026-08-20 #1: as the user logs the field sequence (Me, Me, P …)
    /// every intermediate pending list stays alternating, and its first row is the
    /// performer who is genuinely next.
    @Test func pendingAlternationIsStableAsSetsAreLogged() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Alice", in: ctx)
        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)
        session.plannedRepLadder = [5, 5, 5]
        let people = try WorkoutRepository.allPeople(ctx)

        func pending(_ state: SessionRenderModel.State) -> [SessionRenderModel.PendingSetDisplay] {
            state.contexts[0].pendingSets
        }
        /// Decision D2: no two consecutive rows from the same performer while at
        /// least two performers still have outstanding rows. A same-performer
        /// tail is allowed only once the other performer has nothing left.
        func isFair(_ rows: [SessionRenderModel.PendingSetDisplay]) -> Bool {
            var owed: [UUID?: Int] = [:]
            for row in rows { owed[row.performerID, default: 0] += 1 }
            var emitted: [UUID?: Int] = [:]
            for (index, row) in rows.enumerated() {
                if index > 0, rows[index - 1].performerID == row.performerID {
                    for (performer, total) in owed where performer != row.performerID {
                        if total - (emitted[performer, default: 0]) > 0 { return false }
                    }
                }
                emitted[row.performerID, default: 0] += 1
            }
            return true
        }

        // The user logs an owner set first (Me-heavy start, the field report).
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        var rows = pending(SessionRenderModel.build(session: session, prRule: .topWeight,
                                                    formula: .epley, allPeople: people))
        #expect(isFair(rows), "Pending rows repeat a performer after the first owner set")
        #expect(rows.first?.performerID == partner.id,
                       "The partner is genuinely next after an owner-led start")

        // The user logs a second owner set anyway.
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 100, reps: 5, in: ctx)
        rows = pending(SessionRenderModel.build(session: session, prRule: .topWeight,
                                                formula: .epley, allPeople: people))
        #expect(isFair(rows), "Pending rows repeat a performer after two owner sets")
        #expect(rows.first?.performerID == partner.id,
                       "The partner must be next — the card cannot demand the owner again")

        // The user logs the partner's set; alternation continues.
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 60, reps: 10,
                                         performedBy: partner, in: ctx)
        rows = pending(SessionRenderModel.build(session: session, prRule: .topWeight,
                                                formula: .epley, allPeople: people))
        #expect(isFair(rows), "Pending rows repeat a performer after the partner set")
        #expect(rows.first?.performerID == partner.id,
                       "The partner still leads after logging their first set")
    }

    // MARK: - Collapsed per-partner "last time" (field test 2026-08-20 issue 2, decision D5)

    private func display(_ weight: Double, _ reps: Int, bodyweight: Bool = false) -> SessionRenderModel.SetDisplay {
        SessionRenderModel.SetDisplay(
            setID: UUID(), weight: weight, reps: reps, rpe: nil, isWarmup: false,
            usesBodyweight: bodyweight, isOwnerSet: true, performedBy: nil, isAllTimePR: false)
    }

    /// Two prior sessions — the owner and the partner each logged Bench Press —
    /// then a fresh partner session. The collapsed summary must show one segment
    /// per performer, owner first, in roster order, with NO combined `x/y sets`.
    @Test func compactSummaryWithPartnersShowsPerPerformerLastTime() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        let past = try WorkoutRepository.createSession(in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 90, reps: 6, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 55, reps: 20,
                                          performedBy: partner, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 60, reps: 15,
                                          performedBy: partner, in: ctx)

        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx))

        let summary = SessionRenderModel.compactSummary(context: state.contexts[0], unit: .kilograms)
        #expect(summary == "Me: 80 kg × 5, 90 kg × 6; Sam: 55 kg × 20, 60 kg × 15",
                       "The collapsed card must show per-performer prior sets, owner first")
    }

    @Test func compactSummaryWithPartnersNeverCombinesSetCounts() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        let past = try WorkoutRepository.createSession(in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 60, reps: 15,
                                          performedBy: partner, in: ctx)

        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx))

        let summary = SessionRenderModel.compactSummary(context: state.contexts[0], unit: .kilograms)
        #expect(!summary.contains("sets"),
                       "The combined `6/6 sets` count must not appear when partners have history")
        #expect(summary.contains("; "),
                       "Partner segments must be joined, not combined")
    }

    @Test func compactSummaryOmitsPartnerWithNoHistory() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        let past = try WorkoutRepository.createSession(in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: past, exercise: bench, weightKg: 90, reps: 6, in: ctx)

        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx))

        let summary = SessionRenderModel.compactSummary(context: state.contexts[0], unit: .kilograms)
        #expect(summary == "Me: 80 kg × 5, 90 kg × 6",
                       "A partner with no prior sets contributes no segment")
    }

    @Test func compactSummaryFallsBackWhenNobodyHasHistory() throws {
        let ctx = try makeContext()
        let partner = try WorkoutRepository.findOrCreatePerson(named: "Sam", in: ctx)
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        let session = try WorkoutRepository.createSession(title: "Test",
                                                          partnerIDs: [partner.id.uuidString], in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        session.plannedRepLadder = [5, 5]

        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx))

        let summary = SessionRenderModel.compactSummary(context: state.contexts[0], unit: .kilograms)
        #expect(summary.contains("sets"),
                       "With no prior history the card must fall back to the counts summary, never blank")
        #expect(summary.contains("Sam"),
                       "The fallback keeps the partner label, as the old summary did")
    }

    @Test func compactSummarySoloUnchanged() throws {
        let ctx = try makeContext()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", in: ctx)

        let session = try WorkoutRepository.createSession(in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 80, reps: 5, in: ctx)
        _ = try WorkoutRepository.addSet(to: session, exercise: bench, weightKg: 90, reps: 6, in: ctx)

        let state = SessionRenderModel.build(session: session, prRule: .topWeight, formula: .epley,
                                             allPeople: try WorkoutRepository.allPeople(ctx))

        let summary = SessionRenderModel.compactSummary(context: state.contexts[0], unit: .kilograms)
        #expect(summary == "2/2 sets · 5–6 reps · 80 kg–90 kg",
                       "Solo sessions must keep the exact existing combined summary")
    }

    @Test func lastTimeSegmentBodyweightFormat() {
        #expect(SessionRenderModel.lastTimeSegment(
            label: "Me", sets: [display(0, 12, bodyweight: true)], unit: .kilograms) ==
            "Me: BW × 12")
        #expect(SessionRenderModel.lastTimeSegment(
            label: "Me", sets: [display(10, 12, bodyweight: true)], unit: .kilograms) ==
            "Me: BW + 10 kg × 12")
        #expect(SessionRenderModel.lastTimeSegment(label: "Me", sets: [], unit: .kilograms) == nil,
                     "No prior sets → no segment, never a fake 0")
    }

    @Test func lastTimeSegmentPerSelectedPerformer() {
        // The set editor's History card builds one "Last time" line from the
        // SELECTED performer's own prior sets (field test 2026-08-20 issue 3).
        let me = SessionRenderModel.lastTimeSegment(
            label: "Me", sets: [display(80, 5), display(90, 6)], unit: .kilograms)
        let sam = SessionRenderModel.lastTimeSegment(
            label: "Sam", sets: [display(55, 20), display(60, 15)], unit: .kilograms)
        #expect(me == "Me: 80 kg × 5, 90 kg × 6")
        #expect(sam == "Sam: 55 kg × 20, 60 kg × 15")
        #expect(SessionRenderModel.lastTimeSegment(label: "Sam", sets: [], unit: .kilograms) == nil,
                     "A performer with no prior sets on the movement gets no segment")
    }

    @Test func setLineTextUnitAndRoundtrip() {
        #expect(SessionRenderModel.setLineText(display(100, 5), unit: .kilograms) == "100 kg × 5")
        #expect(SessionRenderModel.setLineText(display(100, 5), unit: .pounds) == "220.5 lb × 5")
        #expect(SessionRenderModel.setLineText(display(90.7185, 8), unit: .kilograms) == "90.7 kg × 8")
        #expect(SessionRenderModel.setLineText(display(100, 5, bodyweight: true), unit: .pounds) ==
                       "BW + 220.5 lb × 5")
    }
}
#endif
