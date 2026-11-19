#if canImport(os)
import Foundation
import Testing
@testable import CadenceCore

struct ActivityDoseAerobicReuseTests {
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

    @Test func precomputedAerobicMatchesStandalone() {
        let (c, s) = fixture()
        let aerobic = WeeklyCardioAggregator.summarize(c, since: since, profile: profile, sessions: s)
        #expect(
            WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since,
                                                   profile: profile, aerobic: aerobic) ==
            WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since, profile: profile))
    }

    @Test func suppliedAerobicIsPreservedAndActualMinutesFromDurations() {
        let (c, s) = fixture()
        let custom = WeeklyCardioSummary.empty
        let r = WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since,
                                                       profile: profile, aerobic: custom)
        #expect(r.aerobic == custom)
        #expect(abs(r.actualActivityMinutes - (30 + 45 + 20 + 50 + 40)) <= 0.001)
    }

    @Test func ineligibleRecordsDoNotContribute() {
        let deleted = cardio(.run, offset: 100, minutes: 10); deleted.deletedAt = since
        let old = cardio(.run, offset: -5_000, minutes: 10)
        let negative = cardio(.run, offset: 200, minutes: -10)
        let deletedSession = strength(offset: 300, minutes: 30); deletedSession.deletedAt = since
        let oldSession = strength(offset: -300, minutes: 30)
        let r = WeeklyActivityDoseAggregator.summarize(
            cardio: [deleted, old, negative], sessions: [deletedSession, oldSession],
            since: since, aerobic: .empty)
        #expect(abs(r.actualActivityMinutes - 0) <= 0.0001)
        #expect(r.strengthDays == 0)
    }

    @Test func precomputedPathMakesNoAdditionalAggregatorCalls() {
        let (c, s) = fixture()
        let probe = WeeklyCardioAggregator.InvocationProbe()
        WeeklyCardioAggregator.$invocationProbe.withValue(probe) {
            let aerobic = WeeklyCardioAggregator.summarize(c, since: since, profile: profile, sessions: s)
            #expect(probe.count == 1)
            _ = WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since,
                                                       profile: profile, aerobic: aerobic)
            #expect(probe.count == 1, "supplied aerobic must not trigger another HR pass")
            _ = WeeklyActivityDoseAggregator.summarize(cardio: c, sessions: s, since: since, profile: profile)
            #expect(probe.count == 2, "standalone path computes aerobic exactly once")
        }
    }
}
#endif
