import Foundation

/// Versioned provenance for cardio intensity and guideline calculations.
public enum CardioAlgorithmVersion: String, Codable, Sendable, Equatable {
    case legacy
    case hrrGuidelineV1
}

public enum HRMaximumSource: String, Codable, Sendable, Equatable, Hashable {
    case laboratoryMeasured
    case fieldTest
    case observed
    case userEntered
    case agePredicted
    case unavailable

    public var displayName: String {
        switch self {
        case .laboratoryMeasured: return "Laboratory measured"
        case .fieldTest: return "Field tested"
        case .observed: return "Observed"
        case .userEntered: return "User entered"
        case .agePredicted: return "Age-estimated"
        case .unavailable: return "Unavailable"
        }
    }
}

public enum RelativeIntensity: String, Codable, Sendable, Equatable, Hashable {
    case veryLight, light, moderate, vigorous, veryHard, nearMaximal, unknown

    public var displayName: String {
        switch self {
        case .veryLight: return "Very light"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .vigorous: return "Vigorous"
        case .veryHard: return "Very hard"
        case .nearMaximal: return "Near maximal"
        case .unknown: return "Unclassified"
        }
    }
}

public enum GuidelineIntensity: String, Codable, Sendable, Equatable, Hashable {
    case belowModerate, moderate, vigorous, unknown

    public var displayName: String {
        switch self {
        case .belowModerate: return "Below moderate"
        case .moderate: return "Moderate"
        case .vigorous: return "Vigorous"
        case .unknown: return "Unclassified"
        }
    }

    public var creditMultiplier: Double {
        switch self {
        case .belowModerate, .unknown: return 0
        case .moderate: return 1
        case .vigorous: return 2
        }
    }
}

public enum IntensityConfidence: String, Codable, Sendable, Equatable, Hashable {
    case high, medium, estimated, unavailable

    public var displayName: String { rawValue.capitalized }
}

public enum IntensityMethod: String, Codable, Sendable, Equatable, Hashable {
    case heartRateReserve
    case percentMaximumHeartRate
    case activityMetadata
    case unavailable

    public var displayName: String {
        switch self {
        case .heartRateReserve: return "Heart-rate reserve"
        case .percentMaximumHeartRate: return "% maximum heart rate"
        case .activityMetadata: return "Activity metadata"
        case .unavailable: return "Unavailable"
        }
    }
}

public enum TrainingZone: Int, Codable, CaseIterable, Hashable, Sendable {
    case z1 = 1, z2, z3, z4, z5

    public var displayName: String { "Zone \(rawValue)" }
}

public enum TrainingZonePolicy: String, Codable, Sendable, Equatable, Hashable {
    case hrrFiveZone
    case thresholdBased
    case custom

    public var displayName: String {
        switch self {
        case .hrrFiveZone: return "5-zone HRR"
        case .thresholdBased: return "Threshold-based"
        case .custom: return "Custom"
        }
    }
}

/// User/profile inputs used by the pure classifier. VO₂ max is contextual only
/// in V1 and is deliberately never used to manufacture HR thresholds.
public struct CardioIntensityProfile: Codable, Equatable, Sendable {
    public var restingHR: Double?
    public var maximumHR: Double?
    public var maximumHRSource: HRMaximumSource
    public var vo2Max: Double?
    public var vt1HR: Double?
    public var vt2HR: Double?
    public var updatedAt: Date?

    public init(restingHR: Double? = nil, maximumHR: Double? = nil,
                maximumHRSource: HRMaximumSource = .unavailable,
                vo2Max: Double? = nil, vt1HR: Double? = nil, vt2HR: Double? = nil,
                updatedAt: Date? = nil) {
        self.restingHR = restingHR
        self.maximumHR = maximumHR
        self.maximumHRSource = maximumHRSource
        self.vo2Max = vo2Max
        self.vt1HR = vt1HR
        self.vt2HR = vt2HR
        self.updatedAt = updatedAt
    }

