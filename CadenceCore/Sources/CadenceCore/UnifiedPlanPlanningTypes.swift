import Foundation

// MARK: - App-owned planning, templates, and schemes

/// Assistance is orthogonal to authorship. It records which deterministic
/// coach operations have touched a plan without changing who owns the plan.
public enum PlanAssistance: String, Codable, Sendable, Hashable {
    case generated
    case critiqued
    case progressed
    case substituted
    case autoregulated
}

public enum TemplateAuthor: Codable, Equatable, Sendable {
    case builtIn
    case user
    case trainer(TrainerRef)
}

public struct PlanTemplate: Codable, Equatable, Sendable, Identifiable {
    public let id: TemplateID
    public var title: String
    public var author: TemplateAuthor
    public var goal: TrainingGoal
    public var experienceLevel: ExperienceLevel
    public var daysPerWeek: Int
    public var equipmentProfile: [Equipment]
    public var weeks: [PlanWeek]
    public var setSchemes: [SetScheme]
    public var description: String
    public var evidenceNotes: String?
    public var rationale: EngineRationale?

    public init(id: TemplateID = TemplateID(), title: String,
                author: TemplateAuthor = .user, goal: TrainingGoal = .hypertrophy,
                experienceLevel: ExperienceLevel = .intermediate,
                daysPerWeek: Int, equipmentProfile: [Equipment] = [],
                weeks: [PlanWeek], setSchemes: [SetScheme] = [], description: String,
                evidenceNotes: String? = nil, rationale: EngineRationale? = nil) {
        self.id = id
        self.title = title
        self.author = author
        self.goal = goal
        self.experienceLevel = experienceLevel
        self.daysPerWeek = daysPerWeek
        self.equipmentProfile = equipmentProfile
        self.weeks = weeks
        self.setSchemes = setSchemes
        self.description = description
        self.evidenceNotes = evidenceNotes
        self.rationale = rationale
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...7).contains(daysPerWeek), !weeks.isEmpty else {
            throw UnifiedPlanValidationError.invalidTemplate
        }
        for week in weeks { try week.validate() }
        for scheme in setSchemes { try scheme.validate() }
        guard Set(setSchemes.map(\.id)).count == setSchemes.count else {
            throw UnifiedPlanValidationError.duplicateSetSchemeID
        }
    }
}

public enum SchemeKind: Codable, Equatable, Sendable {
    case straightSets
    case doubleProgressionRange
    case topSetBackoffs(backoffPercentOfTop: Double)
    case ascendingPyramid
    case descendingPyramid
    case wave
    case emom
    case custom
}

public enum EffortSpec: Codable, Equatable, Sendable {
    case rpe(Double)
    case rir(Int)
    case rpeRange(ClosedRange<Double>)
    case rirRange(ClosedRange<Int>)
    case none
}

public enum LoadSpec: Codable, Equatable, Sendable {
    case absoluteWeight(value: Double, unit: WeightUnit)
    case percent1RM(Double)
    case bodyweight
    case bodyweightPlus(value: Double, unit: WeightUnit)
    case assisted(value: Double, unit: WeightUnit)
    case band(level: String)
    case machineSetting(String)
    case none
}

public struct SchemeParams: Codable, Equatable, Sendable {
    public var workingSets: Int
    public var repTarget: RepTarget
    public var load: LoadSpec?
    public var effort: EffortSpec?
    public var restSeconds: Int?
    public var includeWarmupRamp: Bool
    public var explicitSets: [PrescribedSet]?

    public init(workingSets: Int, repTarget: RepTarget,
                load: LoadSpec? = nil, effort: EffortSpec? = nil,
                restSeconds: Int? = nil, includeWarmupRamp: Bool = false,
                explicitSets: [PrescribedSet]? = nil) {
        self.workingSets = workingSets
        self.repTarget = repTarget
        self.load = load
        self.effort = effort
        self.restSeconds = restSeconds
        self.includeWarmupRamp = includeWarmupRamp
        self.explicitSets = explicitSets
    }

    public func validate() throws {
        guard workingSets > 0, restSeconds == nil || restSeconds! >= 0 else {
            throw UnifiedPlanValidationError.invalidScheme
        }
        if let explicitSets, explicitSets.isEmpty {
            throw UnifiedPlanValidationError.invalidScheme
        }
        for set in explicitSets ?? [] { try set.validate() }
        if case let .rpe(value)? = effort, !(0...10).contains(value) {
            throw UnifiedPlanValidationError.invalidScheme
        }
        if case let .rir(value)? = effort, !(0...10).contains(value) {
            throw UnifiedPlanValidationError.invalidScheme
        }
    }
}

public struct SetScheme: Codable, Equatable, Sendable, Identifiable {
    public let id: SetSchemeID
    public var displayName: String
    public var kind: SchemeKind
    public var params: SchemeParams
    public var isBuiltIn: Bool
    public var goalAffinity: [TrainingGoal]

