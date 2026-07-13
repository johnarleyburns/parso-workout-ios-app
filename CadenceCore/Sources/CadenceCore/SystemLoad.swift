import Foundation

// MARK: - Multi-system fact model (2026-06-25 evidence upgrade, Phase 2)
//
// Coach reasons about the *physiological systems* a session trains, not just
// "strength days" and "moderate-equivalent minutes". This file adds the pure,
// deterministic types + classification needed to describe which systems are stale,
// loaded, or blocked. It deliberately does NOT change Coach's primary
// recommendation behavior — later phases consume these facts.

/// A trainable physiological system Coach balances across the week.
public enum TrainingSystem: String, Sendable, Codable, CaseIterable {
    case maximalStrength
    case hypertrophy
    case strengthEndurance
    case aerobicBase
    case vo2max
    case threshold
    case anaerobicPower
    case flexibility
    case recovery

    public var displayName: String {
        switch self {
        case .maximalStrength: return "Max strength"
        case .hypertrophy: return "Hypertrophy"
        case .strengthEndurance: return "Strength endurance"
        case .aerobicBase: return "Aerobic base"
        case .vo2max: return "VO\u{2082}max"
        case .threshold: return "Threshold"
        case .anaerobicPower: return "Anaerobic power"
        case .flexibility: return "Flexibility"
        case .recovery: return "Recovery"
        }
    }
}

/// The intensity buckets aerobic minutes accrue into. Distinct from
/// `WeeklyBalance.moderate/vigorousMinutes` (which is a health-floor accounting):
/// these map to training systems.
public enum AerobicIntensityBucket: String, Sendable, Codable, CaseIterable {
    case easy
    case moderate
    case threshold
    case vo2
    case anaerobic
}

/// A per-system rolling snapshot: how much exposure (in the system's natural unit —
/// hard sets for strength systems, sessions for aerobic/mobility), how stale it is,
/// and the confidence Coach has in the reading.
public struct SystemLoad: Sendable, Equatable {
    public let system: TrainingSystem
    public let trailing7dExposures: Double
    public let trailing28dExposures: Double
    public let daysSinceLastExposure: Int?
    public let lastHardExposureAt: Date?
    public let trend: TrendDirection?
    public let confidence: FactConfidence

    public init(system: TrainingSystem, trailing7dExposures: Double,
                trailing28dExposures: Double, daysSinceLastExposure: Int?,
                lastHardExposureAt: Date?, trend: TrendDirection?, confidence: FactConfidence) {
        self.system = system
        self.trailing7dExposures = trailing7dExposures
        self.trailing28dExposures = trailing28dExposures
        self.daysSinceLastExposure = daysSinceLastExposure
        self.lastHardExposureAt = lastHardExposureAt
        self.trend = trend
        self.confidence = confidence
    }

    /// A system is "stale" when it has no exposure this week (or never).
    public var isStale: Bool { trailing7dExposures <= 0 }
}

/// The latest self-reported readiness, projected from a `ReadinessEntry`. All scores
/// are 1 (worst) to 5 (best); `nil` when no check-in exists.
public struct ReadinessSnapshot: Sendable, Equatable {
    public let soreness: Int?        // 5 = no soreness
    public let sleepQuality: Int?    // 5 = great
    public let stress: Int?          // 5 = relaxed
    public let motivation: Int?      // energy proxy, 5 = full of energy
    public let painConcern: Bool
    public let capturedAt: Date?
    public var confidence: FactConfidence

    // MARK: Passive fusion (revenue Phase 4, D4). Additive — optional/defaulted so
    // every existing `ReadinessSnapshot(...)` call site stays source-compatible.
    //
    // Self-report ABOVE remains authoritative wherever present (`sawMonitoring2016`:
    // self-reported measures trump objective monitoring). These passive fields are a
    // zero-friction prior that fills the (common) gap where no check-in exists.
    public var passive: PassiveReadinessSignal?
    /// Set when passive signals are strongly suppressed and there is no recent
    /// self-report — the app should *ask* the user for a check-in rather than assume.
    public var promptCheckIn: Bool

