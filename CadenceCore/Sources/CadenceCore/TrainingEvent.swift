import Foundation

public enum EventSource: String, Sendable, Equatable {
    case appStrength
    case appCardio
    case healthKitImported
    case assessment
}

public enum EventCompletion: String, Sendable, Equatable {
    case completed
    case inProgress
}

public struct StrengthEventDetails: Sendable, Equatable {
    public struct PerExercise: Sendable, Equatable, Identifiable {
        public let exerciseID: String
        public let exerciseName: String
        public let patterns: Set<MovementPattern>
        public let muscleGroups: Set<MuscleGroup>
        public let hardSetCount: Int
        public let topSetWeightKg: Double
        public let topSetReps: Int
        public let bestE1RM: Double
        public let meanRPE: Double?
        public let maxRPE: Double?
        public let reachedFailure: Bool
        public let lastWorkingSetAt: Date

        public var id: String { exerciseID }

        /// True when the exercise work reached a meaningful stimulus threshold
        /// (not just light technique/practice sets). Below this, the work does
        /// not create a recovery gate.
        public var isHard: Bool {
            hardSetCount > 0 && ((maxRPE ?? 0) >= 7 || reachedFailure)
        }
    }

    public let exercises: [PerExercise]
    public let totalHardSets: Int
    public let duration: TimeInterval
    public let sessionEnd: Date
}

public struct AerobicEventDetails: Sendable, Equatable {
    public enum Modality: String, Sendable, Equatable {
        case running, walking, cycling, swimming, rowing, hiit, boxing, other
        
        public var displayName: String {
            switch self {
            case .running: return "Run"
            case .walking: return "Walk"
            case .cycling: return "Cycle"
            case .swimming: return "Swim"
            case .rowing: return "Row"
            case .hiit: return "HIIT"
            case .boxing: return "Boxing"
            case .other: return "Other"
            }
        }
    }

    public enum ImpactLevel: String, Sendable, Equatable {
        case low, moderate, high
    }

    public enum IntensityClassification: String, Sendable, Equatable {
        case easy, moderate, vigorous
    }

    public let modality: Modality
    public let impact: ImpactLevel
    public let duration: TimeInterval
    public let intensity: IntensityClassification
    public let intensityConfidence: FactConfidence
    /// Wall-clock minutes distributed by observed effort. These are distinct
    /// from `duration` so an interval session does not report every minute as
    /// vigorous merely because it reached a high peak.
    public let easyMinutes: Double
    public let moderateMinutes: Double
    public let vigorousMinutes: Double
    public let moderateEquivalentMinutes: Double
    public let lowerBodyLoading: Bool
    public let isInterval: Bool
}

public enum FactConfidence: Int, Sendable, Equatable, Comparable {
    case low
    case moderate
    case high
    public static func < (lhs: FactConfidence, rhs: FactConfidence) -> Bool { lhs.rawValue < rhs.rawValue }
}

public enum TrainingEventKind: Sendable, Equatable {
    case strength(StrengthEventDetails?)
    case aerobic(AerobicEventDetails)
    case intervals(AerobicEventDetails)
    case unknown
}

public struct TrainingEvent: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let kind: TrainingEventKind
    public let source: EventSource
    public let completion: EventCompletion

    public init(id: UUID, start: Date, end: Date, kind: TrainingEventKind,
                source: EventSource, completion: EventCompletion) {
        self.id = id
        self.start = start
        self.end = end
        self.kind = kind
        self.source = source
        self.completion = completion
    }

    public var isStrength: Bool {
        if case .strength = kind { return true }
        return false
    }

    public var isAerobic: Bool {
        if case .aerobic = kind { return true }
        if case .intervals = kind { return true }
        return false
    }

    public var isHard: Bool {
        switch kind {
        case .strength(let details):
            guard let d = details else { return false }
            return d.totalHardSets >= 6 || d.exercises.contains { ($0.maxRPE ?? 0) >= 8 }
        case .aerobic(let d), .intervals(let d):
            return d.intensity == .vigorous
        case .unknown:
            return true
        }
    }

    public var completedHardStrengthExercises: [StrengthEventDetails.PerExercise] {
        guard completion == .completed, case .strength(let details) = kind, let d = details else { return [] }
            return d.exercises.filter { $0.isHard }
    }

    public var lowerBodyPatternsTrained: Set<MovementPattern> {
        guard case .strength(let details) = kind, let d = details else { return [] }
        return Set(d.exercises.flatMap { $0.patterns.filter(\.isLowerBody) })
    }

    public var upperBodyPatternsTrained: Set<MovementPattern> {
        guard case .strength(let details) = kind, let d = details else { return [] }
        return Set(d.exercises.flatMap { $0.patterns.filter(\.isUpperBody) })
    }
}

