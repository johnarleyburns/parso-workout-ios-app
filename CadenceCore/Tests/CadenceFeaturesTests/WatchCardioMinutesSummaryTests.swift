import XCTest
import CadenceCore
@testable import CadenceFeatures

final class WatchCardioMinutesSummaryTests: XCTestCase {
    private let hrrProfile = CardioIntensityProfile(restingHR: 63, maximumHR: 173, maximumHRSource: .userEntered)
    private let maxOnlyProfile = CardioIntensityProfile(restingHR: nil, maximumHR: 173, maximumHRSource: .userEntered)

    private func dense(_ bpm: Double, from: Double, count: Int) -> [HRSamplePoint] {
        (0..<count).map { HRSamplePoint(t: from + Double($0) * 60, bpm: bpm) }
    }

    private func assertMatchesAccumulator(_ samples: [HRSamplePoint], duration: TimeInterval,
                                          profile: CardioIntensityProfile,
                                          file: StaticString = #filePath, line: UInt = #line) {
        let expected = CardioMinuteAccumulator.summarize(duration: duration, samples: samples, profile: profile)
        let got = WatchCardioMinutesSummary.make(hrSamples: samples, sessionDuration: duration, profile: profile)
        XCTAssertEqual(got?.belowModerateMinutes ?? -1, expected.belowModerateDuration / 60, file: file, line: line)
        XCTAssertEqual(got?.moderateMinutes ?? -1, expected.moderateDuration / 60, file: file, line: line)
        XCTAssertEqual(got?.vigorousMinutes ?? -1, expected.vigorousDuration / 60, file: file, line: line)
        XCTAssertEqual(got?.totalMinutes ?? -1, expected.classifiedDuration / 60, file: file, line: line)
    }

    func testHRRProfileClassifiesModerateAndVigorousLikePhone() {
        let samples = dense(111, from: 0, count: 5) + dense(130, from: 300, count: 5)
        let summary = WatchCardioMinutesSummary.make(hrSamples: samples, sessionDuration: 600, profile: hrrProfile)
        XCTAssertEqual(summary?.moderateMinutes ?? -1, 5, accuracy: 0.0001)
        XCTAssertEqual(summary?.vigorousMinutes ?? -1, 5, accuracy: 0.0001)
        XCTAssertEqual(summary?.belowModerateMinutes ?? -1, 0, accuracy: 0.0001)
        assertMatchesAccumulator(samples, duration: 600, profile: hrrProfile)
    }

    func testPercentMaxFallbackWithoutRestingHRMatchesAccumulator() {
        let samples = dense(100, from: 0, count: 4) + dense(125, from: 240, count: 4) + dense(160, from: 480, count: 4)
        assertMatchesAccumulator(samples, duration: 720, profile: maxOnlyProfile)
    }

    func testLongGapCarriesForwardTheLastKnownHeartRate() {
        let samples = [HRSamplePoint(t: 0, bpm: 130), HRSamplePoint(t: 600, bpm: 130)]
        let summary = WatchCardioMinutesSummary.make(hrSamples: samples, sessionDuration: 660, profile: hrrProfile)
        XCTAssertEqual(summary?.vigorousMinutes ?? -1, 11, accuracy: 0.0001)
        XCTAssertEqual(summary?.totalMinutes ?? -1, 11, accuracy: 0.0001)
        assertMatchesAccumulator(samples, duration: 660, profile: hrrProfile)
    }

    func testNilWithoutEnoughHeartRate() {
        XCTAssertNil(WatchCardioMinutesSummary.make(hrSamples: [], sessionDuration: 0, profile: hrrProfile))
        XCTAssertNil(WatchCardioMinutesSummary.make(hrSamples: [HRSamplePoint(t: 0, bpm: 120)],
                                                    sessionDuration: 60, profile: hrrProfile))
    }

    func testSourceDoesNotReferenceLegacyZoneMath() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CadenceFeatures/WatchCardioMinutesSummary.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains("CardioZoneAggregator"))
        XCTAssertFalse(source.contains("CardioMath"))
        XCTAssertTrue(source.contains("CardioMinuteAccumulator.summarize"))
    }
}
