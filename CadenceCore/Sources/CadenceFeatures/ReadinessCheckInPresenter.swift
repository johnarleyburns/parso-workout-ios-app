import Foundation
import CadenceCore

/// Pure presentation and validation helpers for the optional daily check-in.
/// Readiness is a soft coaching signal, never a medical or hard eligibility gate.
public enum ReadinessCheckInPresenter {
    public static let scale = 1...5

    public static func summary(for entry: ReadinessEntry) -> String {
        if entry.hasPainOrIllnessConcern {
            return "Pain or illness noted"
        }
        let average = Double(entry.muscleSoreness + entry.fatigueEnergy
            + entry.sleepQuality + entry.stressMood) / 4
        switch average {
        case ..<2.5: return "Recovery may be limited"
        case 2.5..<3.75: return "Recovery looks mixed"
        default: return "Recovery looks good"
        }
    }

    public static func detail(for entry: ReadinessEntry) -> String {
        let values = [entry.muscleSoreness, entry.fatigueEnergy,
                      entry.sleepQuality, entry.stressMood]
        let average = Double(values.reduce(0, +)) / Double(values.count)
        let score = String(format: "%.1f", average)
        return "Average \(score)/5 · optional coaching context"
    }

    public static func validate(muscleSoreness: Int, fatigueEnergy: Int,
                                sleepQuality: Int, stressMood: Int) -> Bool {
        [muscleSoreness, fatigueEnergy, sleepQuality, stressMood]
            .allSatisfy { scale.contains($0) }
    }
}
