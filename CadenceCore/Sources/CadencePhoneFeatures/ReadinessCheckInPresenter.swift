import CadenceFeatures
import Foundation
import CadenceCore

/// Pure presentation and validation helpers for the optional daily check-in.
/// Readiness is a soft coaching signal, never a medical or hard eligibility gate.
public enum ReadinessCheckInPresenter {
    public static let scale = 1...5

    public static func summary(for entry: ReadinessEntry) -> String {
        if entry.hasPainOrIllnessConcern {
            return {
                #if os(Linux)
                "Pain or illness noted"
                #else
                String(localized: "Pain or illness noted", bundle: FeatureLocalization.bundle)
                #endif
            }()
        }
        let average = Double(entry.muscleSoreness + entry.fatigueEnergy
            + entry.sleepQuality + entry.stressMood) / 4
        switch average {
        case ..<2.5: return {
            #if os(Linux)
            "Recovery may be limited"
            #else
            String(localized: "Recovery may be limited", bundle: FeatureLocalization.bundle)
            #endif
        }()
        case 2.5..<3.75: return {
            #if os(Linux)
            "Recovery looks mixed"
            #else
            String(localized: "Recovery looks mixed", bundle: FeatureLocalization.bundle)
            #endif
        }()
        default: return {
            #if os(Linux)
            "Recovery looks good"
            #else
            String(localized: "Recovery looks good", bundle: FeatureLocalization.bundle)
            #endif
        }()
        }
    }

    public static func detail(for entry: ReadinessEntry) -> String {
        let values = [entry.muscleSoreness, entry.fatigueEnergy,
                      entry.sleepQuality, entry.stressMood]
        let average = Double(values.reduce(0, +)) / Double(values.count)
        let score = String(format: "%.1f", average)
        return {
            #if os(Linux)
            "Average \(score)/5 · optional coaching context"
            #else
            String(localized: "Average \(score)/5 · optional coaching context", bundle: FeatureLocalization.bundle)
            #endif
        }()
    }

    public static func validate(muscleSoreness: Int, fatigueEnergy: Int,
                                sleepQuality: Int, stressMood: Int) -> Bool {
        [muscleSoreness, fatigueEnergy, sleepQuality, stressMood]
            .allSatisfy { scale.contains($0) }
    }
}