extension TrainingEvent {
    public static func from(session: WorkoutSession, formula: OneRepMaxFormula = .epley) -> TrainingEvent? {
        let date = session.date
        let endDate = session.endedAt ?? date.addingTimeInterval(3600)
        let completion: EventCompletion = session.endedAt != nil ? .completed : .inProgress

        var perExercise: [StrengthEventDetails.PerExercise] = []
        var totalHardSets = 0

        let sets = session.orderedSets
        let workingSets = sets.filter { !$0.isWarmup && $0.isOwnerSet && $0.reps > 0 }

        var exIndex: [String: (exercise: Exercise, sets: [SetEntry])] = [:]
        for set in workingSets {
            guard let ex = set.exercise, !ex.name.isEmpty else { continue }
            let key = ex.name
            if var entry = exIndex[key] {
                entry.sets.append(set)
                exIndex[key] = entry
            } else {
                exIndex[key] = (ex, [set])
            }
        }

        for (name, entry) in exIndex {
            let ex = entry.exercise
            let hardSets = entry.sets
            let primaryMuscles = ex.primaryMuscles
            let patterns = MovementPattern.patterns(forExerciseNamed: name, primaryMuscles: primaryMuscles)
            let muscleGroups = Set(MuscleGroup.canonicalize(primaryMuscles))
            let hardSetCount = hardSets.count
            totalHardSets += hardSetCount

            let topSet = hardSets.max { a, b in a.effectiveLoadKg < b.effectiveLoadKg }
            let topWeight = topSet?.effectiveLoadKg ?? 0
            let topReps = topSet?.reps ?? 0
            let e1rm = WorkoutMath.estimated1RM(weight: topWeight, reps: topReps, formula: formula)

            let rpes = hardSets.compactMap { $0.rpe }
            let meanRPE = rpes.isEmpty ? nil : rpes.reduce(0, +) / Double(rpes.count)
            let maxRPE = rpes.max()

            let reachedFailure = hardSets.contains { ($0.rpe ?? 0) >= 10 }
            // A session can't end before its last working set: anchor to the later
            // of the set timestamps and the session end (defends against clock skew,
            // imported data, and deterministic test fixtures).
            let lastTime = (hardSets.compactMap(\.completedAt) + [endDate]).max() ?? endDate

            perExercise.append(StrengthEventDetails.PerExercise(
                exerciseID: ex.id.uuidString,
                exerciseName: name,
                patterns: patterns,
                muscleGroups: muscleGroups,
                hardSetCount: hardSetCount,
                topSetWeightKg: topWeight,
                topSetReps: topReps,
                bestE1RM: e1rm,
                meanRPE: meanRPE,
                maxRPE: maxRPE,
                reachedFailure: reachedFailure,
                lastWorkingSetAt: lastTime
            ))
        }

        let details = StrengthEventDetails(
            exercises: perExercise,
            totalHardSets: totalHardSets,
            duration: endDate.timeIntervalSince(date),
            sessionEnd: endDate
        )

        return TrainingEvent(
            id: session.id,
            start: date,
            end: endDate,
            kind: .strength(details),
            source: .appStrength,
            completion: completion
        )
    }