    public static func ageEstimated(age: Int?, restingHR: Double? = nil,
                                    updatedAt: Date? = nil) -> CardioIntensityProfile {
        guard let age, age > 0 else {
            return CardioIntensityProfile(restingHR: restingHR,
                                          maximumHR: nil,
                                          maximumHRSource: .unavailable,
                                          updatedAt: updatedAt)
        }
        return CardioIntensityProfile(restingHR: restingHR,
                                      maximumHR: HeartRateMaximum.tanaka(age: age),
                                      maximumHRSource: .agePredicted,
                                      updatedAt: updatedAt)
    }

    /// Applies the stable source precedence used by every recording surface:
    /// laboratory result, field test, observed maximum, explicit user entry,
    /// then age estimate. Invalid values are ignored rather than persisted as
    /// authoritative thresholds.
    public static func resolved(restingHR: Double? = nil,
                                laboratoryMaximumHR: Double? = nil,
                                fieldMaximumHR: Double? = nil,
                                observedMaximumHR: Double? = nil,
                                userEnteredMaximumHR: Double? = nil,
                                age: Int? = nil, vo2Max: Double? = nil,
                                updatedAt: Date? = nil) -> CardioIntensityProfile {
        let candidates: [(Double?, HRMaximumSource)] = [
            (laboratoryMaximumHR, .laboratoryMeasured),
            (fieldMaximumHR, .fieldTest),
            (observedMaximumHR, .observed),
            (userEnteredMaximumHR, .userEntered)
        ]
        if let (maximum, source) = candidates.first(where: { candidate in
            guard let value = candidate.0 else { return false }
            return value.isFinite && value >= 100 && value <= 240
        }) {
            return CardioIntensityProfile(restingHR: restingHR, maximumHR: maximum,
                                          maximumHRSource: source, vo2Max: vo2Max,
                                          updatedAt: updatedAt)
        }
        var profile = ageEstimated(age: age, restingHR: restingHR, updatedAt: updatedAt)
        profile.vo2Max = vo2Max
        return profile
    }

    public var validHeartRateReserve: Double? {
        guard let restingHR, let maximumHR,
              restingHR > 0, maximumHR > restingHR else { return nil }
        return maximumHR - restingHR
    }
}

public enum HeartRateMaximum {
    /// Tanaka et al. (2001): HRmax = 208 − 0.7 × age. This is an estimate,
    /// never presented as a measured maximum.
    public static func tanaka(age: Int) -> Double {
        208 - 0.7 * Double(age)
    }
}

/// One timestamped heart-rate sample classified independently of workout type.
public struct IntensityClassification: Codable, Equatable, Sendable {
    public let heartRate: Double?
    public let hrrFraction: Double?
    public let maximumFraction: Double?
    public let relativeIntensity: RelativeIntensity
    public let guidelineIntensity: GuidelineIntensity
    public let trainingZone: TrainingZone?
    public let method: IntensityMethod
    public let confidence: IntensityConfidence

    public init(heartRate: Double?, hrrFraction: Double?, maximumFraction: Double?,
                relativeIntensity: RelativeIntensity, guidelineIntensity: GuidelineIntensity,
                trainingZone: TrainingZone?, method: IntensityMethod,
                confidence: IntensityConfidence) {
        self.heartRate = heartRate
        self.hrrFraction = hrrFraction
        self.maximumFraction = maximumFraction
        self.relativeIntensity = relativeIntensity
        self.guidelineIntensity = guidelineIntensity
        self.trainingZone = trainingZone
        self.method = method
        self.confidence = confidence
    }
}

/// All boundaries live here so the UI, iPhone, Watch, and weekly aggregation
/// cannot silently drift. HRR is treated as %VO₂ reserve, not %VO₂ max.
public enum CardioIntensityPolicy {
    public static let algorithmVersion: CardioAlgorithmVersion = .hrrGuidelineV1
    public static let trainingZonePolicy: TrainingZonePolicy = .hrrFiveZone
    public static let veryLightHRR = 0.30
    public static let lightHRR = 0.40
    public static let moderateHRR = 0.60
    public static let veryHardHRR = 0.85
    public static let nearMaximalHRR = 0.95
    public static let moderateMaximumFraction = 0.70
    public static let vigorousMaximumFraction = 0.80
    public static let citationIDs = ["swainLeutholtz1997HRR", "acsmGarber2011AerobicGuidelines",
                                     "piercy2018PhysicalActivityGuidelines", "tanakaMaxHR2001"]
}

