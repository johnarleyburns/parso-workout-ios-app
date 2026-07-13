import Foundation

/// One day of passively-collected recovery data, read from HealthKit. Pure value
/// type — the HealthKit read lives in the app layer; this file never imports it.
public struct PassiveReadinessSample: Sendable, Equatable {
    public let date: Date
    public let hrvSDNN: Double?     // ms
    public let restingHR: Double?   // bpm
    public let sleepHours: Double?

    public init(date: Date, hrvSDNN: Double? = nil, restingHR: Double? = nil, sleepHours: Double? = nil) {
        self.date = date
        self.hrvSDNN = hrvSDNN
        self.restingHR = restingHR
        self.sleepHours = sleepHours
    }
}

/// How suppressed the passive recovery signal is versus the user's own baseline.
public enum PassiveReadinessLevel: Sendable, Equatable {
    case insufficientData   // the coach makes NO claim
    case normal
    case suppressed
    case stronglySuppressed
}

/// The fused-ready passive signal. Any level other than `.insufficientData` that
/// carries a claim MUST populate `citationIds` (HARD RULE — every coaching output
/// cites navigable science).
public struct PassiveReadinessSignal: Sendable, Equatable {
    public let level: PassiveReadinessLevel
    public let hrvDeviationPct: Double?     // vs personal baseline (negative = below)
    public let restingHRDeltaBpm: Double?   // vs personal baseline (positive = elevated)
    public let sleepDebtHours: Double?      // vs 14-day mean (positive = debt)
    public let citationIds: [String]

    public init(level: PassiveReadinessLevel,
                hrvDeviationPct: Double? = nil,
                restingHRDeltaBpm: Double? = nil,
                sleepDebtHours: Double? = nil,
                citationIds: [String] = []) {
        self.level = level
        self.hrvDeviationPct = hrvDeviationPct
        self.restingHRDeltaBpm = restingHRDeltaBpm
        self.sleepDebtHours = sleepDebtHours
        self.citationIds = citationIds
    }

    /// The default, no-claim signal a brand-new install produces.
    public static let insufficient = PassiveReadinessSignal(level: .insufficientData)

    /// True when the passive signal is confident enough to carry a coaching claim.
    public var makesClaim: Bool { level != .insufficientData }
}

/// Turns a window of passive HealthKit samples into a conservative,
/// citation-backed recovery signal. Pure, zero-I/O, deterministic against `now`.
///
/// Every threshold here is deliberately conservative and citation-backed. A single
/// day's HRV is noise (Javaloyes, Vesterinen), so we compare a 7-day rolling mean
/// against a 28–60 day baseline and require ≥14 days of HRV before making any claim
/// at all. `.insufficientData` is the DEFAULT, not an edge case — a two-day-old
/// install must produce no confident claim.
public enum PassiveReadinessAnalyzer {

    /// Minimum days of HRV data before the analyzer will make any claim.
    public static let minimumHRVDays = 14

    /// Baseline window: trailing 28–60 days. We use up to 60, require ≥28 available
    /// but fall back to whatever ≥14 exists (still guarded by `minimumHRVDays`).
    static let baselineWindowDays = 60
    static let rollingWindowDays = 7

    // Thresholds (citation-backed — see the changelog / CITATIONS.md):
    static let hrvSuppressedPct = -10.0
    static let hrvStronglySuppressedPct = -20.0
    static let restingHRElevatedBpm = 5.0
    static let sleepDebtHours = 2.0
    static let sleepAbsoluteLowHours = 6.0

    /// Citations backing a passive-readiness claim. Kept in one place so the signal
    /// and the changelog cannot drift.
    public static let claimCitationIds = [
        "javaloyesHRVGuided2019",
        "vesterinenHRVGuided2016",
        "buchheitMonitoring2014",
        "cravenSleep2022",
    ]

    public static func signal(samples: [PassiveReadinessSample], now: Date) -> PassiveReadinessSignal {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)

