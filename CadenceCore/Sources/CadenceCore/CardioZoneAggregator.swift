import Foundation

/// Weekly cardio time-in-heart-rate-zone aggregation (issue 7). Pure/testable: the
/// app maps its `CardioWorkout` rows into `Sample`s. When a workout carries real HR
/// samples, its duration is distributed across zones by those samples; when HR is
/// missing, the whole duration is placed in a zone estimated from the modality's
/// typical %HRmax (using the age-based Tanaka HRmax). Zones cite `tanakaMaxHR2001`.
public enum CardioZoneAggregator {

    /// The effort distribution for one cardio session. Unlike a single
    /// session-wide label, this preserves the amount of easy, moderate, and
    /// vigorous work when heart-rate samples show intervals.
    public struct IntensityProfile: Sendable, Equatable {
        public let easyMinutes: Double
        public let moderateMinutes: Double
        public let vigorousMinutes: Double
        public let moderateEquivalentMinutes: Double
        public let isIntervalLike: Bool
        public let hasHeartRateSamples: Bool

        public var totalMinutes: Double {
            easyMinutes + moderateMinutes + vigorousMinutes
        }

        /// A session label remains useful for coach matching, while the
        /// weighted minute fields prevent a short interval peak from making
        /// the whole workout count as vigorous.
        public var dominantIntensity: CoachSession.AerobicIntensity {
            guard totalMinutes > 0 else { return .easy }
            if isIntervalLike || vigorousMinutes / totalMinutes >= 0.5 {
                return .vigorous
            }
            if (moderateMinutes + vigorousMinutes) / totalMinutes >= 0.5 {
                return .moderate
            }
            return .easy
        }
    }

    /// One HR sample: seconds-since-start + bpm.
    public struct HRPoint: Sendable, Equatable {
        public let t: TimeInterval
        public let bpm: Double
        public init(t: TimeInterval, bpm: Double) { self.t = t; self.bpm = bpm }
    }

    /// A cardio session reduced to what the zone math needs.
    public struct Session: Sendable, Equatable {
        public let modality: CoachSession.AerobicModality
        public let intensity: CoachSession.AerobicIntensity
        public let durationMinutes: Double
        public let hrSamples: [HRPoint]
        public init(modality: CoachSession.AerobicModality,
                    intensity: CoachSession.AerobicIntensity,
                    durationMinutes: Double,
                    hrSamples: [HRPoint] = []) {
            self.modality = modality
            self.intensity = intensity
            self.durationMinutes = durationMinutes
            self.hrSamples = hrSamples
        }
    }

    /// Minutes spent in each HR zone (1...5) across all `sessions`, using `age` for
    /// the Tanaka HRmax when HR must be estimated.
    public static func weeklyZoneMinutes(sessions: [Session], age: Int?) -> [Int: Double] {
        let maxHR = CardioMath.defaultMaxHR(age: age)
        var result: [Int: Double] = [:]
        for session in sessions {
            let perZone = zoneMinutes(for: session, maxHR: maxHR)
            for (zone, minutes) in perZone {
                result[zone, default: 0] += minutes
            }
        }
        return result
    }

    /// Returns the effort distribution used by both the coach event model and
    /// the weekly zone surface. HR samples are integrated over the workout
    /// rather than allowing one maximum sample to classify the whole session.
    public static func intensityProfile(for session: Session, maxHR: Double) -> IntensityProfile {
        guard session.durationMinutes > 0 else {
            return IntensityProfile(easyMinutes: 0, moderateMinutes: 0,
                                    vigorousMinutes: 0, moderateEquivalentMinutes: 0,
                                    isIntervalLike: false, hasHeartRateSamples: false)
        }

        guard session.hrSamples.count >= 2 else {
            let zone = estimatedZone(modality: session.modality, intensity: session.intensity)
            return profile(for: [zone: session.durationMinutes],
                           isIntervalLike: false, hasHeartRateSamples: false)
        }

        let zones = zoneMinutesFromSamples(session, maxHR: maxHR)
        return profile(for: zones,
                       isIntervalLike: intervalLike(session, maxHR: maxHR),
                       hasHeartRateSamples: true)
    }

