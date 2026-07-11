import Foundation

/// Weekly per-muscle volume landmarks — the set-count bands the engine compares a
/// user's training against. These are conservative starting points, not validated
/// physiological thresholds.
///
/// **Deprecated:** Prefer `VolumeGuidance` which uses evidence-informed starting
/// ranges that personalize from the user's own response rather than pseudo-precise
/// MEV/MAV/MRV cutoffs.
public struct VolumeBands: Equatable, Sendable {
    @available(*, deprecated, message: "Use VolumeGuidance.startingTargetRange instead")
    public let mev: Double
    @available(*, deprecated, message: "Use VolumeGuidance.startingTargetRange instead")
    public let mav: Double
    @available(*, deprecated, message: "Use VolumeGuidance.personalBaselineRange instead")
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

    /// Baseline (intermediate) weekly working-set bands per coarse `BodyPart`.
    /// Smaller muscles (arms, calves, abs) sit a touch lower than large compound
    /// regions, but the spread is deliberately gentle — these are starting points.
    static func baseline(for part: BodyPart) -> VolumeBands {
        switch part {
        case .legs, .back, .chest:
            return VolumeBands(mev: 8, mav: 16, mrv: 22)
        case .shoulders:
            return VolumeBands(mev: 8, mav: 16, mrv: 24)
        case .biceps, .triceps:
            return VolumeBands(mev: 6, mav: 14, mrv: 20)
        case .calves, .abs:
            return VolumeBands(mev: 6, mav: 12, mrv: 18)
        }
    }

    /// Experience-scaled bands for a body part. Beginners get lower volume,
    /// advanced lifters higher (per `ExperienceLevel.volumeScale`), keeping the
    /// MEV < MAV < MRV ordering.
    public static func bands(for part: BodyPart, experience: ExperienceLevel) -> VolumeBands {
        let base = baseline(for: part)
        let s = experience.volumeScale
        return VolumeBands(mev: (base.mev * s).rounded(),
                           mav: (base.mav * s).rounded(),
                           mrv: (base.mrv * s).rounded())
    }

    /// Classify a measured weekly set count against the (experience-scaled) bands.
    public static func zone(sets: Double, for part: BodyPart, experience: ExperienceLevel) -> VolumeZone {
        let b = bands(for: part, experience: experience)
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
    public static func productiveTarget(for part: BodyPart, experience: ExperienceLevel) -> Double {
        let b = bands(for: part, experience: experience)
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
