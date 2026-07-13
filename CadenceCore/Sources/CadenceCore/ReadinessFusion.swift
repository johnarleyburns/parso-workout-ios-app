import Foundation

/// Fuses passive HealthKit signals (HRV, sleep, resting HR) with the user's
/// self-reported readiness check-in.
///
/// **D4 in code.** Self-report is AUTHORITATIVE where present — `sawMonitoring2016`
/// found self-reported measures outperform objective monitoring, and the coach
/// already carries that citation, so a claim that *overrode* self-report with HRV
/// would contradict a citation the coach ships (a correctness bug under the HARD
/// RULE, not a style choice). Passive signals are a zero-friction prior that:
///
/// - fills the (common) gap where no recent check-in exists, at a *lower*
///   confidence, and
/// - when strongly suppressed with no check-in, raises `promptCheckIn` so the app
///   *asks* the user rather than *assuming*.
public enum ReadinessFusion {

    /// A self-report is authoritative only while it is fresh (≤24h).
    public static let selfReportFreshnessWindow: TimeInterval = 24 * 3600

    public static func fuse(selfReport: ReadinessSnapshot?,
                            passive: PassiveReadinessSignal,
                            now: Date = Date()) -> ReadinessSnapshot {

        let freshSelfReport = selfReport.flatMap { report -> ReadinessSnapshot? in
            guard let captured = report.capturedAt else { return nil }
            return now.timeIntervalSince(captured) <= selfReportFreshnessWindow ? report : nil
        }

        if let report = freshSelfReport {
            // Self-report wins. Passive may add CONTEXT and, when it agrees, nudge
            // confidence up — but it may never override the check-in, and it never
            // lowers self-report's confidence.
            var fused = report
            fused.passive = passive
            fused.promptCheckIn = false  // we already have a fresh check-in

            if passive.makesClaim {
                let passiveIsPoor = passive.level == .suppressed || passive.level == .stronglySuppressed
                if passiveIsPoor == report.isPoor, report.confidence < .high {
                    // Objective signal corroborates the subjective one → more confident.
                    fused.confidence = bump(report.confidence)
                }
            }
            return fused
        }

        // No fresh self-report: passive drives a LOWER-confidence estimate.
        switch passive.level {
        case .insufficientData:
            // Nothing to say. Preserve any stale self-report fields but stay low.
            if let stale = selfReport {
                var s = stale
                s.passive = passive
                s.confidence = .low
                s.promptCheckIn = false
                return s
            }
            return ReadinessSnapshot(soreness: nil, sleepQuality: nil, stress: nil,
                                     motivation: nil, painConcern: false, capturedAt: nil,
                                     confidence: .low, passive: passive, promptCheckIn: false)

        case .normal:
            return ReadinessSnapshot(soreness: nil, sleepQuality: nil, stress: nil,
                                     motivation: nil, painConcern: false, capturedAt: nil,
                                     confidence: .low, passive: passive, promptCheckIn: false)

        case .suppressed:
            // A soft passive red flag. Map to a poor-but-low-confidence readiness.
            return ReadinessSnapshot(soreness: 2, sleepQuality: nil, stress: nil,
                                     motivation: 2, painConcern: false, capturedAt: nil,
                                     confidence: .low, passive: passive, promptCheckIn: false)

        case .stronglySuppressed:
            // Strong passive red flag with NO check-in → ask the user (fixes
            // compliance without contradicting sawMonitoring2016).
            return ReadinessSnapshot(soreness: 2, sleepQuality: 2, stress: nil,
                                     motivation: 2, painConcern: false, capturedAt: nil,
                                     confidence: .low, passive: passive, promptCheckIn: true)
        }
    }

    private static func bump(_ c: FactConfidence) -> FactConfidence {
        switch c {
        case .low: return .moderate
        case .moderate: return .high
        case .high: return .high
        }
    }
}
