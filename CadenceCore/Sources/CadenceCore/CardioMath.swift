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

    // MARK: - VO2max estimation (FR-10.2)

    /// Cooper 12-minute run test (Cooper 1968).
    /// VO2max (mL/kg/min) = (distance_m - 504.9) / 44.73
    public static func cooperVO2max(distanceMeters: Double) -> Double {
        (distanceMeters - 504.9) / 44.73
    }

    /// 1.5-mile (2.4 km) run test.
    /// VO2max (mL/kg/min) = 483 / time_minutes + 3.5
    public static func run1_5mileVO2max(timeSeconds: Double) -> Double {
        guard timeSeconds > 0 else { return 0 }
        let minutes = timeSeconds / 60
        return 483 / minutes + 3.5
    }

    /// Rockport 1-mile walk test (Kline et al. 1987).
    /// sexCode: 1 = male, 0 = female.
    public static func rockportVO2max(weightKg: Double, ageYears: Int, sexCode: Int,
                                      walkTimeSeconds: Double, endingHR: Double) -> Double {
        let weightLb = weightKg * 2.2046
        let walkTimeMin = walkTimeSeconds / 60
        return 132.853
            - (0.1692 * weightLb)
            - (0.3877 * Double(ageYears))
            + (6.315 * Double(sexCode))
            - (3.2649 * walkTimeMin)
            - (0.1565 * endingHR)
    }

    /// Queens College 3-minute step test (McArdle et al. 1972).
    /// sexCode: 1 = male, 0 = female.
    public static func queensCollegeVO2max(recoveryHR: Double, sexCode: Int) -> Double {
        if sexCode == 1 {
            return 111.33 - (0.42 * recoveryHR)
        } else {
            return 65.81 - (0.1847 * recoveryHR)
        }
    }

    // MARK: - VO2max fitness categories (ACSM)

    public enum FitnessCategory: String, Sendable {
        case superior = "Superior"
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case veryPoor = "Very Poor"
    }

    /// Classifies a VO2max value into a fitness category based on ACSM normative
    /// tables. Simplified: uses broad age bands and the commonly published thresholds.
    /// sexCode: 1 = male, 0 = female.
    public static func fitnessCategory(vo2max: Double, ageYears: Int, sexCode: Int) -> FitnessCategory {
        let thresholds: [Double]
        if sexCode == 1 {
            switch ageYears {
            case ..<30:  thresholds = [55.4, 51.1, 45.4, 41.7, 37.1]
            case ..<40:  thresholds = [54.0, 48.7, 44.0, 40.5, 35.5]
            case ..<50:  thresholds = [52.5, 46.8, 41.0, 37.4, 33.0]
            case ..<60:  thresholds = [48.9, 43.3, 37.4, 33.6, 29.4]
            default:     thresholds = [45.7, 39.5, 33.6, 30.2, 26.1]
            }
        } else {
            switch ageYears {
            case ..<30:  thresholds = [49.6, 43.9, 39.5, 36.1, 32.3]
            case ..<40:  thresholds = [47.4, 42.4, 37.8, 34.6, 30.5]
            case ..<50:  thresholds = [45.3, 39.7, 35.2, 32.3, 28.7]
            case ..<60:  thresholds = [41.1, 36.7, 32.3, 29.4, 25.5]
            default:     thresholds = [37.8, 33.0, 28.7, 25.9, 22.8]
            }
        }
        if vo2max >= thresholds[0] { return .superior }
        if vo2max >= thresholds[1] { return .excellent }
        if vo2max >= thresholds[2] { return .good }
        if vo2max >= thresholds[3] { return .fair }
        if vo2max >= thresholds[4] { return .poor }
        return .veryPoor
    }
}