    private static func zoneMinutes(for session: Session, maxHR: Double) -> [Int: Double] {
        guard session.durationMinutes > 0 else { return [:] }
        if session.hrSamples.count >= 2 {
            return zoneMinutesFromSamples(session, maxHR: maxHR)
        }
        // No HR: estimate a single zone from modality + intensity.
        let zone = estimatedZone(modality: session.modality, intensity: session.intensity)
        return [zone: session.durationMinutes]
    }

    private static func zoneMinutesFromSamples(_ session: Session, maxHR: Double) -> [Int: Double] {
        let samples = session.hrSamples.sorted { $0.t < $1.t }
        let totalSeconds = session.durationMinutes * 60
        var result: [Int: Double] = [:]
        for (i, sample) in samples.enumerated() {
            let start = min(totalSeconds, max(0, sample.t))
            let nextT = i + 1 < samples.count ? samples[i + 1].t : totalSeconds
            let end = min(totalSeconds, max(start, nextT))
            let span = max(0, end - start)
            guard sample.bpm > 0, span > 0 else { continue }
            let zone = CardioMath.hrZone(bpm: sample.bpm, maxHR: maxHR)
            result[zone, default: 0] += span / 60
        }
        return result
    }

    private static func profile(for zones: [Int: Double],
                                isIntervalLike: Bool,
                                hasHeartRateSamples: Bool) -> IntensityProfile {
        let easy = zones.filter { $0.key <= 2 }.values.reduce(0, +)
        let moderate = zones.filter { $0.key == 3 }.values.reduce(0, +)
        let vigorous = zones.filter { $0.key >= 4 }.values.reduce(0, +)
        // Public-health guideline credit starts at moderate intensity. Easy / very
        // light work remains visible as actual training time but is not granted
        // fractional credit.
        let weighted = moderate + vigorous * 2
        return IntensityProfile(easyMinutes: easy, moderateMinutes: moderate,
                                vigorousMinutes: vigorous,
                                moderateEquivalentMinutes: weighted,
                                isIntervalLike: isIntervalLike,
                                hasHeartRateSamples: hasHeartRateSamples)
    }

    /// Detects repeated high-HR bouts with recovery between them. A single
    /// isolated peak therefore cannot turn a normal workout into an interval.
    /// The 30-second minimum tolerates the Watch's usual one-minute sample
    /// cadence while rejecting momentary sensor spikes.
    private static func intervalLike(_ session: Session, maxHR: Double) -> Bool {
        let samples = session.hrSamples.sorted { $0.t < $1.t }
        let totalSeconds = session.durationMinutes * 60
        var highBouts = 0
        var inHighBout = false
        var highBoutSeconds = 0.0
        var hadRecovery = false

        for (index, sample) in samples.enumerated() {
            let start = min(totalSeconds, max(0, sample.t))
            let nextT = index + 1 < samples.count ? samples[index + 1].t : totalSeconds
            let end = min(totalSeconds, max(start, nextT))
            let span = max(0, end - start)
            guard span > 0, sample.bpm > 0 else { continue }
            let zone = CardioMath.hrZone(bpm: sample.bpm, maxHR: maxHR)
            if zone >= 4 {
                if !inHighBout {
                    if highBouts > 0 && hadRecovery { highBouts += 1 }
                    else if highBouts == 0 { highBouts = 1 }
                    inHighBout = true
                    highBoutSeconds = 0
                    hadRecovery = false
                }
                highBoutSeconds += span
            } else {
                if inHighBout {
                    if highBoutSeconds < 30 {
                        highBouts = max(0, highBouts - 1)
                    }
                    inHighBout = false
                    highBoutSeconds = 0
                }
                if highBouts > 0 { hadRecovery = true }
            }
        }
        if inHighBout && highBoutSeconds < 30 {
            highBouts = max(0, highBouts - 1)
        }
        return highBouts >= 2
    }

    /// Typical zone when only the modality + intensity are known (no HR). Grounded
    /// in the usual %HRmax each effort sits at; deliberately conservative.
    static func estimatedZone(modality: CoachSession.AerobicModality,
                              intensity: CoachSession.AerobicIntensity) -> Int {
        switch intensity {
        case .easy:
            // Walking easy sits lower than easy running/rowing.
            return modality == .walk ? 1 : 2
        case .moderate:
            return 3
        case .vigorous:
            return 4
        }
    }
}