public enum CardioIntensityClassifier {
    public static func classify(heartRate: Double, profile: CardioIntensityProfile,
                                zonePolicy: TrainingZonePolicy = CardioIntensityPolicy.trainingZonePolicy)
        -> IntensityClassification {
        guard heartRate.isFinite, heartRate >= 30, heartRate <= 240 else {
            return unavailable(heartRate: heartRate)
        }

        if let hrr = profile.validHeartRateReserve, let maximumHR = profile.maximumHR {
            let fraction = (heartRate - profile.restingHR!) / hrr
            let relative: RelativeIntensity
            switch fraction {
            case ..<CardioIntensityPolicy.veryLightHRR: relative = .veryLight
            case ..<CardioIntensityPolicy.lightHRR: relative = .light
            case ..<CardioIntensityPolicy.moderateHRR: relative = .moderate
            case ..<CardioIntensityPolicy.veryHardHRR: relative = .vigorous
            case ..<CardioIntensityPolicy.nearMaximalHRR: relative = .veryHard
            default: relative = .nearMaximal
            }
            let guideline: GuidelineIntensity = fraction < CardioIntensityPolicy.lightHRR
                ? .belowModerate : fraction < CardioIntensityPolicy.moderateHRR ? .moderate : .vigorous
            return IntensityClassification(
                heartRate: heartRate, hrrFraction: fraction,
                maximumFraction: heartRate / maximumHR, relativeIntensity: relative,
                guidelineIntensity: guideline, trainingZone: zone(forHRR: fraction, policy: zonePolicy),
                method: .heartRateReserve,
                confidence: confidence(for: profile.maximumHRSource))
        }

        guard let maximumHR = profile.maximumHR, maximumHR > 0 else {
            return unavailable(heartRate: heartRate)
        }
        let fraction = heartRate / maximumHR
        let relative: RelativeIntensity
        switch fraction {
        case ..<0.60: relative = .veryLight
        case ..<0.70: relative = .light
        case ..<0.80: relative = .moderate
        case ..<0.90: relative = .vigorous
        case ..<0.95: relative = .veryHard
        default: relative = .nearMaximal
        }
        let guideline: GuidelineIntensity = fraction < CardioIntensityPolicy.moderateMaximumFraction
            ? .belowModerate : fraction < CardioIntensityPolicy.vigorousMaximumFraction ? .moderate : .vigorous
        return IntensityClassification(
            heartRate: heartRate, hrrFraction: nil, maximumFraction: fraction,
            relativeIntensity: relative, guidelineIntensity: guideline,
            trainingZone: zone(forMaximumFraction: fraction),
            method: .percentMaximumHeartRate,
            confidence: confidence(for: profile.maximumHRSource))
    }

    private static func zone(forHRR fraction: Double, policy: TrainingZonePolicy) -> TrainingZone? {
        guard policy == .hrrFiveZone else { return nil }
        switch fraction {
        case ..<CardioIntensityPolicy.veryLightHRR: return .z1
        case ..<CardioIntensityPolicy.lightHRR: return .z2
        case ..<CardioIntensityPolicy.moderateHRR: return .z3
        case ..<CardioIntensityPolicy.veryHardHRR: return .z4
        default: return .z5
        }
    }

    private static func zone(forMaximumFraction fraction: Double) -> TrainingZone {
        switch fraction {
        case ..<0.60: return .z1
        case ..<0.70: return .z2
        case ..<0.80: return .z3
        case ..<0.90: return .z4
        default: return .z5
        }
    }

    private static func unavailable(heartRate: Double?) -> IntensityClassification {
        IntensityClassification(heartRate: heartRate, hrrFraction: nil, maximumFraction: nil,
                                relativeIntensity: .unknown, guidelineIntensity: .unknown,
                                trainingZone: nil, method: .unavailable, confidence: .unavailable)
    }

    private static func confidence(for source: HRMaximumSource) -> IntensityConfidence {
        switch source {
        case .laboratoryMeasured, .fieldTest: return .high
        case .observed, .userEntered: return .medium
        case .agePredicted: return .estimated
        case .unavailable: return .unavailable
        }
    }
}

