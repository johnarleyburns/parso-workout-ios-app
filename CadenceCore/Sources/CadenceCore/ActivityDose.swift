import Foundation

public enum METBasis: String, Codable, Sendable, Equatable {
    case standardCompendium
    case correctedIndividual
}

public enum METEstimationMethod: String, Codable, Sendable, Equatable {
    case adultCompendium2024
    case resistanceActiveRestEstimate
    case unavailable
}

public enum ActivityCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case running, walking, cycling, swimming, rowing, hiit, boxing, otherCardio, strength
}

public struct METEstimate: Codable, Equatable, Sendable {
    public let standardMET: Double?
    public let metMinutes: Double?
    public let activeMinutes: Double
    public let method: METEstimationMethod
    public let basis: METBasis
    public let confidence: IntensityConfidence
    public let sourceCitationIDs: [String]

    public init(standardMET: Double?, metMinutes: Double?, activeMinutes: Double,
                method: METEstimationMethod, basis: METBasis = .standardCompendium,
                confidence: IntensityConfidence, sourceCitationIDs: [String]) {
        self.standardMET = standardMET
        self.metMinutes = metMinutes
        self.activeMinutes = activeMinutes
        self.method = method
        self.basis = basis
        self.confidence = confidence
        self.sourceCitationIDs = sourceCitationIDs
    }
}

public enum CompendiumMETCatalog {
    /// Representative 2024 Adult Compendium values. These are standardized
    /// population estimates, not individual calorimetry.
    public static func cardio(_ type: CardioType) -> Double {
        switch type {
        case .run: return 9.8
        case .walk: return 3.8
        case .cycle: return 7.5
        case .swim: return 8.0
        case .rowing: return 7.0
        case .hiit: return 7.5
        case .boxing: return 9.0
        case .elliptical: return 5.0
        case .stairClimber: return 8.8
        case .other: return 6.0
        }
    }

    public static let multipleResistanceExercises = 3.5
    public static let squatOrDeadlift = 5.0
    public static let resistanceCircuit = 5.8
    public static let vigorousPowerlifting = 6.0
}

public enum METEstimator {
    public static let citationIDs = ["compendium2024AdultPhysicalActivities", "pag2018AerobicStrengthGuidelines"]

    public static func cardio(type: CardioType, duration: TimeInterval) -> METEstimate {
        let minutes = max(0, duration) / 60
        let met = CompendiumMETCatalog.cardio(type)
        return METEstimate(standardMET: met, metMinutes: met * minutes,
                           activeMinutes: minutes, method: .adultCompendium2024,
                           confidence: .estimated, sourceCitationIDs: citationIDs)
    }

    /// A conservative session estimate for strength: only an estimated active
    /// fraction receives the multiple-exercise resistance MET value; rest and
    /// unobserved setup time are not mislabeled as vigorous lifting.
    public static func strength(duration: TimeInterval, activeFraction: Double = 0.35) -> METEstimate {
        let minutes = max(0, duration) / 60 * min(1, max(0, activeFraction))
        let met = CompendiumMETCatalog.multipleResistanceExercises
        return METEstimate(standardMET: met, metMinutes: met * minutes,
                           activeMinutes: minutes, method: .resistanceActiveRestEstimate,
                           confidence: .estimated, sourceCitationIDs: citationIDs)
    }
}

public struct ActivityDoseSummary: Codable, Equatable, Sendable {
    public let actualMinutes: Double
    public let standardMETMinutes: Double
    public let correctedMETMinutes: Double?
    public let aerobicGuidelineCreditMinutes: Double
    public let strengthDays: Int
    public let categoryMETMinutes: [ActivityCategory: Double]

    public init(actualMinutes: Double, standardMETMinutes: Double,
                correctedMETMinutes: Double? = nil,
                aerobicGuidelineCreditMinutes: Double, strengthDays: Int,
                categoryMETMinutes: [ActivityCategory: Double] = [:]) {
        self.actualMinutes = actualMinutes
        self.standardMETMinutes = standardMETMinutes
        self.correctedMETMinutes = correctedMETMinutes
        self.aerobicGuidelineCreditMinutes = aerobicGuidelineCreditMinutes
        self.strengthDays = strengthDays
        self.categoryMETMinutes = categoryMETMinutes
    }
}

public struct WeeklyActivitySummary: Codable, Equatable, Sendable {
    public let actualActivityMinutes: Double
    public let totalStandardMETMinutes: Double
    public let aerobic: WeeklyCardioSummary
    public let strengthDays: Int
    public let metMinutesByActivity: [ActivityCategory: Double]

    public init(actualActivityMinutes: Double, totalStandardMETMinutes: Double,
                aerobic: WeeklyCardioSummary, strengthDays: Int,
                metMinutesByActivity: [ActivityCategory: Double]) {
        self.actualActivityMinutes = actualActivityMinutes
        self.totalStandardMETMinutes = totalStandardMETMinutes
        self.aerobic = aerobic
        self.strengthDays = strengthDays
        self.metMinutesByActivity = metMinutesByActivity
    }
}

public enum WeeklyActivityDoseAggregator {
    public static func summarize(cardio: [CardioWorkout], sessions: [WorkoutSession],
                                 since: Date, profile: CardioIntensityProfile? = nil)
        -> WeeklyActivitySummary {
        let aerobic = WeeklyCardioAggregator.summarize(cardio, since: since, profile: profile)
        var actual = aerobic.actualMinutes
        var total = 0.0
        var byCategory: [ActivityCategory: Double] = [:]
        for workout in cardio where workout.deletedAt == nil && workout.start >= since {
            let estimate = workout.standardMETMinutes.map {
                METEstimate(standardMET: workout.standardMETValue, metMinutes: $0,
                            activeMinutes: workout.duration / 60,
                            method: METEstimationMethod(rawValue: workout.metMethodRaw ?? "") ?? .adultCompendium2024,
                            basis: METBasis(rawValue: workout.metBasisRaw ?? "") ?? .standardCompendium,
                            confidence: .estimated, sourceCitationIDs: METEstimator.citationIDs)
            } ?? METEstimator.cardio(type: workout.typeValue, duration: workout.duration)
            let category = category(for: workout.typeValue)
            byCategory[category, default: 0] += estimate.metMinutes ?? 0
            total += estimate.metMinutes ?? 0
        }
        var days = Set<DateComponents>()
        for session in sessions where session.deletedAt == nil && session.date >= since {
            let estimate = METEstimator.strength(duration: session.duration)
            byCategory[.strength, default: 0] += estimate.metMinutes ?? 0
            total += estimate.metMinutes ?? 0
            actual += max(0, session.duration) / 60
            let cal = Calendar.current
            days.insert(cal.dateComponents([.era, .year, .month, .day], from: session.date))
        }
        return WeeklyActivitySummary(actualActivityMinutes: actual,
                                     totalStandardMETMinutes: total,
                                     aerobic: aerobic, strengthDays: days.count,
                                     metMinutesByActivity: byCategory)
    }

    private static func category(for type: CardioType) -> ActivityCategory {
        switch type {
        case .run: return .running
        case .walk: return .walking
        case .cycle: return .cycling
        case .swim: return .swimming
        case .rowing: return .rowing
        case .hiit: return .hiit
        case .boxing: return .boxing
        case .elliptical, .stairClimber: return .otherCardio
        case .other: return .otherCardio
        }
    }
}