    /// Converts a logged cardio workout into a coach `TrainingEvent`.
    ///
    /// Intensity classification ("coach suggests" plan, Phase 1):
    /// - **Real age for maxHR** — `userAge` anchors HRmax via Tanaka
    ///   (`CardioMath.defaultMaxHR`, tanakaMaxHR2001); nil falls back to 190.
    /// - **Modality floor** — HIIT, boxing, and interval sessions classify at
    ///   least `.vigorous` regardless of HR (they are intense by construction;
    ///   averaging rest intervals must not wash them out).
    /// - **Peak-aware fallback for intervals/combat** — without a sample
    ///     distribution, a peak ≥90% HRmax marks the session vigorous even when
    ///     the average sits below 80%; sampled sessions use their integrated
    ///     effort profile instead.
    public static func from(cardio: CardioWorkout, userAge: Int? = nil) -> TrainingEvent {
        let cardioEnd = cardio.end ?? cardio.start.addingTimeInterval(600)
        let completion: EventCompletion = cardioEnd > cardio.start ? .completed : .inProgress
        let duration = max(0, cardioEnd.timeIntervalSince(cardio.start))

        let cardioType = cardio.typeValue
        let modality: AerobicEventDetails.Modality = switch cardioType {
        case .run: .running
        case .walk: .walking
        case .cycle: .cycling
        case .swim: .swimming
        case .rowing: .rowing
        case .hiit: .hiit
        case .boxing: .boxing
        case .other: .other
        }

        let impact: AerobicEventDetails.ImpactLevel = switch modality {
        case .running, .hiit, .boxing: .high
        case .walking, .swimming: .low
        case .cycling, .rowing, .other: .moderate
        }

        let samples = cardio.orderedHRSamples
        let hasHR = !samples.isEmpty
        let hrSum = hasHR ? samples.map(\.bpm).reduce(0, +) : 0
        let computedAvgHR = hasHR ? hrSum / Double(samples.count) : nil
        let avgHR = cardio.avgHeartRate ?? computedAvgHR
        let computedPeakHR = hasHR ? samples.map(\.bpm).max() : nil
        let peakHR = cardio.maxHeartRate ?? computedPeakHR

        let isIntervalByType = cardioType == .hiit
        // HIIT/boxing/interval work is intense by construction — HR may raise,
        // never lower, the classification (user decision #1).
        let intenseByModality = isIntervalByType || modality == .hiit || modality == .boxing

        let intensity: AerobicEventDetails.IntensityClassification
        let intensityConfidence: FactConfidence
        let maxHR = CardioMath.defaultMaxHR(age: userAge)
        if let hr = avgHR, hr > 0 {
            let pct = hr / maxHR
            let peakPct = (peakHR ?? 0) / maxHR
            if intenseByModality || pct >= 0.80 || peakPct >= 0.90 {
                intensity = .vigorous
            } else if pct >= 0.60 {
                intensity = .moderate
            } else {
                intensity = .easy
            }
            intensityConfidence = .moderate
        } else if intenseByModality {
            // No HR but the modality itself is intense (e.g. phone-logged HIIT).
            intensity = .vigorous
            intensityConfidence = .moderate
        } else {
            intensity = .moderate
            intensityConfidence = .low
        }

        let profileSession = CardioZoneAggregator.Session(
            modality: YourWeekModalityBridge.modality(for: cardioType),
            intensity: YourWeekModalityBridge.intensity(for: intensity),
            durationMinutes: duration / 60,
            hrSamples: samples.map { CardioZoneAggregator.HRPoint(t: $0.t, bpm: $0.bpm) })
        let profile = CardioZoneAggregator.intensityProfile(for: profileSession, maxHR: maxHR)
        let hasObservedInterval = profile.isIntervalLike
        let isInterval = isIntervalByType || hasObservedInterval
        let finalIntensity: AerobicEventDetails.IntensityClassification = switch profile.dominantIntensity {
        case .easy: .easy
        case .moderate: .moderate
        case .vigorous: .vigorous
        }
        // Modality floors remain authoritative for HIIT/boxing, but observed
        // sample distribution controls ordinary cardio classification.
        let resolvedIntensity: AerobicEventDetails.IntensityClassification = intenseByModality
            ? .vigorous : finalIntensity
        let moderateEquivalent = intenseByModality && !profile.hasHeartRateSamples
            ? duration / 60 * 2 : profile.moderateEquivalentMinutes

        let lowerBody: Bool = switch modality {
        case .running, .walking, .cycling, .hiit, .rowing: true
        case .swimming, .boxing, .other: false
        }

        let details = AerobicEventDetails(
            modality: modality,
            impact: impact,
            duration: duration,
            intensity: resolvedIntensity,
            intensityConfidence: profile.hasHeartRateSamples ? .high : intensityConfidence,
            easyMinutes: profile.hasHeartRateSamples ? profile.easyMinutes : (resolvedIntensity == .easy ? duration / 60 : 0),
            moderateMinutes: profile.hasHeartRateSamples ? profile.moderateMinutes : (resolvedIntensity == .moderate ? duration / 60 : 0),
            vigorousMinutes: profile.hasHeartRateSamples ? profile.vigorousMinutes : (resolvedIntensity == .vigorous ? duration / 60 : 0),
            moderateEquivalentMinutes: moderateEquivalent,
            lowerBodyLoading: lowerBody,
            isInterval: isInterval
        )

        return TrainingEvent(
            id: cardio.id,
            start: cardio.start,
            end: cardioEnd,
            kind: isInterval ? .intervals(details) : .aerobic(details),
            source: (cardio.sourceValue == .watch && cardio.healthKitWorkoutUUID != nil) ? .healthKitImported : .appCardio,
            completion: completion
        )
    }

    public static func from(assessment: Assessment) -> TrainingEvent {
        TrainingEvent(
            id: assessment.id,
            start: assessment.date,
            end: assessment.date.addingTimeInterval(600),
            kind: .unknown,
            source: .assessment,
            completion: .completed
        )
    }
}

/// Keeps the core cardio model independent from the feature presenter module.
/// The two enums intentionally have the same cases but live in different
/// layers, so this is the single conversion point used by TrainingEvent.
private enum YourWeekModalityBridge {
    static func modality(for type: CardioType) -> CoachSession.AerobicModality {
        switch type {
        case .walk: return .walk
        case .run: return .run
        case .cycle: return .cycle
        case .swim: return .swim
        case .rowing: return .row
        case .boxing: return .boxing
        default: return .other
        }
    }

    static func intensity(for value: AerobicEventDetails.IntensityClassification)
        -> CoachSession.AerobicIntensity {
        switch value {
        case .easy: return .easy
        case .moderate: return .moderate
        case .vigorous: return .vigorous
        }
    }
}
