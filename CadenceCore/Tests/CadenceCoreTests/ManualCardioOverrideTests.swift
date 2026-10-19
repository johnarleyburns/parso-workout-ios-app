import XCTest
@testable import CadenceCore

final class ManualCardioOverrideTests: XCTestCase {
    private let profile = CardioIntensityProfile(restingHR: 60, maximumHR: 200, maximumHRSource: .fieldTest)
    private let since = Date(timeIntervalSince1970: 0)
    private var samples: [HRSamplePoint] { (0..<60).map { HRSamplePoint(t: Double($0 * 60), bpm: 185) } }

    private func session() -> WorkoutSession {
        let s = WorkoutSession(title: "Run", date: Date(timeIntervalSince1970: 1000))
        s.endedAt = s.date.addingTimeInterval(3600)
        s.hrSamplePoints = samples
        return s
    }

    func testManualMinutesWinOverHRSamples() {
        let s = session()
        s.setManualCardioMinutes(moderate: 17, vigorous: 11)
        XCTAssertTrue(s.hasManualCardioMinutesOverride)
        let r = WeeklyCardioAggregator.summarize([], since: since, profile: profile, sessions: [s])
        XCTAssertEqual(r.moderateMinutes, 17, accuracy: 0.001)
        XCTAssertEqual(r.vigorousMinutes, 11, accuracy: 0.001)
        XCTAssertEqual(r.moderateEquivalentMinutes, 39, accuracy: 0.001)
        XCTAssertTrue(r.zoneMinutes.isEmpty)
    }

    func testZeroZeroRemainsOverride() {
        let s = session()
        s.setManualCardioMinutes(moderate: 0, vigorous: 0)
        XCTAssertTrue(s.hasManualCardioMinutesOverride)
        let r = WeeklyCardioAggregator.summarize([], since: since, profile: profile, sessions: [s])
        XCTAssertEqual(r.moderateEquivalentMinutes, 0, accuracy: 0.001)
    }

    func testNonManualSessionRecomputesFromHR() {
        let s = session()
        let r = WeeklyCardioAggregator.summarize([], since: since, profile: profile, sessions: [s])
        XCTAssertGreaterThan(r.vigorousMinutes, 0)
    }

    func testLegacyRecognition() {
        let s = session()
        s.intensitySummary = CardioMinuteSummary.manual(moderate: 10, vigorous: 0, sessionDuration: 3600)
        XCTAssertFalse(s.hasManualCardioMinutesOverride)
        XCTAssertTrue(s.isManualCardioMinutesOverride)
        let r = WeeklyCardioAggregator.summarize([], since: since, profile: profile, sessions: [s])
        XCTAssertEqual(r.moderateMinutes, 10, accuracy: 0.001)

        let zero = session()
        zero.intensitySummary = CardioMinuteSummary.manual(moderate: 0, vigorous: 0, sessionDuration: 3600)
        XCTAssertFalse(zero.isManualCardioMinutesOverride)

        let withZones = session()
        withZones.intensitySummary = CardioMinuteAccumulator.summarize(duration: 3600, samples: samples, profile: profile)
        XCTAssertFalse(withZones.isManualCardioMinutesOverride)
    }

    func testAggregationDoesNotMutateAndNewHRClearsOverride() {
        let s = session()
        s.setManualCardioMinutes(moderate: 5, vigorous: 5)
        let data = s.intensitySummaryData, stamp = s.updatedAt
        _ = WeeklyCardioAggregator.summarize([], since: since, profile: profile, sessions: [s])
        XCTAssertEqual(s.intensitySummaryData, data)
        XCTAssertEqual(s.updatedAt, stamp)
        XCTAssertTrue(s.hasManualCardioMinutesOverride)
        s.recordHeartRate(samples, profile: profile)
        XCTAssertFalse(s.hasManualCardioMinutesOverride)
    }
}