public struct CardioMinuteSummary: Codable, Equatable, Sendable {
    public let actualDuration: TimeInterval
    public let classifiedDuration: TimeInterval
    public let unclassifiedDuration: TimeInterval
    public let belowModerateDuration: TimeInterval
    public let moderateDuration: TimeInterval
    public let vigorousDuration: TimeInterval
    public let zoneDurations: [TrainingZone: TimeInterval]
    public let algorithmVersion: CardioAlgorithmVersion
    public let method: IntensityMethod
    public let confidence: IntensityConfidence

    public init(actualDuration: TimeInterval, classifiedDuration: TimeInterval,
                unclassifiedDuration: TimeInterval, belowModerateDuration: TimeInterval,
                moderateDuration: TimeInterval, vigorousDuration: TimeInterval,
                zoneDurations: [TrainingZone: TimeInterval],
                algorithmVersion: CardioAlgorithmVersion = CardioIntensityPolicy.algorithmVersion,
                method: IntensityMethod, confidence: IntensityConfidence) {
        self.actualDuration = actualDuration
        self.classifiedDuration = classifiedDuration
        self.unclassifiedDuration = unclassifiedDuration
        self.belowModerateDuration = belowModerateDuration
        self.moderateDuration = moderateDuration
        self.vigorousDuration = vigorousDuration
        self.zoneDurations = zoneDurations
        self.algorithmVersion = algorithmVersion
        self.method = method
        self.confidence = confidence
    }

    public var moderateEquivalentMinutes: Double {
        moderateDuration / 60 + 2 * vigorousDuration / 60
    }
}

/// Integrates the time represented by valid HR samples. Gaps longer than two
/// minutes are intentionally left unclassified instead of being interpolated.
public enum CardioMinuteAccumulator {
    public static let maximumSampleGap: TimeInterval = 120

    public static func summarize(duration: TimeInterval, samples: [HRSamplePoint],
                                 profile: CardioIntensityProfile,
                                 zonePolicy: TrainingZonePolicy = CardioIntensityPolicy.trainingZonePolicy)
        -> CardioMinuteSummary {
        let total = max(0, duration)
        let valid = samples.filter { $0.t.isFinite && $0.bpm.isFinite && $0.bpm >= 30 && $0.bpm <= 240 }
            .sorted { $0.t < $1.t }
        var buckets: [RelativeIntensity: TimeInterval] = [:]
        var guideline: [GuidelineIntensity: TimeInterval] = [:]
        var zones: [TrainingZone: TimeInterval] = [:]
        var classified = 0.0
        var unclassified = 0.0
        var cursor = 0.0
        var methods = Set<IntensityMethod>()
        var confidences = Set<IntensityConfidence>()

        for (index, sample) in valid.enumerated() {
            let start = min(total, max(0, sample.t))
            if start > cursor { unclassified += start - cursor }
            let next = index + 1 < valid.count ? min(total, max(start, valid[index + 1].t)) : total
            let representedEnd = min(next, start + maximumSampleGap)
            if representedEnd > start {
                let result = CardioIntensityClassifier.classify(heartRate: sample.bpm,
                                                                 profile: profile,
                                                                 zonePolicy: zonePolicy)
                let span = representedEnd - start
                if result.guidelineIntensity == .unknown {
                    unclassified += span
                } else {
                    classified += span
                    buckets[result.relativeIntensity, default: 0] += span
                    guideline[result.guidelineIntensity, default: 0] += span
                    if let zone = result.trainingZone { zones[zone, default: 0] += span }
                    methods.insert(result.method)
                    confidences.insert(result.confidence)
                }
                cursor = max(cursor, representedEnd)
            }
        }
        if valid.isEmpty { unclassified = total }
        else if cursor < total { unclassified += total - cursor }

        let method = methods.count == 1 ? methods.first! : methods.isEmpty ? .unavailable : .activityMetadata
        let confidence: IntensityConfidence
        if confidences.contains(.unavailable) || methods.isEmpty { confidence = .unavailable }
        else if confidences.contains(.estimated) { confidence = .estimated }
        else if confidences.contains(.medium) { confidence = .medium }
        else { confidence = .high }
        return CardioMinuteSummary(
            actualDuration: total,
            classifiedDuration: min(total, classified),
            unclassifiedDuration: min(total, unclassified),
            belowModerateDuration: guideline[.belowModerate, default: 0],
            moderateDuration: guideline[.moderate, default: 0],
            vigorousDuration: guideline[.vigorous, default: 0],
            zoneDurations: zones,
            method: method,
            confidence: confidence)
    }
}

