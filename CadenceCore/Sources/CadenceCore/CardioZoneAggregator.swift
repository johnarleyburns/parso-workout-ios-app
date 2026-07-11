import Foundation

/// Weekly cardio time-in-heart-rate-zone aggregation (issue 7). Pure/testable: the
/// app maps its `CardioWorkout` rows into `Sample`s. When a workout carries real HR
/// samples, its duration is distributed across zones by those samples; when HR is
/// missing, the whole duration is placed in a zone estimated from the modality's
/// typical %HRmax (using the age-based Tanaka HRmax). Zones cite `tanakaMaxHR2001`.
public enum CardioZoneAggregator {

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
            let nextT = i + 1 < samples.count ? samples[i + 1].t : totalSeconds
            let span = max(0, nextT - sample.t)
            let zone = CardioMath.hrZone(bpm: sample.bpm, maxHR: maxHR)
            result[zone, default: 0] += span / 60
        }
        return result
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
