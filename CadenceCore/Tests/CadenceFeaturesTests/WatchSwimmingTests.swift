import XCTest
import CadenceFeatures

final class WatchSwimmingTests: XCTestCase {
    func testMutuallyExclusiveSwimConfigurations() {
        for length in [25.0, 50.0] {
            let pool = WatchSwimSetup.configuration(mode: .lapPool, poolLength: length)
            XCTAssertEqual(pool.poolLengthMeters, length)
            XCTAssertFalse(pool.usesGPS)
            let open = WatchSwimSetup.configuration(mode: .openWater, poolLength: length)
            XCTAssertTrue(open.usesGPS)
            XCTAssertNil(open.poolLengthMeters)
        }
        XCTAssertEqual(WatchSwimSetup.configuration(mode: .lapPool, poolLength: .nan).poolLengthMeters, 25)
    }

    func testNativeDistanceCountsPoolLengthsWithoutDuplicateEvents() {
        var progress = WatchSwimProgress(poolLengthMeters: 25)
        for (distance, laps) in [(0.0, 0), (24.9, 0), (25, 1), (25, 1), (50, 2), (100, 4)] {
            progress.update(distanceMeters: distance)
            XCTAssertEqual(progress.lapCount, laps)
        }
        progress.update(distanceMeters: 50) // late callback cannot undo completed lengths
        XCTAssertEqual(progress.distanceMeters, 100)
        XCTAssertEqual(progress.lapCount, 4)
    }

    func testFiftyMeterPoolAndOpenWater() {
        var pool = WatchSwimProgress(poolLengthMeters: 50)
        pool.update(distanceMeters: 200)
        XCTAssertEqual(pool.lapCount, 4)
        var open = WatchSwimProgress(poolLengthMeters: nil)
        open.update(distanceMeters: 200)
        XCTAssertEqual(open.distanceMeters, 200)
        XCTAssertNil(open.lapCount)
    }

    func testInvalidMeasurementsDoNotInventLapsOrCrash() {
        var pool = WatchSwimProgress(poolLengthMeters: 25)
        for value in [Double.nan, .infinity, -1, Double.greatestFiniteMagnitude] {
            pool.update(distanceMeters: value)
        }
        XCTAssertEqual(pool.distanceMeters, 0)
        XCTAssertEqual(pool.lapCount, 0)
        XCTAssertNil(WatchSwimProgress(poolLengthMeters: 0).lapCount)
    }

    func testWaterLockWaitsForRunningForegroundAndOnlyPendingRequest() {
        XCTAssertTrue(WatchSwimSetup.shouldWaterLock(pending: true, running: true, foreground: true, supported: true))
        XCTAssertFalse(WatchSwimSetup.shouldWaterLock(pending: true, running: false, foreground: true, supported: true))
        XCTAssertFalse(WatchSwimSetup.shouldWaterLock(pending: true, running: true, foreground: false, supported: true))
        XCTAssertFalse(WatchSwimSetup.shouldWaterLock(pending: false, running: true, foreground: true, supported: true))
        XCTAssertFalse(WatchSwimSetup.shouldWaterLock(pending: true, running: true, foreground: true, supported: false))
    }
}
