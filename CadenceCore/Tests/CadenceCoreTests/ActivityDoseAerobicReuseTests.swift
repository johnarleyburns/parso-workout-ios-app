import XCTest
@testable import CadenceCore

final class ActivityDoseAerobicReuseTests: XCTestCase {
    private let since = Date(timeIntervalSince1970: 1_000_000)
    private let profile = CardioIntensityProfile(maximumHR: 200, maximumHRSource: .userEntered)

    private func cardio(_ type: CardioType, offset: TimeInterval, minutes: Double,
                        bpm: Double? = nil) -> CardioWorkout {
        let start = since.addingTimeInterval(offset)
        let w = CardioWorkout(type: type, start: start, end: start.addingTimeInterval(minutes * 60))
        if let bpm {
            w.hrSamples = stride(from: 0.0, to: minutes * 60, by: 5).map {
                HRSample(t: $0, bpm: bpm, cardio: w)
            }
        }
        return w
    }

    private func strength(offset: TimeInterval, minutes: Double) -> WorkoutSession {
        let start = since.addingTimeInterval(offset)
        return WorkoutSession(title: "S", date: start, endedAt: start.addingTimeInterval(minutes * 60))
    }

    private func fixture() -> (cardio: [CardioWorkout], sessions: [WorkoutSession]) {
        let stored = cardio(.walk, offset: 4_000, minutes: 20)
        stored.intensitySummary = CardioMinuteSummary(
            actualDuration: 1_200, classifiedDuration: 1_200, unclassifiedDuration: 0,
            belowModerateDuration: 600, moderateDuration: 600, vigorousDuration: 0,
            zoneDurations: [.z2: 600, .z3: 600], method: .percentMaximumHeartRate,
            confidence: .estimated)
        return ([cardio(.run, offset: 1_000, minutes: 30, bpm: 170),
                 cardio(.cycle, offset: 90_000, minutes: 45, bpm: 140),
                 stored],
                [strength(offset: 5_000, minutes: 50), strength(offset: 100_000, minutes: 40)])
    }

    func testPrecomputedAerobicMatchesStandalone() {
        let (c, s) = fixture()
        let aerobic = WeeklyCardioAggregator.summarize(c, since: since, profile: profile, sessions: s)
        XCTAssertEqual(
            WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since,
                                                   profile: profile, aerobic: aerobic),
            WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since, profile: profile))
    }

    func testSuppliedAerobicIsPreservedAndActualMinutesFromDurations() {
        let (c, s) = fixture()
        let custom = WeeklyCardioSummary.empty
        let r = WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since,
                                                       profile: profile, aerobic: custom)
        XCTAssertEqual(r.aerobic, custom)
        XCTAssertEqual(r.actualActivityMinutes, 30 + 45 + 20 + 50 + 40, accuracy: 0.001)
    }

    func testIneligibleRecordsDoNotContribute() {
        let deleted = cardio(.run, offset: 100, minutes: 10); deleted.deletedAt = since
        let old = cardio(.run, offset: -5_000, minutes: 10)
        let negative = cardio(.run, offset: 200, minutes: -10)
        let deletedSession = strength(offset: 300, minutes: 30); deletedSession.deletedAt = since
        let oldSession = strength(offset: -300, minutes: 30)
        let r = WeeklyActivityDoseAggregator.summarize(
            cardio: [deleted, old, negative], sessions: [deletedSession, oldSession],
            since: since, aerobic: .empty)
        XCTAssertEqual(r.actualActivityMinutes, 0, accuracy: 0.0001)
        XCTAssertEqual(r.strengthDays, 0)
    }

    func testPrecomputedPathMakesNoAdditionalAggregatorCalls() {
        let (c, s) = fixture()
        let probe = WeeklyCardioAggregator.InvocationProbe()
        WeeklyCardioAggregator.$invocationProbe.withValue(probe) {
            let aerobic = WeeklyCardioAggregator.summarize(c, since: since, profile: profile, sessions: s)
            XCTAssertEqual(probe.count, 1)
            _ = WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since,
                                                       profile: profile, aerobic: aerobic)
            XCTAssertEqual(probe.count, 1, "supplied aerobic must not trigger another HR pass")
            _ = WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since, profile: profile)
            XCTAssertEqual(probe.count, 2, "standalone path computes aerobic exactly once")
        }
    }
}