    public init(id: SetSchemeID, displayName: String, kind: SchemeKind,
                params: SchemeParams, isBuiltIn: Bool = false,
                goalAffinity: [TrainingGoal] = []) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.params = params
        self.isBuiltIn = isBuiltIn
        self.goalAffinity = goalAffinity
    }

    public func validate() throws {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UnifiedPlanValidationError.invalidScheme
        }
        try params.validate()
        if case let .topSetBackoffs(percent) = kind, !(0...1).contains(percent) {
            throw UnifiedPlanValidationError.invalidScheme
        }
    }
}

public enum PlanningConstraint: Codable, Equatable, Sendable {
    case unavailableExercise(ExerciseKey)
    case unavailableEquipment(Equipment)
    case avoidMovementPattern(MovementPattern)
    case avoidMuscleGroup(MuscleGroup)
    case excludedWeekdays(Set<Weekday>)
    case maximumSessionMinutes(Int)
    case note(String)
}

public enum PeriodizationModel: String, Codable, Sendable {
    case none
    case accumulationIntensificationDeload
    case linear
    case dailyUndulating
    case block
}

/// A repeat is an authoring operation, not a second source of truth for the
/// persisted plan graph. Applying one materializes ordinary weeks/sessions and
/// records the resulting revision in the plan store.
public enum RepeatScope: String, Codable, Sendable {
    case session
    case week
    case mesocycle
}

public struct PlanRepeatRequest: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var scope: RepeatScope
    public var sourceSessionID: UUID?
    public var sourceWeekIndex: Int?
    public var targetWeekIndices: [Int]
    public var targetWeekdays: Set<Weekday>
    public var applyProgression: Bool

    public init(id: UUID = UUID(), scope: RepeatScope,
                sourceSessionID: UUID? = nil, sourceWeekIndex: Int? = nil,
                targetWeekIndices: [Int], targetWeekdays: Set<Weekday> = [],
                applyProgression: Bool = true) {
        self.id = id
        self.scope = scope
        self.sourceSessionID = sourceSessionID
        self.sourceWeekIndex = sourceWeekIndex
        self.targetWeekIndices = targetWeekIndices
        self.targetWeekdays = targetWeekdays
        self.applyProgression = applyProgression
    }

    public func validate() throws {
        guard !targetWeekIndices.isEmpty,
              targetWeekIndices.allSatisfy({ $0 >= 0 }),
              sourceSessionID != nil || sourceWeekIndex != nil else {
            throw UnifiedPlanValidationError.invalidRepeatRequest
        }
        if let sourceWeekIndex, sourceWeekIndex < 0 {
            throw UnifiedPlanValidationError.invalidRepeatRequest
        }
    }
}

/// Structured input for deterministic generation. A future natural-language
/// layer may produce this value, but never chooses prescriptions directly.
public struct PlanningRequest: Codable, Equatable, Sendable {
    public var goal: TrainingGoal
    public var experience: ExperienceLevel
    public var daysPerWeek: Int
    public var sessionLengthMinutes: Int?
    public var equipmentProfile: [Equipment]
    public var constraints: [PlanningConstraint]
    public var preferences: [String]
    public var horizon: PlanHorizon
    public var progression: ProgressionIntent?
    public var periodization: PeriodizationModel?
    public var wantsConditioning: Bool
    public var readiness: ReadinessSignal?
    public var performanceProfiles: [ExercisePerformanceProfile]
    public var referenceDate: Date

    public init(goal: TrainingGoal, experience: ExperienceLevel,
                daysPerWeek: Int, sessionLengthMinutes: Int? = nil,
                equipmentProfile: [Equipment] = [],
                constraints: [PlanningConstraint] = [], preferences: [String] = [],
                horizon: PlanHorizon = .singleWeek,
                progression: ProgressionIntent? = nil,
                periodization: PeriodizationModel? = nil,
                wantsConditioning: Bool = false, readiness: ReadinessSignal? = nil,
                performanceProfiles: [ExercisePerformanceProfile] = [],
                referenceDate: Date = Date()) {
        self.goal = goal
        self.experience = experience
        self.daysPerWeek = daysPerWeek
        self.sessionLengthMinutes = sessionLengthMinutes
        self.equipmentProfile = equipmentProfile
        self.constraints = constraints
        self.preferences = preferences
        self.horizon = horizon
        self.progression = progression
        self.periodization = periodization
        self.wantsConditioning = wantsConditioning
        self.readiness = readiness
        self.performanceProfiles = performanceProfiles
        self.referenceDate = referenceDate
    }

    public func validate() throws {
        guard (1...7).contains(daysPerWeek),
              sessionLengthMinutes == nil || sessionLengthMinutes! > 0 else {
            throw UnifiedPlanValidationError.invalidPlanningRequest
        }
        if case let .nativeCycle(days) = horizon, days < 1 {
            throw UnifiedPlanValidationError.invalidPlanningRequest
        }
        for constraint in constraints {
            if case let .maximumSessionMinutes(minutes) = constraint, minutes <= 0 {
                throw UnifiedPlanValidationError.invalidPlanningRequest
            }
        }
        try readiness?.validate()
        for profile in performanceProfiles { try profile.validate() }
    }
}