    public init(soreness: Int?, sleepQuality: Int?, stress: Int?, motivation: Int?,
                painConcern: Bool, capturedAt: Date?, confidence: FactConfidence,
                passive: PassiveReadinessSignal? = nil,
                promptCheckIn: Bool = false) {
        self.soreness = soreness
        self.sleepQuality = sleepQuality
        self.stress = stress
        self.motivation = motivation
        self.painConcern = painConcern
        self.capturedAt = capturedAt
        self.confidence = confidence
        self.passive = passive
        self.promptCheckIn = promptCheckIn
    }

    /// True when any logged score is poor (≤2) — a conservative "downgrade hard work"
    /// signal. Never a diagnosis.
    public var isPoor: Bool {
        [soreness, sleepQuality, stress, motivation].compactMap { $0 }.contains { $0 <= 2 }
    }

    public static func from(_ entry: ReadinessEntry, now: Date = Date()) -> ReadinessSnapshot {
        // A check-in older than ~36h is treated as low-confidence.
        let ageHours = now.timeIntervalSince(entry.date) / 3600
        return ReadinessSnapshot(
            soreness: entry.muscleSoreness,
            sleepQuality: entry.sleepQuality,
            stress: entry.stressMood,
            motivation: entry.fatigueEnergy,
            painConcern: entry.hasPainOrIllnessConcern,
            capturedAt: entry.date,
            confidence: ageHours <= 36 ? .moderate : .low)
    }
}

/// Whether Coach has a fresh baseline for a system (so it can decide whether to
/// prescribe vs prompt an assessment).
public struct AssessmentCoverage: Sendable, Equatable {
    public let system: TrainingSystem
    public let hasBaseline: Bool
    public let isFresh: Bool
    public let latestDate: Date?
    public let trend: AssessmentTrend?

    public init(system: TrainingSystem, hasBaseline: Bool, isFresh: Bool,
                latestDate: Date?, trend: AssessmentTrend?) {
        self.system = system
        self.hasBaseline = hasBaseline
        self.isFresh = isFresh
        self.latestDate = latestDate
        self.trend = trend
    }
}

/// A flagged acute:chronic-style load spike. Computed, not acted on, in Phase 2.
public struct LoadSpikeFlag: Sendable, Equatable {
    public let system: TrainingSystem?
    public let acute7d: Double
    public let chronicWeeklyAvg: Double
    public let ratio: Double

    public init(system: TrainingSystem?, acute7d: Double, chronicWeeklyAvg: Double, ratio: Double) {
        self.system = system
        self.acute7d = acute7d
        self.chronicWeeklyAvg = chronicWeeklyAvg
        self.ratio = ratio
    }
}

/// Where a cardio HR zone's max-HR came from. Drives the low-confidence caveat on
/// HR-zone prescriptions (Tanaka 2001).
public enum CardioZoneSource: String, Sendable, Codable, Equatable {
    case tested          // user has a tested/measured HRmax
    case ageEstimated    // 208 − 0.7·age (or 220 − age) fallback
    case unknown         // no HR data at all
}

// MARK: - Event → system classification

extension TrainingEvent {

    /// A single (system, exposure, hard) contribution this event makes.
    public struct SystemExposure: Sendable, Equatable {
        public let system: TrainingSystem
        public let exposures: Double
        public let hard: Bool
    }

