import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchHRRelayScheduleTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func firstReadingIsNewAndSendsNow() {
        var schedule = WatchHRRelaySchedule()
        let isNew = schedule.observeReading(endingAt: t0, uptime: 0)
        #expect(isNew)
        #expect(schedule.delayBeforeSending(uptime: 50) == 0)
    }

    @Test func theSameSampleSeenAgainIsNotNew() {
        var schedule = WatchHRRelaySchedule()
        let first = schedule.observeReading(endingAt: t0, uptime: 0)
        #expect(first)
        let repeated = schedule.observeReading(endingAt: t0, uptime: 0)
        #expect(!repeated, "the display poll re-reads the latest statistic")
        let older = schedule.observeReading(endingAt: t0.addingTimeInterval(-3), uptime: 0)
        #expect(!older, "an older sample arriving late")
        let newer = schedule.observeReading(endingAt: t0.addingTimeInterval(5), uptime: 0)
        #expect(newer)
    }

    @Test func readingsWithoutTimestampsAreAlwaysNew() {
        var schedule = WatchHRRelaySchedule()
        let first = schedule.observeReading(endingAt: nil, uptime: 0)
        #expect(first)
        let second = schedule.observeReading(endingAt: nil, uptime: 0)
        #expect(second)
    }

    @Test func aReadingInsideTheGapWaitsForTheRest() {
        var schedule = WatchHRRelaySchedule()
        schedule.recordSend(uptime: 100)
        #expect(abs(schedule.delayBeforeSending(uptime: 100.25) - 0.75) <= 0.0001)
        #expect(schedule.delayBeforeSending(uptime: 101) == 0)
        #expect(schedule.delayBeforeSending(uptime: 106) == 0)
    }

    @Test func uptimeGoingBackwardDoesNotStallTheRelay() {
        var schedule = WatchHRRelaySchedule()
        schedule.recordSend(uptime: 500)
        #expect(schedule.delayBeforeSending(uptime: 10) == 0)
    }

    @Test func heartbeatStopsAfterFifteenSecondsWithoutANewReading() {
        var schedule = WatchHRRelaySchedule()
        #expect(!schedule.isNewestReadingStale(uptime: 100), "no reading yet")
        let first = schedule.observeReading(endingAt: t0, uptime: 100)
        #expect(first)
        #expect(!schedule.isNewestReadingStale(uptime: 115))
        #expect(schedule.isNewestReadingStale(uptime: 115.5))
        let reread = schedule.observeReading(endingAt: t0, uptime: 116)
        #expect(!reread, "a re-read is not a new reading")
        #expect(schedule.isNewestReadingStale(uptime: 116))
        let strap = schedule.observeReading(endingAt: nil, uptime: 117)
        #expect(strap, "a strap reading counts as new")
        #expect(!schedule.isNewestReadingStale(uptime: 117))
    }

    @Test func aLateHealthKitReadingIsFreshWhenItArrives() {
        var schedule = WatchHRRelaySchedule()
        // HealthKit can deliver a sample well after it was taken.
        let isNew = schedule.observeReading(endingAt: t0.addingTimeInterval(-40), uptime: 200)
        #expect(isNew)
        #expect(!schedule.isNewestReadingStale(uptime: 200))
    }

    @Test func resetForgetsReadingsAndSends() {
        var schedule = WatchHRRelaySchedule()
        _ = schedule.observeReading(endingAt: t0, uptime: 0)
        schedule.recordSend(uptime: 100)
        schedule.reset()
        #expect(schedule == WatchHRRelaySchedule())
        let isNew = schedule.observeReading(endingAt: t0, uptime: 0)
        #expect(isNew)
        #expect(schedule.delayBeforeSending(uptime: 100.1) == 0)
    }

    @Test func heartbeatKeepsThePhoneWellInsideItsStaleWindow() {
        #expect(WatchHRRelaySchedule.heartbeatInterval == 5)
        #expect(WatchHRRelay.staleAfter == 3 * WatchHRRelaySchedule.heartbeatInterval)
        #expect(WatchHRRelaySchedule.minimumGap < WatchHRRelaySchedule.heartbeatInterval)
    }
}
