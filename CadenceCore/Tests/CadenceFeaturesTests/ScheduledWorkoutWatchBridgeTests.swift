import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Pure, headless tests for surfacing a user's manually scheduled workout on
/// Watch Today without suppressing a coach suggestion of a different modality
/// (NFR-8: the coach suggests, it does not proscribe).
final class ScheduledWorkoutWatchBridgeTests: XCTestCase {
    private func strengthPayload() throws -> Data {
        let plan = EditablePlan(
            title: "Push Day",
            warmupMinutes: 5,
            cooldownMinutes: 5,
            exercises: [
                EditableExercise(name: "Bench Press",
                                 sets: [EditableSet(targetReps: 8, targetWeight: 60),
                                        EditableSet(targetReps: 6, targetWeight: 70)],
                                 notes: ""),
                EditableExercise(name: "Overhead Press",
                                 sets: [EditableSet(targetReps: 10, targetWeight: 30)],
                                 notes: "")
            ])
        return try ScheduledWorkoutStore.encode(plan)
    }

    private func cardioPayload(_ type: CardioType = .run) throws -> Data {
        try ScheduledWorkoutStore.encode(cardioType: type)
    }

    // MARK: - session(...)

    func testSessionDecodesStrengthPlanWithExerciseNamesAndRepLadder() throws {
        let id = UUID()
        let session = try XCTUnwrap(ScheduledWorkoutWatchBridge.session(
            id: id, title: "Push Day", payloadData: strengthPayload(),
            payloadVersion: ScheduledWorkoutStore.currentPayloadVersion))

        XCTAssertEqual(session.kind, .strength)
        XCTAssertEqual(session.exerciseNames, ["Bench Press", "Overhead Press"])
        XCTAssertEqual(session.repLadder, [8, 6])
    }

    func testSessionDecodesCardioTypeAndMatchesRawValue() throws {
        let id = UUID()
        let session = try XCTUnwrap(ScheduledWorkoutWatchBridge.session(
            id: id, title: "Morning Run", payloadData: cardioPayload(.run),
            payloadVersion: ScheduledWorkoutStore.currentPayloadVersion))

        XCTAssertEqual(session.kind, .cardio)
        XCTAssertEqual(session.cardioType, CardioType.run.rawValue)
    }

    func testSessionReturnsNilForUndecodablePayload() {
        let garbage = Data([0x00, 0x01, 0x02, 0xFF])
        let session = ScheduledWorkoutWatchBridge.session(
            id: UUID(), title: "Mystery", payloadData: garbage,
            payloadVersion: ScheduledWorkoutStore.currentPayloadVersion)
        XCTAssertNil(session)
    }

    // MARK: - todaySessions(...)

    func testTodaySessionsFiltersByDayAndStatus() throws {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let payload = try strengthPayload()
        let version = ScheduledWorkoutStore.currentPayloadVersion

        let inputs: [ScheduledWorkoutWatchBridge.Input] = [
            .init(id: UUID(), date: yesterday, title: "Yesterday", payloadData: payload,
                  payloadVersion: version, status: .scheduled),
            .init(id: UUID(), date: tomorrow, title: "Tomorrow", payloadData: payload,
                  payloadVersion: version, status: .scheduled),
            .init(id: UUID(), date: now, title: "Cancelled Today", payloadData: payload,
                  payloadVersion: version, status: .cancelled),
            .init(id: UUID(), date: now, title: "Completed Today", payloadData: payload,
                  payloadVersion: version, status: .completed),
            .init(id: UUID(), date: now, title: "Scheduled Today", payloadData: payload,
                  payloadVersion: version, status: .scheduled),
            .init(id: UUID(), date: now, title: "Started Today", payloadData: payload,
                  payloadVersion: version, status: .started)
        ]

        let sessions = ScheduledWorkoutWatchBridge.todaySessions(inputs, now: now, calendar: calendar)

        XCTAssertEqual(sessions.map(\.label), ["Scheduled Today", "Started Today"])
    }

    // MARK: - merge(...)

    func testMergePrependsScheduledSessionsAheadOfCoachSessionsOfTheSameKind() throws {
        let scheduledID = UUID().uuidString
        let coachID = UUID().uuidString
        let coachCardioID = UUID().uuidString

        let scheduledStrength = WatchSync.TodayPlan.Session(
            id: scheduledID, kind: .strength, label: "User's Push Day",
            exerciseNames: ["Bench Press"], repLadder: [8])
        let coachStrength = WatchSync.TodayPlan.Session(
            id: coachID, kind: .strength, label: "Coach Strength",
            exerciseNames: ["Squat"], repLadder: [5])
        let coachCardio = WatchSync.TodayPlan.Session(
            id: coachCardioID, kind: .cardio, label: "Coach Cardio",
            cardioType: "run", durationMinutes: 30)

        let base = WatchSync.TodayPlan(sessions: [coachStrength, coachCardio], updatedAt: Date())
        let merged = ScheduledWorkoutWatchBridge.merge(scheduledSessions: [scheduledStrength], into: base)

        XCTAssertEqual(merged.sessions.count, 3)
        let firstStrength = try XCTUnwrap(merged.sessions.first { $0.isStrength })
        XCTAssertEqual(firstStrength.id, scheduledID)
        XCTAssertTrue(merged.sessions.contains { $0.id == coachCardioID })
    }

    func testMergeWithEmptyScheduledSessionsReturnsBaseUnchanged() {
        let base = WatchSync.TodayPlan(
            sessions: [WatchSync.TodayPlan.Session(id: "coach-1", kind: .cardio, label: "Coach Cardio")],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let merged = ScheduledWorkoutWatchBridge.merge(scheduledSessions: [], into: base)

        XCTAssertEqual(merged, base)
    }
}