    /// Classify the systems this event loads. Deterministic; no behavior change to
    /// the existing decision engine. Strength systems are counted in *hard sets*;
    /// aerobic/mobility systems in *sessions*. See plan §B classification rules.
    public var systemExposures: [SystemExposure] {
        switch kind {
        case .strength(let details):
            guard let d = details, completion == .completed else { return [] }
            var out: [SystemExposure] = []
            for ex in d.exercises where ex.hardSetCount > 0 {
                let system: TrainingSystem
                if ex.topSetReps > 0 && ex.topSetReps <= 5 {
                    system = .maximalStrength
                } else if ex.topSetReps <= 15 {
                    system = .hypertrophy
                } else {
                    system = .strengthEndurance
                }
                out.append(SystemExposure(system: system,
                                          exposures: Double(ex.hardSetCount),
                                          hard: ex.isHard))
            }
            return out

        case .aerobic(let d):
            switch d.intensity {
            case .easy:
                // Easy continuous work / recovery walks build base + recovery.
                if d.modality == .walking {
                    return [SystemExposure(system: .recovery, exposures: 1, hard: false),
                            SystemExposure(system: .aerobicBase, exposures: 1, hard: false)]
                }
                return [SystemExposure(system: .aerobicBase, exposures: 1, hard: false)]
            case .moderate:
                return [SystemExposure(system: .aerobicBase, exposures: 1, hard: false)]
            case .vigorous:
                // Sustained continuous hard effort ≈ threshold work.
                return [SystemExposure(system: .threshold, exposures: 1, hard: true)]
            }

        case .intervals(let d):
            // Interval (HIIT) sessions default to VO₂ work; short all-out sprint
            // sessions are recommended explicitly by the coach and not inferred
            // from a generic interval label.
            switch d.intensity {
            case .vigorous:
                return [SystemExposure(system: .vo2max, exposures: 1, hard: true)]
            case .moderate, .easy:
                return [SystemExposure(system: .aerobicBase, exposures: 1, hard: false)]
            }

        case .unknown:
            return []
        }
    }
}

// MARK: - Aggregation (pure)

/// Builds the multi-system rolling facts from completed `TrainingEvent`s. Pure and
/// deterministic against an injected `now`.
public enum SystemLoadComputer {

    public static func loads(rolling7d: [TrainingEvent],
                             rolling28d: [TrainingEvent],
                             now: Date,
                             calendar: Calendar = .current) -> [TrainingSystem: SystemLoad] {
        var sevenDay: [TrainingSystem: Double] = [:]
        var twentyEight: [TrainingSystem: Double] = [:]
        var lastExposure: [TrainingSystem: Date] = [:]
        var lastHard: [TrainingSystem: Date] = [:]

        for e in rolling28d {
            for ex in e.systemExposures {
                twentyEight[ex.system, default: 0] += ex.exposures
                if lastExposure[ex.system] == nil || e.end > lastExposure[ex.system]! {
                    lastExposure[ex.system] = e.end
                }
                if ex.hard, lastHard[ex.system] == nil || e.end > lastHard[ex.system]! {
                    lastHard[ex.system] = e.end
                }
            }
        }
        for e in rolling7d {
            for ex in e.systemExposures {
                sevenDay[ex.system, default: 0] += ex.exposures
            }
        }

        var out: [TrainingSystem: SystemLoad] = [:]
        for system in TrainingSystem.allCases {
            let last = lastExposure[system]
            let daysSince = last.map {
                max(0, calendar.dateComponents([.day],
                                               from: calendar.startOfDay(for: $0),
                                               to: calendar.startOfDay(for: now)).day ?? 0)
            }
            let twentyEightVal = twentyEight[system] ?? 0
            out[system] = SystemLoad(
                system: system,
                trailing7dExposures: sevenDay[system] ?? 0,
                trailing28dExposures: twentyEightVal,
                daysSinceLastExposure: daysSince,
                lastHardExposureAt: lastHard[system],
                trend: nil,
                confidence: twentyEightVal > 0 ? .moderate : .low)
        }
        return out
    }

    /// Aerobic minutes this week split into training-system buckets (distinct from the
    /// health-floor `moderate/vigorousMinutes` accounting in `WeeklyBalance`).
    public static func aerobicMinutesByBucket(rolling7d: [TrainingEvent]) -> [AerobicIntensityBucket: Double] {
        var out: [AerobicIntensityBucket: Double] = [:]
        for e in rolling7d {
            let d: AerobicEventDetails
            let isInterval: Bool
            switch e.kind {
            case .aerobic(let ad): d = ad; isInterval = false
            case .intervals(let ad): d = ad; isInterval = true
            default: continue
            }
            let mins = d.duration / 60
            let bucket: AerobicIntensityBucket
            switch (isInterval, d.intensity) {
            case (true, .vigorous): bucket = .vo2
            case (false, .vigorous): bucket = .threshold
            case (_, .moderate): bucket = .moderate
            case (_, .easy): bucket = .easy
            }
            out[bucket, default: 0] += mins
        }
        return out
    }