// MARK: - Readiness and performance snapshots

public struct ReadinessSignal: Codable, Equatable, Sendable {
    public var date: Date
    public var restingHR: Int?
    public var hrvMillis: Double?
    public var sleepHours: Double?
    public var selfReportedReadiness: Int?
    public var sorenessByMuscle: [MuscleGroup: Int]?

    public init(date: Date = Date(), restingHR: Int? = nil,
                hrvMillis: Double? = nil, sleepHours: Double? = nil,
                selfReportedReadiness: Int? = nil,
                sorenessByMuscle: [MuscleGroup: Int]? = nil) {
        self.date = date
        self.restingHR = restingHR
        self.hrvMillis = hrvMillis
        self.sleepHours = sleepHours
        self.selfReportedReadiness = selfReportedReadiness
        self.sorenessByMuscle = sorenessByMuscle
    }

    public func validate() throws {
        if let restingHR, !(20...260).contains(restingHR) {
            throw UnifiedPlanValidationError.invalidReadinessSignal
        }
        if let sleepHours, !(0...24).contains(sleepHours) {
            throw UnifiedPlanValidationError.invalidReadinessSignal
        }
        if let readiness = selfReportedReadiness, !(1...5).contains(readiness) {
            throw UnifiedPlanValidationError.invalidReadinessSignal
        }
        if let soreness = sorenessByMuscle?.values, soreness.contains(where: { !(0...3).contains($0) }) {
            throw UnifiedPlanValidationError.invalidReadinessSignal
        }
    }
}

public enum EstimateConfidence: String, Codable, Sendable {
    case high
    case moderate
    case low
}

public enum EstimateSource: String, Codable, Sendable {
    case testedByTrainer
    case submaximalSet
    case programmedSet
    case acceptedSuggestion
    case manual
}

public enum OneRMFormula: String, Codable, Sendable {
    case epley
    case brzycki
    case blended
}

public struct OneRMEstimatePoint: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var exerciseKey: ExerciseKey
    public var valueKg: Double
    public var measuredAt: Date
    public var formula: OneRMFormula
    public var confidence: EstimateConfidence
    public var source: EstimateSource

    public init(id: UUID = UUID(), exerciseKey: ExerciseKey, valueKg: Double,
                measuredAt: Date = Date(), formula: OneRMFormula,
                confidence: EstimateConfidence, source: EstimateSource) {
        self.id = id
        self.exerciseKey = exerciseKey
        self.valueKg = valueKg
        self.measuredAt = measuredAt
        self.formula = formula
        self.confidence = confidence
        self.source = source
    }

    public func validate() throws {
        guard valueKg.isFinite, valueKg > 0 else {
            throw UnifiedPlanValidationError.invalidPerformanceProfile
        }
    }
}

public struct ExercisePerformanceProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var exerciseKey: ExerciseKey
    public var estimates: [OneRMEstimatePoint]
    public var lastPerformedAt: Date?
    public var sessionsSinceDeload: Int

    public init(id: UUID = UUID(), exerciseKey: ExerciseKey,
                estimates: [OneRMEstimatePoint] = [], lastPerformedAt: Date? = nil,
                sessionsSinceDeload: Int = 0) {
        self.id = id
        self.exerciseKey = exerciseKey
        self.estimates = estimates
        self.lastPerformedAt = lastPerformedAt
        self.sessionsSinceDeload = sessionsSinceDeload
    }

    public var latestEstimate: OneRMEstimatePoint? {
        estimates.max { $0.measuredAt < $1.measuredAt }
    }

    public func validate() throws {
        guard sessionsSinceDeload >= 0 else {
            throw UnifiedPlanValidationError.invalidPerformanceProfile
        }
        for estimate in estimates {
            guard estimate.exerciseKey == exerciseKey else {
                throw UnifiedPlanValidationError.invalidPerformanceProfile
            }
            try estimate.validate()
        }
    }
}

public struct MuscleVolumeWeek: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var muscle: MuscleGroup
    public var weekStart: Date
    public var directSets: Double
    public var fractionalSets: Double

    public init(id: UUID = UUID(), muscle: MuscleGroup, weekStart: Date,
                directSets: Double = 0, fractionalSets: Double = 0) {
        self.id = id
        self.muscle = muscle
        self.weekStart = weekStart
        self.directSets = directSets
        self.fractionalSets = fractionalSets
    }

    public var totalSets: Double { directSets + fractionalSets }

    public func validate() throws {
        guard directSets.isFinite, directSets >= 0,
              fractionalSets.isFinite, fractionalSets >= 0 else {
            throw UnifiedPlanValidationError.invalidVolumeSnapshot
        }
    }
}
