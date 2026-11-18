import Foundation
import Testing
@testable import CadenceCore

struct ManualCardioOverrideTests {
    private let profile = CardioIntensityProfile(restingHR: 60, maximumHR: 200, maximumHRSource: .fieldTest)
    private let since = Date(timeIntervalSince1970: 0)
    private var samples: [HRSamplePoint] { (0..<60).map { HRSamplePoint(t: Double($0 * 60), bpm: 185) } }

    private func session() -> WorkoutSession {
        let s = WorkoutSession(title: "Run", date: Date(timeIntervalSince1970: 1000))
        s.endedAt = s.date.addingTimeInterval(3600)
        s.hrSamplePoints = samples
        return s
    }

    @Test func manualMinutesWinOverHRSamples() {
        let s = session()
        s.setManualCardioMinutes(moderate: 17, vigorous: 11)
        #expect(s.hasManualCardioMinutesOverride)
        let r = WeeklyCardioAggregator.summarize([], since: since, profile: profile, sessions: [s])
        #expect(abs(r.moderateMinutes - 17) <= 0.001)
        #expect(abs(r.vigorousMinutes - 11) <= 0.001)
        #expect(abs(r.moderateEquivalentMinutes - 39) <= 0.001)
        #expect(r.zoneMinutes.isEmpty)
    }

    @Test func zeroZeroRemainsOverride() {
        let s = session()
        s.setManualCardioMinutes(moderate: 0, vigorous: 0)
        #expect(s.hasManualCardioMinutesOverride)
        let r = WeeklyCardioAggregator.summarize([], since: since, profile: profile, sessions: [s])
        #expect(abs(r.moderateEquivalentMinutes - 0) <= 0.001)
    }

    @Test func nonManualSessionRecomputesFromHR() {
        let s = session()
        let r = WeeklyCardioAggregator.summarize([], since: since, profile: profile, sessions: [s])
        #expect(r.vigorousMinutes > 0)
    }

    @Test func legacyRecognition() {
        let s = session()
        s.intensitySummary = CardioMinuteSummary.manual(moderate: 10, vigorous: 0, sessionDuration: 3600)
        #expect(!s.hasManualCardioMinutesOverride)
        #expect(s.isManualCardioMinutesOverride)
        let r = WeeklyCardioAggregator.summarize([], since: since, profile: profile, sessions: [s])
        #expect(abs(r.moderateMinutes - 10) <= 0.001)

        let zero = session()
        zero.intensitySummary = CardioMinuteSummary.manual(moderate: 0, vigorous: 0, sessionDuration: 3600)
        #expect(!zero.isManualCardioMinutesOverride)

        let withZones = session()
        withZones.intensitySummary = CardioMinuteAccumulator.summarize(duration: 3600, samples: samples, profile: profile)
        #expect(!withZones.isManualCardioMinutesOverride)
    }

    @Test func aggregationDoesNotMutateAndNewHRClearsOverride() {
        let s = session()
        s.setManualCardioMinutes(moderate: 5, vigorous: 5)
        let data = s.intensitySummaryData, stamp = s.updatedAt
        _ = WeeklyCardioAggregator.summarize([], since: since, profile: profile, sessions: [s])
        #expect(s.intensitySummaryData == data)
        #expect(s.updatedAt == stamp)
        #expect(s.hasManualCardioMinutesOverride)
        s.recordHeartRate(samples, profile: profile)
        #expect(!s.hasManualCardioMinutesOverride)
    }
}