        // Consider only samples within the baseline window and not in the future.
        let windowStart = cal.date(byAdding: .day, value: -baselineWindowDays, to: today)!
        let inWindow = samples.filter { $0.date >= windowStart && $0.date <= now }

        let hrvSamples = inWindow.compactMap { s in s.hrvSDNN.map { (s.date, $0) } }

        // HARD RULE guard: without ≥14 days of HRV we make NO claim.
        guard hrvSamples.count >= minimumHRVDays else {
            return .insufficient
        }

        // Baseline = mean of all in-window HRV; rolling = mean of the last 7 days.
        let baselineHRV = mean(hrvSamples.map(\.1))
        let rollingStart = cal.date(byAdding: .day, value: -rollingWindowDays, to: today)!
        let rollingHRV = hrvSamples.filter { $0.0 >= rollingStart }.map(\.1)
        guard !rollingHRV.isEmpty, baselineHRV > 0 else { return .insufficient }
        let rollingMeanHRV = mean(rollingHRV)

        let hrvDeviationPct = (rollingMeanHRV - baselineHRV) / baselineHRV * 100.0

        // Resting HR: rolling 7-day mean vs in-window baseline.
        let rhrSamples = inWindow.compactMap { s in s.restingHR.map { (s.date, $0) } }
        var rhrDelta: Double?
        if rhrSamples.count >= minimumHRVDays {
            let baselineRHR = mean(rhrSamples.map(\.1))
            let rollingRHR = rhrSamples.filter { $0.0 >= rollingStart }.map(\.1)
            if !rollingRHR.isEmpty { rhrDelta = mean(rollingRHR) - baselineRHR }
        }

        // Sleep: rolling 7-day mean vs 14-day mean; also flag an absolute short night.
        let sleepSamples = inWindow.compactMap { s in s.sleepHours.map { (s.date, $0) } }
        var sleepDebt: Double?
        if !sleepSamples.isEmpty {
            let twoWeekStart = cal.date(byAdding: .day, value: -14, to: today)!
            let twoWeek = sleepSamples.filter { $0.0 >= twoWeekStart }.map(\.1)
            let rollingSleep = sleepSamples.filter { $0.0 >= rollingStart }.map(\.1)
            if !twoWeek.isEmpty, !rollingSleep.isEmpty {
                sleepDebt = mean(twoWeek) - mean(rollingSleep)
            }
        }
        let recentSleepLow = sleepSamples
            .filter { $0.0 >= rollingStart }
            .map(\.1)
            .min()

        // Score each contributing signal.
        var suppressionPoints = 0
        var strongPoints = 0

        if hrvDeviationPct <= hrvStronglySuppressedPct {
            strongPoints += 1
        } else if hrvDeviationPct <= hrvSuppressedPct {
            suppressionPoints += 1
        }

        if let rhrDelta, rhrDelta >= restingHRElevatedBpm {
            suppressionPoints += 1
        }

        if let sleepDebt, sleepDebt >= sleepDebtHours {
            suppressionPoints += 1
        } else if let recentSleepLow, recentSleepLow < sleepAbsoluteLowHours {
            suppressionPoints += 1
        }

        let level: PassiveReadinessLevel
        if strongPoints > 0 && suppressionPoints >= 1 {
            // Strongly-suppressed HRV corroborated by RHR/sleep.
            level = .stronglySuppressed
        } else if strongPoints > 0 {
            // Strong HRV drop alone is still a strong signal.
            level = .stronglySuppressed
        } else if suppressionPoints >= 1 {
            level = .suppressed
        } else {
            level = .normal
        }

        return PassiveReadinessSignal(
            level: level,
            hrvDeviationPct: hrvDeviationPct,
            restingHRDeltaBpm: rhrDelta,
            sleepDebtHours: sleepDebt,
            citationIds: level == .normal ? [] : claimCitationIds)
    }

    private static func mean(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        return xs.reduce(0, +) / Double(xs.count)
    }
}
