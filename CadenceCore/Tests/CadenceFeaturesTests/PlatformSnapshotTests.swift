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
