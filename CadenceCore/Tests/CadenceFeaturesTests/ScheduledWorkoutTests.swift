import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

@MainActor
final class ScheduledWorkoutTests: XCTestCase {
    func testPayloadRoundTripPreservesFractionalLoadsRepsPartnersAndStyle() throws {
        let partnerID = UUID()
        let plan = EditablePlan(
            title: "Olympic technique",
            warmupMinutes: 5,
            cooldownMinutes: 4,
            exercises: [EditableExercise(
                name: "Clean and Jerk",
                sets: [
                    EditableSet(targetReps: 12, targetWeight: 28.5),
                    EditableSet(targetReps: 10, targetWeight: 32.5),
                    EditableSet(targetReps: 8, targetWeight: 53)
                ],
                notes: "Keep the catch controlled",
                performerPlans: [EditablePerformerPlan(
                    performerID: partnerID,
                    name: "Sam",
                    sets: [EditableSet(targetReps: 8, targetWeight: 20.5)])]
            )],
            partnerIDs: [partnerID],
            suggestedWorkoutStyle: .olympic)

        let decoded = try ScheduledWorkoutStore.decode(
            try ScheduledWorkoutStore.encode(plan),
            version: ScheduledWorkoutStore.currentPayloadVersion)

        XCTAssertEqual(decoded.title, plan.title)
        XCTAssertEqual(decoded.warmupMinutes, 5)
        XCTAssertEqual(decoded.cooldownMinutes, 4)
        XCTAssertEqual(decoded.partnerIDs, [partnerID])
        XCTAssertEqual(decoded.suggestedWorkoutStyle, .olympic)
        XCTAssertEqual(decoded.exercises.first?.sets.map(\.targetReps), [12, 10, 8])
        XCTAssertEqual(decoded.exercises.first?.sets.map(\.targetWeight), [28.5, 32.5, 53])
        XCTAssertEqual(decoded.exercises.first?.performerPlans.first?.sets.first?.targetWeight, 20.5)
    }

