import Foundation
import Testing
@testable import CadenceCore

/// Passive readiness signal from HealthKit (revenue Phase 4, D4). Every threshold
/// is conservative and citation-backed; `.insufficientData` is the DEFAULT, so the
/// tests lean hard on the "make no claim" cases that would otherwise ship a false
/// positive to a brand-new user.
struct PassiveReadinessAnalyzerTests {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let cal = Calendar.current

    private func day(_ ago: Int) -> Date {
        cal.date(byAdding: .day, value: -ago, to: cal.startOfDay(for: now))!
    }

    /// Build `count` days of samples ending yesterday, with a constant baseline and
    /// an optional override for the most-recent `recentDays`.
    private func samples(days count: Int,
                         baselineHRV: Double,
                         recentHRV: Double? = nil,
                         recentDays: Int = 7,
                         baselineRHR: Double? = nil,
                         recentRHR: Double? = nil,
                         sleep: Double? = nil,
                         recentSleep: Double? = nil) -> [PassiveReadinessSample] {
        (1...count).map { ago in
            let isRecent = ago <= recentDays
            return PassiveReadinessSample(
                date: day(ago),
                hrvSDNN: isRecent ? (recentHRV ?? baselineHRV) : baselineHRV,
                restingHR: baselineRHR.map { isRecent ? (recentRHR ?? $0) : $0 },
                sleepHours: sleep.map { isRecent ? (recentSleep ?? $0) : $0 })
        }
    }

    // MARK: insufficient data — the default, tested first

    @Test func freshInstallWithNoDataMakesNoClaim() {
        let signal = PassiveReadinessAnalyzer.signal(samples: [], now: now)
        #expect(signal.level == .insufficientData)
        #expect(!signal.makesClaim)
        #expect(signal.citationIds.isEmpty)
    }

    @Test func fewerThan14DaysOfHRVMakesNoClaim() {
        let signal = PassiveReadinessAnalyzer.signal(
            samples: samples(days: 13, baselineHRV: 60, recentHRV: 30), now: now)
        #expect(signal.level == .insufficientData,
                       "13 days of HRV must not produce a confident claim")
    }

    @Test func exactly14DaysCrossesTheThreshold() {
        let signal = PassiveReadinessAnalyzer.signal(
            samples: samples(days: 14, baselineHRV: 60), now: now)
        #expect(signal.level != .insufficientData)
    }

    // MARK: HRV thresholds

    @Test func flatBaselineProducesNormalNoFalsePositive() {
        let signal = PassiveReadinessAnalyzer.signal(
            samples: samples(days: 40, baselineHRV: 55), now: now)
        #expect(signal.level == .normal)
        #expect(signal.citationIds.isEmpty, "normal makes no claim → no citations")
    }

    @Test func hRVDropBetween10And20IsSuppressed() {
        // 40-day baseline ~ mostly 60; last 7 days at 51 → rolling mean noticeably
        // below baseline (>10% but <20%).
        let signal = PassiveReadinessAnalyzer.signal(
            samples: samples(days: 40, baselineHRV: 60, recentHRV: 50), now: now)
        #expect(signal.level == .suppressed)
        #expect(signal.citationIds == PassiveReadinessAnalyzer.claimCitationIds)
    }

    @Test func hRVDropOver20IsStronglySuppressed() {
        let signal = PassiveReadinessAnalyzer.signal(
            samples: samples(days: 40, baselineHRV: 60, recentHRV: 35), now: now)
        #expect(signal.level == .stronglySuppressed)
        #expect(!signal.citationIds.isEmpty)
    }

    @Test func hRVDeviationIsNegativeWhenSuppressed() {
        let signal = PassiveReadinessAnalyzer.signal(
            samples: samples(days: 40, baselineHRV: 60, recentHRV: 45), now: now)
        #expect(signal.hrvDeviationPct != nil)
        #expect((signal.hrvDeviationPct ?? 0) < 0)
    }

    // MARK: resting HR + sleep contributions

    @Test func elevatedRestingHRContributes() {
        // HRV flat (normal), but resting HR up over baseline → suppressed. (The
        // baseline includes the recent days, so the measured delta is diluted below
        // the raw 7 bpm bump; what matters is that it clears the +5 bpm threshold.)
        let signal = PassiveReadinessAnalyzer.signal(
            samples: samples(days: 40, baselineHRV: 60,
                             baselineRHR: 52, recentRHR: 59), now: now)
        #expect(signal.level == .suppressed)
        #expect((signal.restingHRDeltaBpm ?? 0) >= 5.0)
    }

    @Test func sleepDebtContributes() {
        // HRV flat; sleep drops from 8h to 5.5h over the last week → debt ≥ 2h.
        let signal = PassiveReadinessAnalyzer.signal(
            samples: samples(days: 40, baselineHRV: 60, sleep: 8.0, recentSleep: 5.5), now: now)
        #expect(signal.level == .suppressed)
    }

    @Test func absoluteShortNightContributesEvenWithoutDebt() {
        // Consistent 5.5h every night → no debt vs its own mean, but < 6h absolute.
        let signal = PassiveReadinessAnalyzer.signal(
            samples: samples(days: 40, baselineHRV: 60, sleep: 5.5, recentSleep: 5.5), now: now)
        #expect(signal.level == .suppressed)
    }

    // MARK: robustness

    @Test func onlyHRVAvailableStillWorks() {
        let signal = PassiveReadinessAnalyzer.signal(
            samples: samples(days: 30, baselineHRV: 65), now: now)
        #expect(signal.level == .normal)
        #expect(signal.restingHRDeltaBpm == nil)
        #expect(signal.sleepDebtHours == nil)
    }

    @Test func sleepOnlyWithoutEnoughHRVMakesNoClaim() {
        // Sleep present but < 14 days of HRV → still insufficient (HRV gate governs).
        let sleepOnly = (1...30).map {
            PassiveReadinessSample(date: day($0), hrvSDNN: nil, restingHR: nil, sleepHours: 5.0)
        }
        #expect(PassiveReadinessAnalyzer.signal(samples: sleepOnly, now: now).level
                       == .insufficientData)
    }

    @Test func singleAnomalousDayDoesNotFlipTheLevel() {
        // 40 days at 60, with ONE anomalous day of 20 outside the rolling window.
        var s = samples(days: 40, baselineHRV: 60)
        s[20] = PassiveReadinessSample(date: day(21), hrvSDNN: 20, restingHR: nil, sleepHours: nil)
        let signal = PassiveReadinessAnalyzer.signal(samples: s, now: now)
        #expect(signal.level == .normal,
                       "one bad day 21 days ago must not suppress a rolling-mean signal")
    }

    @Test func futureSamplesAreIgnored() {
        var s = samples(days: 20, baselineHRV: 60)
        s.append(PassiveReadinessSample(date: now.addingTimeInterval(3 * 86400),
                                        hrvSDNN: 10, restingHR: nil, sleepHours: nil))
        let signal = PassiveReadinessAnalyzer.signal(samples: s, now: now)
        #expect(signal.level == .normal)
    }
}
