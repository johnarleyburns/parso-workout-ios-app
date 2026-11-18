import Testing
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct WatchSwimmingTests {
    @Test func mutuallyExclusiveSwimConfigurations() {
        for length in [25.0, 50.0] {
            let pool = WatchSwimSetup.configuration(mode: .lapPool, poolLength: length)
            #expect(pool.poolLengthMeters == length)
            #expect(!pool.usesGPS)
            let open = WatchSwimSetup.configuration(mode: .openWater, poolLength: length)
            #expect(open.usesGPS)
            #expect(open.poolLengthMeters == nil)
        }
        #expect(WatchSwimSetup.configuration(mode: .lapPool, poolLength: .nan).poolLengthMeters == 25)
    }

    @Test func nativeDistanceCountsPoolLengthsWithoutDuplicateEvents() {
        var progress = WatchSwimProgress(poolLengthMeters: 25)
        for (distance, laps) in [(0.0, 0), (24.9, 0), (25, 1), (25, 1), (50, 2), (100, 4)] {
            progress.update(distanceMeters: distance)
            #expect(progress.lapCount == laps)
        }
        progress.update(distanceMeters: 50) // late callback cannot undo completed lengths
        #expect(progress.distanceMeters == 100)
        #expect(progress.lapCount == 4)
    }

    @Test func fiftyMeterPoolAndOpenWater() {
        var pool = WatchSwimProgress(poolLengthMeters: 50)
        pool.update(distanceMeters: 200)
        #expect(pool.lapCount == 4)
        var open = WatchSwimProgress(poolLengthMeters: nil)
        open.update(distanceMeters: 200)
        #expect(open.distanceMeters == 200)
        #expect(open.lapCount == nil)
    }

    @Test func invalidMeasurementsDoNotInventLapsOrCrash() {
        var pool = WatchSwimProgress(poolLengthMeters: 25)
        for value in [Double.nan, .infinity, -1, Double.greatestFiniteMagnitude] {
            pool.update(distanceMeters: value)
        }
        #expect(pool.distanceMeters == 0)
        #expect(pool.lapCount == 0)
        #expect(WatchSwimProgress(poolLengthMeters: 0).lapCount == nil)
    }

    @Test func waterLockWaitsForRunningForegroundAndOnlyPendingRequest() {
        #expect(WatchSwimSetup.shouldWaterLock(pending: true, running: true, foreground: true, supported: true))
        #expect(!WatchSwimSetup.shouldWaterLock(pending: true, running: false, foreground: true, supported: true))
        #expect(!WatchSwimSetup.shouldWaterLock(pending: true, running: true, foreground: false, supported: true))
        #expect(!WatchSwimSetup.shouldWaterLock(pending: false, running: true, foreground: true, supported: true))
        #expect(!WatchSwimSetup.shouldWaterLock(pending: true, running: true, foreground: true, supported: false))
    }
}