    func testSchedulingIsDateOnlyAndDuplicateSameDayRecordsRemainDeterministic() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20,
                                                       hour: 12, minute: 30))!
        let plan = EditablePlan(title: "Custom Workout", warmupMinutes: 0,
                                cooldownMinutes: 0, exercises: [])

        let first = try ScheduledWorkoutStore.schedule(plan: plan, for: noon,
                                                        calendar: calendar, in: context)
        let second = try ScheduledWorkoutStore.schedule(
            plan: EditablePlan(title: "Evening Workout", warmupMinutes: 0,
                               cooldownMinutes: 0, exercises: []),
            for: noon.addingTimeInterval(3600), calendar: calendar, in: context)

        XCTAssertEqual(first.scheduledDate, calendar.startOfDay(for: noon))
        XCTAssertEqual(first.scheduledDayKey, "2026-09-20")
        XCTAssertEqual(second.scheduledDayKey, first.scheduledDayKey)
        let active = try ScheduledWorkoutStore.active(in: context)
        XCTAssertEqual(active.map(\.title), ["Custom Workout", "Evening Workout"])

        first.status = .cancelled
        first.deletedAt = Date()
        try context.save()
        XCTAssertEqual(try ScheduledWorkoutStore.active(in: context).map(\.title), ["Evening Workout"])
    }

    func testSchedulingRejectsPastDaysAndReschedulingResetsStartedLifecycle() throws {
        let container = try CadenceStore.makeModelContainer(inMemory: true)
        let context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20,
                                                       hour: 9))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        let plan = EditablePlan(title: "Move me", warmupMinutes: 0,
                                cooldownMinutes: 0, exercises: [])

        XCTAssertThrowsError(try ScheduledWorkoutStore.schedule(plan: plan,
                                                                 for: yesterday,
                                                                 calendar: calendar,
                                                                 now: now,
                                                                 in: context)) { error in
            XCTAssertEqual(error as? ScheduledWorkoutStoreError, .dateMustBeTodayOrFuture)
        }
        let record = try ScheduledWorkoutStore.schedule(plan: plan, for: now,
                                                         calendar: calendar, now: now,
                                                         in: context)
        let sessionID = UUID()
        XCTAssertTrue(try ScheduledWorkoutStore.markStarted(recordID: record.id,
                                                             sessionID: sessionID, in: context))
        XCTAssertTrue(try ScheduledWorkoutStore.reschedule(recordID: record.id,
                                                           to: tomorrow,
                                                           calendar: calendar,
                                                           now: now,
                                                           in: context))
        XCTAssertEqual(record.scheduledDayKey, "2026-09-21")
        XCTAssertEqual(record.status, .scheduled)
        XCTAssertNil(record.startedSessionID)
    }

    func testPresenterSeparatesTodayFutureAndOverdueAndHidesCompleted() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let calendar = Calendar(identifier: .gregorian)
        let items = [
            PlannedWorkoutsPresenter.Item(id: UUID(), date: now.addingTimeInterval(-86_400),
                                          title: "Old", detail: "", status: .scheduled),
            PlannedWorkoutsPresenter.Item(id: UUID(), date: now,
                                          title: "Today", detail: "", status: .scheduled),
            PlannedWorkoutsPresenter.Item(id: UUID(), date: now.addingTimeInterval(86_400),
                                          title: "Future", detail: "", status: .started),
            PlannedWorkoutsPresenter.Item(id: UUID(), date: now,
                                          title: "Done", detail: "", status: .completed)
        ]

        XCTAssertEqual(PlannedWorkoutsPresenter.today(items, now: now, calendar: calendar).map(\.title), ["Today"])
        XCTAssertEqual(PlannedWorkoutsPresenter.todayAndFuture(items, now: now, calendar: calendar).map(\.title), ["Today", "Future"])
        XCTAssertEqual(PlannedWorkoutsPresenter.overdue(items, now: now, calendar: calendar).map(\.title), ["Old"])
        XCTAssertTrue(PlannedWorkoutsPresenter.showsMore(items, now: now, calendar: calendar))
    }

    func testLifecycleLinksStartCompletesAndCanBeAbandonedOrTombstoned() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let plan = EditablePlan(title: "Lifecycle", warmupMinutes: 0,
                                cooldownMinutes: 0, exercises: [])
        let scheduled = try ScheduledWorkoutStore.schedule(plan: plan, for: Date(), in: context)
        let sessionID = UUID()

        XCTAssertTrue(try ScheduledWorkoutStore.markStarted(recordID: scheduled.id,
                                                            sessionID: sessionID, in: context))
        XCTAssertEqual(scheduled.status, .started)
        XCTAssertEqual(scheduled.startedSessionID, sessionID)
        XCTAssertTrue(try ScheduledWorkoutStore.markAbandoned(recordID: scheduled.id, in: context))
        XCTAssertEqual(scheduled.status, .scheduled)
        XCTAssertNil(scheduled.startedSessionID)
        XCTAssertTrue(try ScheduledWorkoutStore.markStarted(recordID: scheduled.id,
                                                            sessionID: sessionID, in: context))
        XCTAssertTrue(try ScheduledWorkoutStore.markCompleted(recordID: scheduled.id, in: context))
        XCTAssertFalse(try ScheduledWorkoutStore.markAbandoned(recordID: scheduled.id, in: context))

        let deleted = try ScheduledWorkoutStore.schedule(plan: plan, for: Date(), in: context)
        XCTAssertTrue(try ScheduledWorkoutStore.cancel(recordID: deleted.id, in: context))
        XCTAssertNotNil(deleted.deletedAt)
        XCTAssertFalse(try ScheduledWorkoutStore.active(in: context).contains { $0.id == deleted.id })
    }
}
