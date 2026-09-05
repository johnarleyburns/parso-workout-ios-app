import Foundation

/// The smallest planning boundary needed to hand a unified-plan session to the
/// shipped workout runner. These snapshots deliberately contain no SwiftData
/// references: planning can build and test them off the main actor, while the
/// existing runtime remains responsible for creating WorkoutSession/SetEntry
/// records and HealthKit state.
public struct PlanSessionSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var items: [PlanItemSnapshot]

    public init(id: UUID, title: String, items: [PlanItemSnapshot]) {
        self.id = id
        self.title = title
        self.items = items
    }

    /// Converts the unified value-model session into the runtime boundary. The
    /// exercise-name map is supplied by the bundled catalog at the app edge;
    /// stable exercise keys remain the source of truth in the plan.
    public init(session: Session, exerciseNameByKey: [String: String] = [:]) {
        self.id = session.id
        self.title = session.title
        self.items = session.orderedItems.compactMap { item in
            switch item {
            case let .strength(value):
                return .strength(StrengthItemSnapshot(
                    id: value.id,
                    exerciseKey: value.exerciseKey.raw,
                    exerciseName: exerciseNameByKey[value.exerciseKey.raw] ?? value.exerciseKey.raw,
                    sets: value.sets.map { set in
                        PrescribedSetSnapshot(
                            id: set.id,
                            targetReps: Self.targetReps(for: set.repTarget),
                            load: Self.loadIntent(for: set.load),
                            targetRPE: set.targetRPE,
                            restSeconds: set.restSeconds,
                            isWarmup: set.kind == .warmup)
                    }))
            case let .cardio(value):
                return .cardio(Self.cardioSnapshot(value))
            case let .mobility(value):
                return .mobility(MobilityItemSnapshot(id: value.id, title: value.name,
                                                      rounds: value.rounds))
            case let .instruction(value):
                return .instruction(InstructionItemSnapshot(id: value.id, text: value.text))
            }
        }
    }

    private static func targetReps(for target: RepTarget) -> Int {
        switch target {
        case let .exact(reps): return reps
        case let .range(min, _): return min
        case let .amrap(minimum): return minimum ?? 1
        case .duration, .distance: return 0
        }
    }

    private static func loadIntent(for load: LoadPrescription) -> PrescribedLoadIntent {
        switch load {
        case let .absoluteWeight(value, unit):
            return .absoluteKg(unit == .kg ? value : value * 0.45359237)
        case let .percent1RM(percent, calculatedWeight):
            if let calculatedWeight {
                return .oneRepMaxPercentResolved(percent: percent, weightKg: calculatedWeight)
            }
            return .oneRepMaxPercent(percent)
        case .bodyweight, .bodyweightPlus, .assisted: return .bodyweight
        case .band, .machineSetting, .rpeOnly, .unspecified: return .none
        }
    }

    private static func cardioSnapshot(_ item: CardioItem) -> CardioItemSnapshot {
        switch item.prescription {
        case let .steadyState(value):
            return CardioItemSnapshot(id: item.id, title: activityName(value.activity),
                                      kind: activityName(value.activity),
                                      durationSeconds: value.durationSeconds)
        case let .intervals(value):
            let data = try? JSONEncoder().encode(value)
            return CardioItemSnapshot(id: item.id, title: activityName(value.activity),
                                      kind: "intervals", intervalPlanData: data)
        case let .open(value):
            return CardioItemSnapshot(id: item.id, title: activityName(value.activity),
                                      kind: "open")
        }
    }

    private static func activityName(_ activity: CardioActivity) -> String {
        switch activity {
        case .walk: return "walk"
        case .run: return "run"
        case .bike: return "cycle"
        case .row: return "rowing"
        case .swim: return "swim"
        case .elliptical: return "elliptical"
        case .stairs: return "stairs"
        case let .other(value): return value
        }
    }

    public var strengthItems: [StrengthItemSnapshot] {
        items.compactMap { item in
            if case let .strength(value) = item { return value }
            return nil
        }
    }
}

/// Cardio is included at the boundary so a future planner can hand the
/// existing cardio configuration the same item list. The current session
/// materializer only writes strength prescriptions; it does not create a
/// second cardio runner.
public enum PlanItemSnapshot: Codable, Equatable, Sendable {
    case strength(StrengthItemSnapshot)
    case cardio(CardioItemSnapshot)
    case mobility(MobilityItemSnapshot)
    case instruction(InstructionItemSnapshot)
}

