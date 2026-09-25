import XCTest
@testable import CadenceFeatures

final class WatchHRRelayScheduleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    func testFirstReadingIsNewAndSendsNow() {
        var schedule = WatchHRRelaySchedule()
        XCTAssertTrue(schedule.observeReading(endingAt: t0, uptime: 0))
        XCTAssertEqual(schedule.delayBeforeSending(uptime: 50), 0)
    }

    func testTheSameSampleSeenAgainIsNotNew() {
        var schedule = WatchHRRelaySchedule()
        XCTAssertTrue(schedule.observeReading(endingAt: t0, uptime: 0))
        XCTAssertFalse(schedule.observeReading(endingAt: t0, uptime: 0), "the display poll re-reads the latest statistic")
        XCTAssertFalse(schedule.observeReading(endingAt: t0.addingTimeInterval(-3), uptime: 0), "an older sample arriving late")
        XCTAssertTrue(schedule.observeReading(endingAt: t0.addingTimeInterval(5), uptime: 0))
    }

    func testReadingsWithoutTimestampsAreAlwaysNew() {
        var schedule = WatchHRRelaySchedule()
        XCTAssertTrue(schedule.observeReading(endingAt: nil, uptime: 0))
        XCTAssertTrue(schedule.observeReading(endingAt: nil, uptime: 0))
    }

    func testAReadingInsideTheGapWaitsForTheRest() {
        var schedule = WatchHRRelaySchedule()
        schedule.recordSend(uptime: 100)
        XCTAssertEqual(schedule.delayBeforeSending(uptime: 100.25), 0.75, accuracy: 0.0001)
        XCTAssertEqual(schedule.delayBeforeSending(uptime: 101), 0)
        XCTAssertEqual(schedule.delayBeforeSending(uptime: 106), 0)
    }

    func testUptimeGoingBackwardDoesNotStallTheRelay() {
        var schedule = WatchHRRelaySchedule()
        schedule.recordSend(uptime: 500)
        XCTAssertEqual(schedule.delayBeforeSending(uptime: 10), 0)
    }

    func testHeartbeatStopsAfterFifteenSecondsWithoutANewReading() {
        var schedule = WatchHRRelaySchedule()
        XCTAssertFalse(schedule.isNewestReadingStale(uptime: 100), "no reading yet")
        XCTAssertTrue(schedule.observeReading(endingAt: t0, uptime: 100))
        XCTAssertFalse(schedule.isNewestReadingStale(uptime: 115))
        XCTAssertTrue(schedule.isNewestReadingStale(uptime: 115.5))
        XCTAssertFalse(schedule.observeReading(endingAt: t0, uptime: 116), "a re-read is not a new reading")
        XCTAssertTrue(schedule.isNewestReadingStale(uptime: 116))
        XCTAssertTrue(schedule.observeReading(endingAt: nil, uptime: 117), "a strap reading counts as new")
        XCTAssertFalse(schedule.isNewestReadingStale(uptime: 117))
    }

    func testALateHealthKitReadingIsFreshWhenItArrives() {
        var schedule = WatchHRRelaySchedule()
        // HealthKit can deliver a sample well after it was taken.
        XCTAssertTrue(schedule.observeReading(endingAt: t0.addingTimeInterval(-40), uptime: 200))
        XCTAssertFalse(schedule.isNewestReadingStale(uptime: 200))
    }

    func testResetForgetsReadingsAndSends() {
        var schedule = WatchHRRelaySchedule()
        _ = schedule.observeReading(endingAt: t0, uptime: 0)
        schedule.recordSend(uptime: 100)
        schedule.reset()
        XCTAssertEqual(schedule, WatchHRRelaySchedule())
        XCTAssertTrue(schedule.observeReading(endingAt: t0, uptime: 0))
        XCTAssertEqual(schedule.delayBeforeSending(uptime: 100.1), 0)
    }

    func testHeartbeatKeepsThePhoneWellInsideItsStaleWindow() {
        XCTAssertEqual(WatchHRRelaySchedule.heartbeatInterval, 5)
        XCTAssertEqual(WatchHRRelay.staleAfter, 3 * WatchHRRelaySchedule.heartbeatInterval)
        XCTAssertLessThan(WatchHRRelaySchedule.minimumGap, WatchHRRelaySchedule.heartbeatInterval)
    }
}
