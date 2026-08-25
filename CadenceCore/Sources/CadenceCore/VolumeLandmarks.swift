import Foundation

/// Weekly per-muscle volume landmarks — the set-count bands the engine compares a
/// user's training against. These are conservative starting points, not validated
/// physiological thresholds.
///
/// **Deprecated:** Prefer `VolumeGuidance` which uses evidence-informed starting
/// ranges that personalize from the user's own response rather than pseudo-precise
/// MEV/MAV/MRV cutoffs.
public struct VolumeBands: Equatable, Sendable {
    public let mev: Double
    public let mav: Double
    public let mrv: Double

    public init(mev: Double, mav: Double, mrv: Double) {
        self.mev = mev
        self.mav = mav
        self.mrv = mrv
    }
}

/// Where a measured weekly set count falls relative to the bands.
public enum VolumeZone: String, Sendable, Equatable {
    case belowMEV       // under the minimum effective volume
    case productive     // between MEV and MAV — the adaptive range
    case approachingMRV // between MAV and MRV
    case overMRV        // at/above the maximum recoverable volume
}

public enum VolumeLandmarks {

    /// Baseline (intermediate) weekly working-set bands per `MuscleGroup`.
    ///
    /// These preserve the spread the coarse body-part table had — large regions
    /// 8/16/22, arms 6/14/20, small muscles 6/12/18 — and extend it to the groups
    /// the retired `BodyPart` used to hide inside `legs` and `back`. The groups the coach does
    /// not target by default (`MuscleGroup.defaultTracked` excludes them) get
    /// deliberately low bands, so a user who opts one in is not told to run a
    /// training block for it.
    ///
    /// Conservative starting points anchored on the weekly-volume dose-response
    /// work (`volumeDoseResponse`, `pellandDoseResponse2026`), not validated
    /// physiological thresholds for any individual.
    static func baseline(for group: MuscleGroup) -> VolumeBands {
        switch group {
        case .chest, .lats, .quadriceps:
            return VolumeBands(mev: 8, mav: 16, mrv: 22)
        case .shoulders:
            return VolumeBands(mev: 8, mav: 16, mrv: 24)
        case .middleBack, .biceps, .triceps, .glutes, .hamstrings:
            return VolumeBands(mev: 6, mav: 14, mrv: 20)
        case .traps:
            return VolumeBands(mev: 4, mav: 12, mrv: 20)
        case .abdominals, .calves:
            return VolumeBands(mev: 6, mav: 12, mrv: 18)
        case .forearms, .lowerBack, .adductors, .abductors:
            return VolumeBands(mev: 4, mav: 10, mrv: 16)
        case .hipFlexors, .neck, .rotatorCuff, .tibialis:
            return VolumeBands(mev: 2, mav: 6, mrv: 12)
        }
    }

    /// Experience-scaled bands for a muscle group. Beginners get lower volume,
    /// advanced lifters higher (per `ExperienceLevel.volumeScale`), keeping the
    /// MEV < MAV < MRV ordering.
    public static func bands(for group: MuscleGroup, experience: ExperienceLevel) -> VolumeBands {
        scaled(baseline(for: group), experience: experience)
    }

    private static func scaled(_ base: VolumeBands, experience: ExperienceLevel) -> VolumeBands {
        let s = experience.volumeScale
        return VolumeBands(mev: (base.mev * s).rounded(),
                           mav: (base.mav * s).rounded(),
                           mrv: (base.mrv * s).rounded())
    }

    /// Classify a measured weekly set count against the (experience-scaled) bands.
    public static func zone(sets: Double, for group: MuscleGroup, experience: ExperienceLevel) -> VolumeZone {
        zone(sets: sets, bands: bands(for: group, experience: experience))
    }

    private static func zone(sets: Double, bands b: VolumeBands) -> VolumeZone {
        if sets < b.mev { return .belowMEV }
        if sets < b.mav { return .productive }
        if sets < b.mrv { return .approachingMRV }
        return .overMRV
    }

    /// The **productive planning target** — a point in the middle of the adaptive
    /// (MEV→MAV) band that the coach prescribes toward, rather than the bare MEV
    /// floor (issue 1). Prescribing to the midpoint gives small muscles (abs,
    /// calves, arms) a genuinely productive dose instead of the minimum effective
    /// one, while staying well under MRV. Cited to the volume dose-response work
    /// (`volumeDoseResponse`) that the coach already surfaces for volume claims.
    public static func productiveTarget(for group: MuscleGroup, experience: ExperienceLevel) -> Double {
        let b = bands(for: group, experience: experience)
        return ((b.mev + b.mav) / 2).rounded()
    }
}

/// Replaces the fixed MEV/MAV/MRV bands with evidence-informed starting ranges
/// that personalize from the user's own response. The old `VolumeBands` and
/// `VolumeZone` types remain for backward compatibility.
public struct VolumeGuidance: Sendable, Equatable {
    public let observedFractionalSets: Double
    public let startingTargetRange: ClosedRange<Double>?
    public let personalBaselineRange: ClosedRange<Double>?
    public let trend: DoseTrend
    public let confidence: FactConfidence

    public init(observedFractionalSets: Double, startingTargetRange: ClosedRange<Double>? = nil,
                personalBaselineRange: ClosedRange<Double>? = nil, trend: DoseTrend = .unknown,
                confidence: FactConfidence = .low) {
        self.observedFractionalSets = observedFractionalSets
        self.startingTargetRange = startingTargetRange
        self.personalBaselineRange = personalBaselineRange
        self.trend = trend
        self.confidence = confidence
    }
}

public enum DoseTrend: String, Sendable, Equatable {
    case rising, stable, declining, unknown
}
