import XCTest
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceFixtures

/// The single highest-value test gained from the whole test-pyramid exercise:
/// `HomeCoachModel.Signature` is the equatable key that decides when the entire
/// coach pipeline re-runs. Getting this wrong either stalls the app (re-running on
/// every logged set) or shows stale coaching. Previously guarded only by one flaky
/// XCUITest; now covered headlessly.
@MainActor
final class HomeCoachModelTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        return ModelContext(container)
    }

    private func sig(token: UUID = UUID(),
                     sessions: [WorkoutSession] = [],
                     cardio: [CardioWorkout] = [],
                     assessments: [Assessment] = [],
                     readiness: [ReadinessEntry] = [],
                     goal: TrainingGoal = .strength,
                     experience: ExperienceLevel = .intermediate,
                     formula: OneRepMaxFormula = .epley,
                     schedule: CoachSchedulePreferences = .default,
                     profile: CoachPreferenceProfile = .empty,
                     now: Date = Date()) -> HomeCoachModel.Signature {
        HomeCoachModel.signature(token: token, sessions: sessions, cardio: cardio,
                                 assessments: assessments, readiness: readiness,
                                 goal: goal, experience: experience, formula: formula,
                                 schedule: schedule, profile: profile, now: now)
    }

    func testIdenticalInputsProduceEqualSignatures() {
        let token = UUID()
        XCTAssertEqual(sig(token: token), sig(token: token))
    }

    func testAddingASessionChangesSignature() throws {
        let ctx = try makeContext()
        let token = UUID()
        let s1 = WorkoutSession(title: "A", date: Date()); ctx.insert(s1)
        let before = sig(token: token, sessions: [s1])
        let s2 = WorkoutSession(title: "B", date: Date()); ctx.insert(s2)
        let after = sig(token: token, sessions: [s1, s2])
        XCTAssertNotEqual(before, after)
    }

    func testAddingASetToExistingSessionDoesNotChangeSignature() throws {
        // The whole point of the optimization: per-set churn must NOT invalidate the
        // coach cache. Session count is unchanged and the token is not bumped.
        let ctx = try makeContext()
        let token = UUID()
        let bench = try WorkoutRepository.findOrCreateExercise(named: "Bench Press", category: .push, in: ctx)
        let s = WorkoutSession(title: "Push", date: Date()); ctx.insert(s)
        let before = sig(token: token, sessions: [s])
        ctx.insert(SetEntry(weight: 100, reps: 5, order: 0, completedAt: s.date, session: s, exercise: bench))
        try ctx.save()
        let after = sig(token: token, sessions: [s])
        XCTAssertEqual(before, after)
    }

    func testBumpingTokenChangesSignature() {
        let base = sig(token: UUID())
        let bumped = sig(token: UUID())
        XCTAssertNotEqual(base, bumped)
    }

    func testChangingGoalChangesSignature() {
        let token = UUID()
        XCTAssertNotEqual(sig(token: token, goal: .strength), sig(token: token, goal: .hypertrophy))
    }

    func testChangingSchedulePreferencesChangesSignature() {
        let token = UUID()
        let a = sig(token: token, schedule: .default)
        let b = sig(token: token, schedule: CoachSchedulePreferences.default.withTwoADays(true))
        XCTAssertNotEqual(a, b)
    }

    func testChangingDesiredSetsChangesSignature() {
        let token = UUID()
        let a = sig(token: token, schedule: .default)
        let b = sig(token: token, schedule: CoachSchedulePreferences.default.withDesiredSetsPerExercise(4))
        XCTAssertNotEqual(a, b)
    }

    func testPainTodayChangesSignature() throws {
        let ctx = try makeContext()
        let token = UUID()
        let painful = ReadinessEntry(date: Date(), hasPainOrIllnessConcern: true)
        ctx.insert(painful)
        let withPain = sig(token: token, readiness: [painful])
        let withoutPain = sig(token: token, readiness: [])
        XCTAssertNotEqual(withPain, withoutPain)
        XCTAssertTrue(withPain.painToday)
        XCTAssertFalse(withoutPain.painToday)
    }

    func testPainYesterdayDoesNotCountAsPainToday() throws {
        let ctx = try makeContext()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let old = ReadinessEntry(date: yesterday, hasPainOrIllnessConcern: true)
        ctx.insert(old)
        XCTAssertFalse(HomeCoachModel.painToday(readiness: [old]))
    }

    func testSnapshotRunsPipelineFromSeededHistory() throws {
        let ctx = try makeContext()
        Fixtures.coachAerobicGap(into: ctx)
        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSession>())
        let cardio = try ctx.fetch(FetchDescriptor<CardioWorkout>())
        let snapshot = HomeCoachModel.snapshot(
            sessions: sessions, cardio: cardio, assessments: [], readiness: [],
            goal: .strength, experience: .intermediate, formula: .epley,
            schedule: .default, profile: .empty)
        XCTAssertNotNil(snapshot.decision.primary)
    }

    func testSnapshotAsyncConcurrentCallersDoNotFaultCardioRelationshipsOffMainActor() async throws {
        let ctx = try makeContext()
        let start = Date().addingTimeInterval(-3_600)
        let workout = CardioWorkout(type: .run,
                                    start: start,
                                    end: start.addingTimeInterval(1_800),
                                    avgHeartRate: nil,
                                    maxHeartRate: nil)
        ctx.insert(workout)
        for offset in 0..<120 {
            ctx.insert(HRSample(t: TimeInterval(offset * 10),
                                bpm: Double(120 + (offset % 30)),
                                cardio: workout))
        }
        try ctx.save()
        let cardio = try ctx.fetch(FetchDescriptor<CardioWorkout>())

        var snapshots: [CoachSnapshot] = []
        for _ in 0..<8 {
            snapshots.append(await HomeCoachModel.snapshotAsync(
                sessions: [], cardio: cardio, assessments: [], readiness: [],
                goal: .strength, experience: .intermediate, formula: .epley,
                schedule: .default, profile: .empty))
        }

        XCTAssertEqual(snapshots.count, 8)
        XCTAssertTrue(snapshots.allSatisfy { $0.coachFacts.events.count == 1 })
    }

    func testSnapshotAsyncRetainsFinalizedPhoneCustomExerciseVolume() async throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let ctx = try makeContext()
        let session = try WorkoutRepository.createSession(
            title: "Phone custom abs",
            date: now.addingTimeInterval(-3_600),
            in: ctx)
        let exercise = try WorkoutRepository.findOrCreateExercise(
            named: "Incline Crunches",
            category: .core,
            primaryMuscles: [MuscleGroup.abdominals.rawValue],
            in: ctx)
        for _ in 0..<3 {
            _ = try WorkoutRepository.addSet(
                to: session, exercise: exercise, weightKg: 0, reps: 15, in: ctx)
        }
        session.endedAt = now
        try ctx.save()

        let snapshot = await HomeCoachModel.snapshotAsync(
            sessions: [session], cardio: [], assessments: [], readiness: [],
            goal: .strength, experience: .intermediate, formula: .epley,
            schedule: .default, profile: .empty, now: now)

        XCTAssertEqual(snapshot.facts.weeklySetsByGroup[.abdominals], 3)
        XCTAssertEqual(snapshot.engineObservation?.effectiveSetsByGroup[.abdominals], 3)
        let dashboard = HomeDashboardPresenter.make(
            snapshot: snapshot, schedule: .default, goal: .strength,
            experience: .intermediate, userAge: nil)
        XCTAssertEqual(dashboard.volume.first { $0.group == .abdominals }?.sets, 3)
    }

    func testTestRecommendationNilWhenCoachHidden() throws {
        let ctx = try makeContext()
        _ = ctx
        XCTAssertNil(HomeCoachModel.testRecommendation(
            coachHidden: true, assessments: [], lastRecommendedAt: nil, snoozedUntil: [:]))
    }

}
