import XCTest
@testable import CadenceCore
@testable import CadenceFeatures

@MainActor
final class ManualCardioMinutesSaverTests: XCTestCase {
    private struct Boom: Error {}

    func testExistingValuesDoNotFlashZero() {
        XCTAssertNil(ManualCardioMinutesSaver.existingMinutes(from: nil))
        let s = WorkoutSession(title: "Lift", date: Date())
        s.setManualCardioMinutes(moderate: 17, vigorous: 11)
        XCTAssertEqual(ManualCardioMinutesSaver.existingMinutes(from: s.intensitySummary),
                       .init(moderate: 17, vigorous: 11))
    }

    func testExistingAutomaticIntensitySeedsTheEditor() {
        let automatic = CardioMinuteSummary(
            actualDuration: 1_800, classifiedDuration: 1_800,
            unclassifiedDuration: 0, belowModerateDuration: 120,
            moderateDuration: 960, vigorousDuration: 720, zoneDurations: [:],
            method: .heartRateReserve, confidence: .high)

        XCTAssertEqual(ManualCardioMinutesSaver.existingMinutes(from: automatic),
                       .init(moderate: 16, vigorous: 12))
    }

    func testFirstSaveFromNilSummaryPersistsManualOverride() {
        let s = WorkoutSession(title: "Lift", date: Date())
        XCTAssertNil(s.intensitySummary)
        var persisted = false
        let result = ManualCardioMinutesSaver.save(session: s, moderate: 12, vigorous: 3,
                                                   persist: { persisted = true }, center: NotificationCenter())
        XCTAssertNoThrow(try result.get())
        XCTAssertTrue(persisted)
        XCTAssertTrue(s.hasManualCardioMinutesOverride)
        XCTAssertEqual(ManualCardioMinutesSaver.existingMinutes(from: s.intensitySummary),
                       .init(moderate: 12, vigorous: 3))
    }

    func testNotificationPostedAfterPersist() {
        let s = WorkoutSession(title: "Lift", date: Date())
        let center = NotificationCenter()
        var persisted = false
        var postedAfterPersist = false
        let token = center.addObserver(forName: .workoutHistoryChanged, object: nil, queue: nil) { _ in
            postedAfterPersist = persisted
        }
        defer { center.removeObserver(token) }
        let result = ManualCardioMinutesSaver.save(session: s, moderate: 20, vigorous: 5,
                                                   persist: { persisted = true }, center: center)
        XCTAssertNoThrow(try result.get())
        XCTAssertTrue(postedAfterPersist)
        XCTAssertEqual(s.intensitySummary.map { $0.moderateDuration }, 1200)
    }

    func testFailedSaveRollsBackAndDoesNotNotify() {
        let s = WorkoutSession(title: "Lift", date: Date())
        s.setManualCardioMinutes(moderate: 10, vigorous: 2)
        let center = NotificationCenter()
        var posted = false
        let token = center.addObserver(forName: .workoutHistoryChanged, object: nil, queue: nil) { _ in posted = true }
        defer { center.removeObserver(token) }
        let result = ManualCardioMinutesSaver.save(session: s, moderate: 99, vigorous: 99,
                                                   persist: { throw Boom() }, center: center)
        XCTAssertThrowsError(try result.get())
        XCTAssertFalse(posted)
        XCTAssertEqual(ManualCardioMinutesSaver.existingMinutes(from: s.intensitySummary),
                       .init(moderate: 10, vigorous: 2))
    }
}