public struct WeeklyCardioSummary: Codable, Equatable, Sendable {
    public let actualMinutes: Double
    public let belowModerateMinutes: Double
    public let moderateMinutes: Double
    public let vigorousMinutes: Double
    public let moderateEquivalentMinutes: Double
    public let unclassifiedMinutes: Double
    public let zoneMinutes: [TrainingZone: Double]
    public let guidelineTarget: Double
    public let personalActualMinutesTarget: Double?
    public let algorithmVersion: CardioAlgorithmVersion

    public init(actualMinutes: Double, belowModerateMinutes: Double,
                moderateMinutes: Double, vigorousMinutes: Double,
                moderateEquivalentMinutes: Double, unclassifiedMinutes: Double,
                zoneMinutes: [TrainingZone: Double], guidelineTarget: Double = 150,
                personalActualMinutesTarget: Double? = nil,
                algorithmVersion: CardioAlgorithmVersion) {
        self.actualMinutes = actualMinutes
        self.belowModerateMinutes = belowModerateMinutes
        self.moderateMinutes = moderateMinutes
        self.vigorousMinutes = vigorousMinutes
        self.moderateEquivalentMinutes = moderateEquivalentMinutes
        self.unclassifiedMinutes = unclassifiedMinutes
        self.zoneMinutes = zoneMinutes
        self.guidelineTarget = guidelineTarget
        self.personalActualMinutesTarget = personalActualMinutesTarget
        self.algorithmVersion = algorithmVersion
    }

    public static let empty = WeeklyCardioSummary(
        actualMinutes: 0, belowModerateMinutes: 0, moderateMinutes: 0,
        vigorousMinutes: 0, moderateEquivalentMinutes: 0, unclassifiedMinutes: 0,
        zoneMinutes: [:], algorithmVersion: CardioAlgorithmVersion.hrrGuidelineV1)
}

public enum WeeklyCardioAggregator {
    public static func summarize(_ workouts: [CardioWorkout], since: Date,
                                 profile: CardioIntensityProfile? = nil,
                                 actualMinutesTarget: Double? = nil) -> WeeklyCardioSummary {
        var actual = 0.0
        var below = 0.0
        var moderate = 0.0
        var vigorous = 0.0
        var unclassified = 0.0
        var zones: [TrainingZone: Double] = [:]
        var usedLegacy = false
        for workout in workouts where workout.deletedAt == nil && workout.start >= since {
            let duration = max(0, workout.duration)
            actual += duration / 60
            let summary: CardioMinuteSummary?
            if let stored = workout.intensitySummary {
                summary = stored
            } else if let profile, !workout.orderedHRSamples.isEmpty {
                summary = CardioMinuteAccumulator.summarize(
                    duration: duration, samples: workout.orderedHRSamples.map { HRSamplePoint(t: $0.t, bpm: $0.bpm) },
                    profile: profile)
            } else {
                summary = nil
                usedLegacy = true
            }
            guard let summary else {
                unclassified += duration / 60
                continue
            }
            below += summary.belowModerateDuration / 60
            moderate += summary.moderateDuration / 60
            vigorous += summary.vigorousDuration / 60
            unclassified += summary.unclassifiedDuration / 60
            for (zone, seconds) in summary.zoneDurations { zones[zone, default: 0] += seconds / 60 }
        }
        return WeeklyCardioSummary(
            actualMinutes: actual, belowModerateMinutes: below,
            moderateMinutes: moderate, vigorousMinutes: vigorous,
            moderateEquivalentMinutes: moderate + vigorous * 2,
            unclassifiedMinutes: unclassified, zoneMinutes: zones,
            guidelineTarget: 150, personalActualMinutesTarget: actualMinutesTarget,
            algorithmVersion: usedLegacy ? .legacy : .hrrGuidelineV1)
    }
}