    /// Per-system acute:chronic load spikes (acute = trailing 7d, chronic = 28d ÷ 4).
    /// Flagged at ratio > 1.5; computed only — not yet consumed by Coach.
    public static func loadSpikeFlags(_ loads: [TrainingSystem: SystemLoad]) -> [LoadSpikeFlag] {
        var flags: [LoadSpikeFlag] = []
        for system in TrainingSystem.allCases {
            guard let load = loads[system] else { continue }
            let chronicWeekly = load.trailing28dExposures / 4.0
            guard chronicWeekly > 0 else { continue }
            let ratio = load.trailing7dExposures / chronicWeekly
            if ratio > 1.5 {
                flags.append(LoadSpikeFlag(system: system, acute7d: load.trailing7dExposures,
                                           chronicWeeklyAvg: chronicWeekly, ratio: ratio))
            }
        }
        return flags
    }

    /// Where cardio HR zones' max-HR comes from. We always use an age-estimated max,
    /// so any HR-backed session is `.ageEstimated`; with no HR data at all it's
    /// `.unknown`. `.tested` is reserved for a future user-entered HRmax.
    public static func zoneSource(rolling28d: [TrainingEvent]) -> CardioZoneSource {
        var sawHR = false
        for e in rolling28d {
            switch e.kind {
            case .aerobic(let d), .intervals(let d):
                if d.intensityConfidence >= .moderate { sawHR = true }
            default: continue
            }
        }
        return sawHR ? .ageEstimated : .unknown
    }

    private static let strengthEnduranceKinds: Set<AssessmentKind> =
        [.pushupMax, .pullupMax, .bodyweightSquatMax, .plankHold, .hollowHold]
    private static let vo2Kinds: Set<AssessmentKind> =
        [.cooper12min, .run1_5mile, .rockportWalk, .queensCollegeStep, .vo2maxField]

    /// Which systems have a (fresh) baseline, from assessment summaries.
    public static func assessmentCoverage(_ summaries: [AssessmentSummary],
                                          now: Date) -> [TrainingSystem: AssessmentCoverage] {
        func coverage(_ system: TrainingSystem, kinds: (AssessmentKind) -> Bool) -> AssessmentCoverage {
            let relevant = summaries.filter { kinds($0.kind) }
            guard let latest = relevant.max(by: { $0.latestDate < $1.latestDate }) else {
                return AssessmentCoverage(system: system, hasBaseline: false, isFresh: false,
                                          latestDate: nil, trend: nil)
            }
            let fresh = !AssessmentMath.isRetestDue(latest, now: now)
            return AssessmentCoverage(system: system, hasBaseline: true, isFresh: fresh,
                                      latestDate: latest.latestDate, trend: latest.trend)
        }

        var out: [TrainingSystem: AssessmentCoverage] = [:]
        out[.maximalStrength] = coverage(.maximalStrength) { $0 == .e1RM || $0 == .repMax }
        out[.strengthEndurance] = coverage(.strengthEndurance) { strengthEnduranceKinds.contains($0) }
        let vo2 = coverage(.vo2max) { vo2Kinds.contains($0) }
        out[.vo2max] = vo2
        out[.aerobicBase] = AssessmentCoverage(system: .aerobicBase, hasBaseline: vo2.hasBaseline,
                                               isFresh: vo2.isFresh, latestDate: vo2.latestDate,
                                               trend: vo2.trend)
        out[.anaerobicPower] = coverage(.anaerobicPower) { $0 == .wingate }
        return out
    }
}
