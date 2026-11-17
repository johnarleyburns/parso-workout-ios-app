import Foundation
import XCTest
@testable import CadenceFeatures

final class PlatformSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsThroughSharedStore() {
        let suite = "cadence.platform.snapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let snapshot = CadenceTodaySnapshot(
            dayKey: "2026-09-11", planTitle: "Coach plan",
            sessionTitles: ["Upper strength", "Easy walk"],
            readinessLabel: "Recovery looks good",
            updatedAt: Date(timeIntervalSince1970: 123))
        CadencePlatformSnapshotStore.save(snapshot, defaults: defaults)

        XCTAssertEqual(CadencePlatformSnapshotStore.load(defaults: defaults), snapshot)
    }

    func testWatchWidgetStateRoundTripsAndClears() {
        let suite = "cadence.platform.watch-widget.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let state = CadenceWatchWidgetState(
            workoutTitle: "Upper strength",
            restEndsAt: Date(timeIntervalSince1970: 456))
        CadenceWatchWidgetStore.save(state, defaults: defaults)

        XCTAssertEqual(CadenceWatchWidgetStore.load(defaults: defaults), state)
        CadenceWatchWidgetStore.clear(defaults: defaults)
        XCTAssertNil(CadenceWatchWidgetStore.load(defaults: defaults))
    }

    func testComplicationStateIsActiveWhileWorkoutRunsAndIdleOtherwise() {
        let suite = "cadence.platform.complication.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date(timeIntervalSince1970: 100_000)

        XCTAssertEqual(CadenceWatchComplicationState.current(defaults: defaults, now: now), .idle)

        let start = now.addingTimeInterval(-600)
        CadenceWatchComplicationState.setActive(
            CadenceWatchActiveWorkout(workoutType: "cardio", startedAt: start), defaults: defaults)
        XCTAssertEqual(CadenceWatchComplicationState.current(defaults: defaults, now: now),
                       .active(workoutType: "cardio", startedAt: start))

        // A stale marker (crash before clear) is ignored.
        XCTAssertEqual(CadenceWatchComplicationState.current(
            defaults: defaults, now: now.addingTimeInterval(CadenceWatchComplicationState.maxAge)), .idle)

        CadenceWatchComplicationState.setActive(nil, defaults: defaults)
        XCTAssertEqual(CadenceWatchComplicationState.current(defaults: defaults, now: now), .idle)
    }


    func testLiveActivityActionIsConsumedOnce() {
        let defaults = UserDefaults(suiteName: "PlatformSnapshotTests.liveActivity.\(UUID().uuidString)")!
        CadencePlatformRequestStore.requestLiveActivity(.logPlannedSet, token: "owner-2", defaults: defaults)
        XCTAssertEqual(CadencePlatformRequestStore.consumeLiveActivityRequest(defaults: defaults),
                       .init(action: .logPlannedSet, token: "owner-2"))
        XCTAssertNil(CadencePlatformRequestStore.consumeLiveActivity(defaults: defaults))
    }

    func testLatestLiveActivityActionReplacesStaleAction() {
        let defaults = UserDefaults(suiteName: "PlatformSnapshotTests.liveActivity.replace.\(UUID().uuidString)")!
        CadencePlatformRequestStore.requestLiveActivity(.addRest, defaults: defaults)
        CadencePlatformRequestStore.requestLiveActivity(.skipRest, defaults: defaults)
        XCTAssertEqual(CadencePlatformRequestStore.consumeLiveActivityRequest(defaults: defaults)?.action, .skipRest)
    }

    func testLegacyLiveActivityStringIsDiscarded() {
        let defaults = UserDefaults(suiteName: "PlatformSnapshotTests.liveActivity.legacy.\(UUID().uuidString)")!
        defaults.set(CadencePlatformRequestStore.LiveActivityAction.addRest.rawValue,
                     forKey: "cadence.platform.liveActivity.action")
        XCTAssertNil(CadencePlatformRequestStore.consumeLiveActivityRequest(defaults: defaults))
    }

    func testLegacySnapshotAndDeepLinkWireValuesStayCompatible() throws {
        let legacy = Data(#"{"dayKey":"2026-09-11","planTitle":"Upper","sessionTitles":["Strength"],"updatedAt":0}"#.utf8)
        let snapshot = try JSONDecoder().decode(CadenceTodaySnapshot.self, from: legacy)
        XCTAssertEqual(snapshot.weeklyMuscles, [])
        XCTAssertNil(snapshot.setsCompleted)
        XCTAssertEqual(snapshot.updatedAt, Date(timeIntervalSinceReferenceDate: 0))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as! [String: Any]
        XCTAssertEqual(encoded["planTitle"] as? String, "Upper")
        XCTAssertEqual(Set(ThisWeekDestination.allCases.map(\.rawValue)), ["muscleCoverage", "strength", "cardio"])
        XCTAssertEqual(Format.duration(3661), "1:01:01")
        XCTAssertEqual(Format.distance(1500), "1.50 km")
    }

}