public struct StrengthItemSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    /// Stable DB++ exercise key. `exerciseName` remains the display fallback
    /// for legacy and locally-authored plans.
    public var exerciseKey: String
    public var exerciseName: String
    public var sets: [PrescribedSetSnapshot]

    public init(id: UUID, exerciseKey: String, exerciseName: String,
                sets: [PrescribedSetSnapshot]) {
        self.id = id
        self.exerciseKey = exerciseKey
        self.exerciseName = exerciseName
        self.sets = sets
    }
}

public struct CardioItemSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var kind: String
    public var durationSeconds: Int?
    public var intervalPlanData: Data?

    public init(id: UUID, title: String, kind: String,
                durationSeconds: Int? = nil, intervalPlanData: Data? = nil) {
        self.id = id
        self.title = title
        self.kind = kind
        self.durationSeconds = durationSeconds
        self.intervalPlanData = intervalPlanData
    }
}

public struct MobilityItemSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var rounds: Int?

    public init(id: UUID, title: String, rounds: Int? = nil) {
        self.id = id
        self.title = title
        self.rounds = rounds
    }
}

public struct InstructionItemSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public var text: String

    public init(id: UUID, text: String) {
        self.id = id
        self.text = text
    }
}

public enum PrescribedLoadIntent: Codable, Equatable, Sendable {
    case absoluteKg(Double)
    case oneRepMaxPercent(Double)
    /// A percentage whose concrete weight was already resolved at authoring or
    /// start time. This keeps the intent and snapshot together when a legacy
    /// editor hands the unified graph an already-calculated load.
    case oneRepMaxPercentResolved(percent: Double, weightKg: Double)
    case bodyweight
    case none
}

public struct PrescribedSetSnapshot: Codable, Equatable, Sendable {
    public let id: UUID
    public var targetReps: Int
    public var load: PrescribedLoadIntent
    public var targetRPE: Double?
    public var restSeconds: Int?
    public var isWarmup: Bool

    public init(id: UUID, targetReps: Int,
                load: PrescribedLoadIntent = .none,
                targetRPE: Double? = nil, restSeconds: Int? = nil,
                isWarmup: Bool = false) {
        self.id = id
        self.targetReps = targetReps
        self.load = load
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
    }
}

/// The athlete values needed to resolve a plan at start/send time. The
/// rounding profile is explicit so the same plan resolves identically on every
/// device and in tests.
public struct AthleteExecutionSnapshot: Codable, Equatable, Sendable {
    public var oneRepMaxKgByExerciseKey: [String: Double]
    public var loadIncrementKg: Double

    public init(oneRepMaxKgByExerciseKey: [String: Double] = [:],
                loadIncrementKg: Double = 0.5) {
        self.oneRepMaxKgByExerciseKey = oneRepMaxKgByExerciseKey
        self.loadIncrementKg = loadIncrementKg
    }
}

public struct WorkoutSessionDraft: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let planSessionID: UUID
    public var title: String
    public var plannedExerciseNames: [String]
    public var plannedPrescriptions: [PlannedExercisePrescription]
    public var plannedRepLadder: [Int]
    public var prescribedLoadKg: Double

    public init(sessionID: UUID, planSessionID: UUID, title: String,
                plannedExerciseNames: [String],
                plannedPrescriptions: [PlannedExercisePrescription],
                plannedRepLadder: [Int], prescribedLoadKg: Double) {
        self.sessionID = sessionID
        self.planSessionID = planSessionID
        self.title = title
        self.plannedExerciseNames = plannedExerciseNames
        self.plannedPrescriptions = plannedPrescriptions
        self.plannedRepLadder = plannedRepLadder
        self.prescribedLoadKg = prescribedLoadKg
    }

    /// Writes only prescription/session metadata. No result or HealthKit record
    /// is created here; the existing WorkoutRepository/Watch runner owns that.
    public func apply(to session: WorkoutSession) {
        session.title = title
        session.planSessionID = planSessionID
        session.plannedExerciseNames = plannedExerciseNames
        session.plannedPrescriptions = plannedPrescriptions
        session.plannedRepLadder = plannedRepLadder
        session.prescribedLoadKg = prescribedLoadKg
        session.updatedAt = Date()
    }
}

public enum RuntimePrescriptionAdapterError: Error, Equatable, Sendable {
    case invalidLoadIncrement
    case missingOneRepMax(exerciseKey: String)
    case invalidOneRepMax(exerciseKey: String)
}

