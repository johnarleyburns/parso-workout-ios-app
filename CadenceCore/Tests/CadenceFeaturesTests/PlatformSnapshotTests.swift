import Foundation
import XCTest
@testable import CadenceFeatures
import CadenceCore

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

    func testQuickTalkRequestIsConsumedOnce() {
        let suite = "cadence.platform.quick-talk.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(CadencePlatformRequestStore.consumeQuickTalk(defaults: defaults))
        CadencePlatformRequestStore.requestQuickTalk(defaults: defaults)
        XCTAssertTrue(CadencePlatformRequestStore.consumeQuickTalk(defaults: defaults))
        XCTAssertFalse(CadencePlatformRequestStore.consumeQuickTalk(defaults: defaults))
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

    func testReadinessPresenterKeepsSafetyCopySeparate() {
        let concern = ReadinessEntry(muscleSoreness: 1, fatigueEnergy: 2,
                                     sleepQuality: 2, stressMood: 1,
                                     hasPainOrIllnessConcern: true)
        XCTAssertEqual(ReadinessCheckInPresenter.summary(for: concern), "Pain or illness noted")
        XCTAssertTrue(ReadinessCheckInPresenter.detail(for: concern).contains("/5"))
        XCTAssertTrue(ReadinessCheckInPresenter.validate(muscleSoreness: 1,
                                                         fatigueEnergy: 5,
                                                         sleepQuality: 3,
                                                         stressMood: 4))
        XCTAssertFalse(ReadinessCheckInPresenter.validate(muscleSoreness: 0,
                                                          fatigueEnergy: 5,
                                                          sleepQuality: 3,
                                                          stressMood: 4))
    }
}
