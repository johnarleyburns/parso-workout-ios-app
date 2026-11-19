import Testing
import Foundation
import CadencePhoneFeatures
@testable import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

@MainActor
@Suite final class ManualCardioMinutesSaverTests {
    private struct Boom: Error {}

    @Test func existingValuesDoNotFlashZero() {
        #expect(ManualCardioMinutesSaver.existingMinutes(from: nil) == nil)
        let s = WorkoutSession(title: "Lift", date: Date())
        s.setManualCardioMinutes(moderate: 17, vigorous: 11)
        #expect(ManualCardioMinutesSaver.existingMinutes(from: s.intensitySummary)
               == .init(moderate: 17, vigorous: 11))
    }

    @Test func existingAutomaticIntensitySeedsTheEditor() {
        let automatic = CardioMinuteSummary(
            actualDuration: 1_800, classifiedDuration: 1_800,
            unclassifiedDuration: 0, belowModerateDuration: 120,
            moderateDuration: 960, vigorousDuration: 720, zoneDurations: [:],
            method: .heartRateReserve, confidence: .high)

        #expect(ManualCardioMinutesSaver.existingMinutes(from: automatic)
               == .init(moderate: 16, vigorous: 12))
    }

    @Test func firstSaveFromNilSummaryPersistsManualOverride() throws {
        let s = WorkoutSession(title: "Lift", date: Date())
        #expect(s.intensitySummary == nil)
        var persisted = false
        let result = ManualCardioMinutesSaver.save(session: s, moderate: 12, vigorous: 3,
                                                   persist: { persisted = true }, center: NotificationCenter())
        #expect(throws: Never.self) { try result.get() }
        #expect(persisted)
        #expect(s.hasManualCardioMinutesOverride)
        #expect(ManualCardioMinutesSaver.existingMinutes(from: s.intensitySummary)
               == .init(moderate: 12, vigorous: 3))
    }

    @Test func notificationPostedAfterPersist() {
        let s = WorkoutSession(title: "Lift", date: Date())
        let center = NotificationCenter()
        // `queue: nil` posts synchronously on the posting thread (here, this
        // MainActor test), so the mutation below is never actually concurrent;
        // the closure's plain `@Sendable` signature just can't express that.
        nonisolated(unsafe) var persisted = false
        nonisolated(unsafe) var postedAfterPersist = false
        let token = center.addObserver(forName: .workoutHistoryChanged, object: nil, queue: nil) { _ in
            postedAfterPersist = persisted
        }
        defer { center.removeObserver(token) }
        let result = ManualCardioMinutesSaver.save(session: s, moderate: 20, vigorous: 5,
                                                   persist: { persisted = true }, center: center)
        #expect(throws: Never.self) { try result.get() }
        #expect(postedAfterPersist)
        #expect(s.intensitySummary.map { $0.moderateDuration } == 1200)
    }

    @Test func failedSaveRollsBackAndDoesNotNotify() {
        let s = WorkoutSession(title: "Lift", date: Date())
        s.setManualCardioMinutes(moderate: 10, vigorous: 2)
        let center = NotificationCenter()
        nonisolated(unsafe) var posted = false
        let token = center.addObserver(forName: .workoutHistoryChanged, object: nil, queue: nil) { _ in posted = true }
        defer { center.removeObserver(token) }
        let result = ManualCardioMinutesSaver.save(session: s, moderate: 99, vigorous: 99,
                                                   persist: { throw Boom() }, center: center)
        #expect(throws: (any Error).self) { try result.get() }
        #expect(!posted)
        #expect(ManualCardioMinutesSaver.existingMinutes(from: s.intensitySummary)
               == .init(moderate: 10, vigorous: 2))
    }
}