/// Pure adapter from the future plan/session boundary into the proven
/// WorkoutSession prescription representation.
public struct RuntimePrescriptionAdapter: Sendable {
    public init() {}

    public func materialize(planSession: PlanSessionSnapshot,
                            athlete: AthleteExecutionSnapshot,
                            existingSessionID: UUID? = nil) throws -> WorkoutSessionDraft {
        guard athlete.loadIncrementKg > 0 else {
            throw RuntimePrescriptionAdapterError.invalidLoadIncrement
        }

        let strength = planSession.strengthItems
        let prescriptions = try strength.map { item in
            PlannedExercisePrescription(
                sourceItemID: item.id,
                exerciseKey: item.exerciseKey,
                exerciseName: item.exerciseName,
                sets: try item.sets.map { set in
                    let resolved = try resolve(set.load,
                                               exerciseKey: item.exerciseKey,
                                               athlete: athlete)
                    return PlannedSetPrescription(
                        sourceSetID: set.id,
                        targetReps: set.targetReps,
                        targetWeightKg: resolved.weightKg,
                        targetLoadMode: resolved.mode,
                        oneRepMaxPercent: resolved.percent,
                        targetRPE: set.targetRPE,
                        restSeconds: set.restSeconds,
                        isWarmup: set.isWarmup)
                })
        }
        let firstSets = prescriptions.first?.sets ?? []
        let firstWeight = firstSets.compactMap(\.targetWeightKg).first ?? 0
        return WorkoutSessionDraft(
            sessionID: existingSessionID ?? UUID(),
            planSessionID: planSession.id,
            title: planSession.title,
            plannedExerciseNames: prescriptions.map(\.exerciseName),
            plannedPrescriptions: prescriptions,
            plannedRepLadder: firstSets.map(\.targetReps),
            prescribedLoadKg: firstWeight)
    }

    public func materialize(planSession: Session,
                            exerciseNameByKey: [String: String] = [:],
                            athlete: AthleteExecutionSnapshot,
                            existingSessionID: UUID? = nil) throws -> WorkoutSessionDraft {
        try materialize(
            planSession: PlanSessionSnapshot(session: planSession,
                                             exerciseNameByKey: exerciseNameByKey),
            athlete: athlete,
            existingSessionID: existingSessionID)
    }

    private struct ResolvedLoad {
        var weightKg: Double?
        var mode: String?
        var percent: Double?
    }

    private func resolve(_ intent: PrescribedLoadIntent,
                         exerciseKey: String,
                         athlete: AthleteExecutionSnapshot) throws -> ResolvedLoad {
        switch intent {
        case let .absoluteKg(weight):
            guard weight >= 0, weight.isFinite else {
                throw RuntimePrescriptionAdapterError.invalidOneRepMax(exerciseKey: exerciseKey)
            }
            return ResolvedLoad(weightKg: weight, mode: "absolute", percent: nil)
        case let .oneRepMaxPercent(percent):
            guard percent > 0, percent <= 2, percent.isFinite,
                  let oneRepMax = athlete.oneRepMaxKgByExerciseKey[exerciseKey],
                  oneRepMax > 0, oneRepMax.isFinite else {
                if athlete.oneRepMaxKgByExerciseKey[exerciseKey] == nil {
                    throw RuntimePrescriptionAdapterError.missingOneRepMax(exerciseKey: exerciseKey)
                }
                throw RuntimePrescriptionAdapterError.invalidOneRepMax(exerciseKey: exerciseKey)
            }
            let raw = oneRepMax * percent
            let rounded = (raw / athlete.loadIncrementKg).rounded() * athlete.loadIncrementKg
            return ResolvedLoad(weightKg: rounded, mode: "oneRepMaxPercent", percent: percent)
        case let .oneRepMaxPercentResolved(percent, weightKg):
            guard percent > 0, percent <= 2, percent.isFinite,
                  weightKg >= 0, weightKg.isFinite else {
                throw RuntimePrescriptionAdapterError.invalidOneRepMax(exerciseKey: exerciseKey)
            }
            return ResolvedLoad(weightKg: weightKg, mode: "oneRepMaxPercent", percent: percent)
        case .bodyweight:
            return ResolvedLoad(weightKg: nil, mode: "bodyweight", percent: nil)
        case .none:
            return ResolvedLoad(weightKg: nil, mode: nil, percent: nil)
        }
    }
}
