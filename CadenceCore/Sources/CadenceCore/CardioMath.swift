import Foundation

/// Pure cardio math — HR zones, pace, and a calorie estimate. No I/O, fully
/// unit-testable. Used by live recording metrics (FR-2.4) and history (FR-5.3).
public enum CardioMath {

    /// Heart-rate zone 1...5 from %HRmax (Karvonen-style fixed bands):
    /// Z1 <60%, Z2 60–70%, Z3 70–80%, Z4 80–90%, Z5 ≥90%. Below Z1 returns 1.
    public static func hrZone(bpm: Double, maxHR: Double) -> Int {
        guard maxHR > 0, bpm > 0 else { return 1 }
        let pct = bpm / maxHR
        switch pct {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default: return 5
        }
    }

    public static func zoneName(_ zone: Int) -> String {
        switch zone {
        case 1: return "Recovery"
        case 2: return "Easy"
        case 3: return "Aerobic"
        case 4: return "Threshold"
        default: return "Max"
        }
    }

    /// Default age-based HRmax (Tanaka): 208 − 0.7·age. Falls back to 190.
    public static func defaultMaxHR(age: Int?) -> Double {
        guard let age, age > 0 else { return 190 }
        return 208 - 0.7 * Double(age)
    }

    /// Pace in seconds per kilometer. Returns nil if distance is ~zero.
    public static func paceSecPerKm(distanceMeters: Double, seconds: TimeInterval) -> Double? {
        guard distanceMeters > 1 else { return nil }
        return seconds / (distanceMeters / 1000)
    }

    /// Progress toward a distance goal (feedback batch 8). Returns the completed
    /// fraction (0...1, clamped) and meters remaining (>= 0). nil goal ⇒ nil.
    public static func goalProgress(distanceMeters: Double, goalMeters: Double?)
        -> (fraction: Double, remainingMeters: Double)? {
        guard let goal = goalMeters, goal > 0 else { return nil }
        let frac = min(max(distanceMeters / goal, 0), 1)
        return (frac, max(0, goal - distanceMeters))
    }

    public static func formatPace(secPerKm: Double?) -> String {
        guard let s = secPerKm, s.isFinite, s > 0 else { return "—" }
        let m = Int(s) / 60, sec = Int(s) % 60
        return String(format: "%d:%02d /km", m, sec)
    }

    /// Calorie-per-minute constant for strength training (MET 5.0 × 75 kg / 60 min).
    /// Used by the strength HK writeback path (FR-2.5).
    public static let strengthCaloriesPerMinute: Double = 6.25

    /// Rough calorie estimate. Prefers an HR-based model when avg HR is known
    /// (gender-neutral approximation), otherwise a MET-based fallback by type.
    public static func estimateCalories(type: CardioType,
                                        seconds: TimeInterval,
                                        avgHR: Double?,
                                        weightKg: Double = 75) -> Double {
        let minutes = seconds / 60
        if let hr = avgHR, hr > 0 {
            // Keytel-style approximation (neutral): kcal/min ≈ (0.45·HR − 23)·w/1000·k
            let perMin = max(0, (0.45 * hr - 23) * weightKg / 1000 * 4.0)
            return perMin * minutes
        }
        let met: Double
        switch type {
        case .run: met = 9.8
        case .cycle: met = 7.5
        case .swim: met = 8.0
        case .boxing: met = 9.0
        case .hiit: met = 8.5
        case .rowing: met = 7.0
        case .walk: met = 3.8
        case .other: met = 6.0
        }
        // kcal = MET · weight(kg) · time(h)
        return met * weightKg * (minutes / 60)
    }
}
