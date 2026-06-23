import Foundation

/// Weekly per-muscle volume landmarks — the set-count bands the engine compares a
/// user's training against (strength-pivot §03, rule 1):
///
/// - **MEV** — *minimum effective volume*: below this, too little stimulus to drive
///   adaptation.
/// - **MAV** — *maximum adaptive volume*: the productive working range.
/// - **MRV** — *maximum recoverable volume*: at/above this, fatigue outpaces recovery.
///
/// Bands are expressed as **working sets per `BodyPart` per week** and scale with
/// `ExperienceLevel`. The baseline (intermediate) numbers are conservative,
/// general-population defaults distilled from the weekly-volume dose-response
/// literature (`CitationRegistry.volumeDoseResponse`); they live here as named
/// constants so they're easy to review and revise as evidence updates. They are
/// coaching guidance, not medical thresholds.
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
