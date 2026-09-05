import Foundation

// MARK: - Stable identity, provenance, and plan metadata

/// Stable identifiers used by the unified planning graph. These wrappers keep
/// plan IDs distinct from runtime WorkoutSession UUIDs at API boundaries.
public struct PlanID: Hashable, Codable, Sendable {
    public let raw: UUID

    public init(raw: UUID = UUID()) {
        self.raw = raw
    }
}

public struct TemplateID: Hashable, Codable, Sendable {
    public let raw: UUID

    public init(raw: UUID = UUID()) {
        self.raw = raw
    }
}

public struct ExerciseKey: Hashable, Codable, Sendable {
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }
}

public struct SetSchemeID: Hashable, Codable, Sendable {
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }
}

public struct SupersetGroupID: Hashable, Codable, Sendable {
    public let raw: String

    public init(raw: String) {
        self.raw = raw
    }
}

public struct TrainerRef: Codable, Equatable, Sendable {
    public var displayName: String
    public var shareOwnerID: String

    public init(displayName: String, shareOwnerID: String) {
        self.displayName = displayName
        self.shareOwnerID = shareOwnerID
    }
}

public enum AuthorRef: Codable, Equatable, Sendable {
    case selfAthlete
    case trainer(TrainerRef)
}

public enum PlanProvenance: Codable, Equatable, Sendable {
    case selfAuthored
    case trainerAuthored(trainer: TrainerRef)
    case templateAuthored(templateID: TemplateID, adaptedBy: AuthorRef)
}

public enum AuthoringIdiom: String, Codable, Sendable {
    case compact
    case regular
    case mac
    case watch
}

public enum PlanHorizon: Codable, Equatable, Sendable {
    case singleWeek
    case mesocycle(weeks: Int)
}

public enum PlanStatus: String, Codable, Sendable {
    case draft
    case active
    case archived
}

public enum ProgressionIntent: String, Codable, Sendable {
    case linearLoad
    case doubleProgression
    case percentageBased
    case autoregulated
    case volume
}

/// The rationale shape is intentionally small at this stage. It is enough to
/// preserve generated-plan provenance without coupling the value model to the
/// citation registry or a future SwiftData mapping.
public struct EngineRationale: Codable, Equatable, Sendable {
    public var summary: String
    public var knowledgeBaseVersion: String?
    public var decisions: [RationaleDecision]

    public init(summary: String, knowledgeBaseVersion: String? = nil,
                decisions: [RationaleDecision] = []) {
        self.summary = summary
        self.knowledgeBaseVersion = knowledgeBaseVersion
        self.decisions = decisions
    }
}

public struct RationaleDecision: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var claim: String
    public var basis: String
    public var citationIDs: [String]

    public init(id: UUID = UUID(), claim: String, basis: String,
                citationIDs: [String] = []) {
        self.id = id
        self.claim = claim
        self.basis = basis
        self.citationIDs = citationIDs
    }
}

// MARK: - Unified plan hierarchy

public struct Plan: Codable, Equatable, Sendable, Identifiable {
    public let id: PlanID
    public var title: String
    public var provenance: PlanProvenance
    /// Reuses the shipped app goal taxonomy for this first value-model slice.
    /// The existing type remains the compatibility bridge for coach features.
    public var goal: TrainingGoal
    public var horizon: PlanHorizon
    public var weeks: [PlanWeek]
    public var createdAt: Date
    public var updatedAt: Date
    public var authoredOnIdiom: AuthoringIdiom?
    public var status: PlanStatus
    public var notes: String?
    public var rationale: EngineRationale?

    public init(id: PlanID = PlanID(), title: String,
                provenance: PlanProvenance = .selfAuthored,
                goal: TrainingGoal = .hypertrophy,
                horizon: PlanHorizon = .singleWeek,
                weeks: [PlanWeek], createdAt: Date = Date(),
                updatedAt: Date = Date(), authoredOnIdiom: AuthoringIdiom? = nil,
                status: PlanStatus = .draft, notes: String? = nil,
                rationale: EngineRationale? = nil) {
        self.id = id
        self.title = title
        self.provenance = provenance
        self.goal = goal
        self.horizon = horizon
        self.weeks = weeks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.authoredOnIdiom = authoredOnIdiom
        self.status = status
        self.notes = notes
        self.rationale = rationale
    }

    /// The only normalization this value model performs is a stable Monday-first
    /// view. Stored day identities and weekday values are never rewritten.
    public var mondayFirstWeeks: [PlanWeek] {
        weeks.map { week in
            var copy = week
            copy.days.sort { lhs, rhs in
                Self.mondayFirstRank(lhs.weekday) < Self.mondayFirstRank(rhs.weekday)
            }
            return copy
        }
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UnifiedPlanValidationError.emptyPlanTitle
        }
        guard !weeks.isEmpty else {
            throw UnifiedPlanValidationError.planHasNoWeeks
        }
        switch horizon {
        case .singleWeek where weeks.count != 1:
            throw UnifiedPlanValidationError.horizonMismatch
        case let .mesocycle(count) where count != weeks.count || count < 1:
            throw UnifiedPlanValidationError.horizonMismatch
        default:
            break
        }
        for (position, week) in weeks.enumerated() {
            try week.validate(expectedIndex: position)
        }
    }

    private static func mondayFirstRank(_ weekday: Weekday) -> Int {
        switch weekday {
        case .monday: return 0
        case .tuesday: return 1
        case .wednesday: return 2
        case .thursday: return 3
        case .friday: return 4
        case .saturday: return 5
        case .sunday: return 6
        }
    }
}

public struct PlanWeek: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var index: Int
    public var days: [PlanDay]
    public var intendedProgression: ProgressionIntent?
    public var isDeload: Bool

    public init(id: UUID = UUID(), index: Int, days: [PlanDay],
                intendedProgression: ProgressionIntent? = nil,
                isDeload: Bool = false) {
        self.id = id
        self.index = index
        self.days = days
        self.intendedProgression = intendedProgression
        self.isDeload = isDeload
    }

    public func validate(expectedIndex: Int? = nil) throws {
        guard index >= 0, expectedIndex == nil || index == expectedIndex else {
            throw UnifiedPlanValidationError.invalidWeekIndex(index)
        }
        guard days.count == 7 else {
            throw UnifiedPlanValidationError.weekMustHaveSevenDays
        }
        let weekdays = days.map(\.weekday)
        guard weekdays == [.monday, .tuesday, .wednesday, .thursday,
                           .friday, .saturday, .sunday] else {
            throw UnifiedPlanValidationError.weekdaysMustBeMondayFirst
        }
        for day in days {
            try day.validate()
        }
    }
}

public struct PlanDay: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var weekday: Weekday
    public var sessions: [Session]

    public init(id: UUID = UUID(), weekday: Weekday, sessions: [Session] = []) {
        self.id = id
        self.weekday = weekday
        self.sessions = sessions
    }

    public var isRestDay: Bool { sessions.isEmpty }

    public func validate() throws {
        guard sessions.count <= 2 else {
            throw UnifiedPlanValidationError.dayHasTooManySessions(weekday)
        }
        for session in sessions {
            try session.validate()
        }
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case planned
    case inProgress
    case completed
    case skipped
}

public struct Session: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public var goal: TrainingGoal
    public var items: [WorkoutItem]
    public var estimatedDurationMinutes: Int?
    public var status: SessionStatus
    public var startedAt: Date?
    public var completedAt: Date?
    public var sessionRPE: Double?
    public var painFlag: PainFlag?
    public var note: String?
    public var partners: [PartnerRef]

    public init(id: UUID = UUID(), title: String,
                goal: TrainingGoal = .hypertrophy, items: [WorkoutItem] = [],
                estimatedDurationMinutes: Int? = nil,
                status: SessionStatus = .planned, startedAt: Date? = nil,
                completedAt: Date? = nil, sessionRPE: Double? = nil,
                painFlag: PainFlag? = nil, note: String? = nil,
                partners: [PartnerRef] = []) {
        self.id = id
        self.title = title
        self.goal = goal
        self.items = items
        self.estimatedDurationMinutes = estimatedDurationMinutes
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.sessionRPE = sessionRPE
        self.painFlag = painFlag
        self.note = note
        self.partners = partners
    }

    public var orderedItems: [WorkoutItem] {
        items.sorted { lhs, rhs in
            lhs.order == rhs.order ? lhs.id.uuidString < rhs.id.uuidString : lhs.order < rhs.order
        }
    }

    public func validate() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UnifiedPlanValidationError.emptySessionTitle
        }
        guard items.allSatisfy({ $0.order >= 0 }) else {
            throw UnifiedPlanValidationError.invalidItemOrder
        }
        let ids = items.map(\.id)
        guard Set(ids).count == ids.count else {
            throw UnifiedPlanValidationError.duplicateItemID
        }
        for item in items {
            try item.validate()
        }
    }
}

// MARK: - Workout items and prescriptions

public enum WorkoutItem: Codable, Equatable, Sendable {
    case strength(StrengthItem)
    case cardio(CardioItem)
    case mobility(MobilityItem)
    case instruction(InstructionItem)

    public var id: UUID {
        switch self {
        case let .strength(item): return item.id
        case let .cardio(item): return item.id
        case let .mobility(item): return item.id
        case let .instruction(item): return item.id
        }
    }

    public var order: Int {
        switch self {
        case let .strength(item): return item.order
        case let .cardio(item): return item.order
        case let .mobility(item): return item.order
        case let .instruction(item): return item.order
        }
    }

    public func validate() throws {
        switch self {
        case let .strength(item): try item.validate()
        case let .cardio(item): try item.validate()
        case let .mobility(item): try item.validate()
        case let .instruction(item): try item.validate()
        }
    }
}

public struct StrengthItem: Codable, Equatable, Sendable {
    public let id: UUID
    public var exerciseKey: ExerciseKey
    public var order: Int
    public var instructions: String?
    public var tempo: String?
    public var defaultRestSeconds: Int?
    public var alternateExerciseKey: ExerciseKey?
    public var sets: [PrescribedSet]
    public var schemeApplied: SetSchemeID?
    public var supersetGroup: SupersetGroupID?

    public init(id: UUID = UUID(), exerciseKey: ExerciseKey, order: Int,
                instructions: String? = nil, tempo: String? = nil,
                defaultRestSeconds: Int? = nil,
                alternateExerciseKey: ExerciseKey? = nil,
                sets: [PrescribedSet] = [], schemeApplied: SetSchemeID? = nil,
                supersetGroup: SupersetGroupID? = nil) {
        self.id = id
        self.exerciseKey = exerciseKey
        self.order = order
        self.instructions = instructions
        self.tempo = tempo
        self.defaultRestSeconds = defaultRestSeconds
        self.alternateExerciseKey = alternateExerciseKey
        self.sets = sets
        self.schemeApplied = schemeApplied
        self.supersetGroup = supersetGroup
    }

    public func validate() throws {
        guard order >= 0 else { throw UnifiedPlanValidationError.invalidItemOrder }
        let indices = sets.map(\.setIndex)
        guard indices.allSatisfy({ $0 >= 0 }), Set(indices).count == indices.count else {
            throw UnifiedPlanValidationError.invalidSetIndex
        }
        let ids = sets.map(\.id)
        guard Set(ids).count == ids.count else {
            throw UnifiedPlanValidationError.duplicateSetID
        }
        for set in sets { try set.validate() }
    }
}

public enum SetKind: String, Codable, Sendable {
    case warmup
    case working
    case backoff
    case amrap
    case drop
}

public enum RepTarget: Codable, Equatable, Sendable {
    case exact(Int)
    case range(min: Int, max: Int)
    case amrap(minimum: Int?)
    case duration(seconds: Int)
    case distance(meters: Double)
}

public enum WeightUnit: String, Codable, Sendable {
    case lb
    case kg
}

public enum LoadPrescription: Codable, Equatable, Sendable {
    case absoluteWeight(value: Double, unit: WeightUnit)
    case percent1RM(percent: Double, calculatedWeight: Double?)
    case bodyweight
    case bodyweightPlus(value: Double, unit: WeightUnit)
    case assisted(value: Double, unit: WeightUnit)
    case band(level: String)
    case machineSetting(String)
    case rpeOnly
    case unspecified
}

public struct PrescribedSet: Codable, Equatable, Sendable {
    public let id: UUID
    public var setIndex: Int
    public var kind: SetKind
    public var repTarget: RepTarget
    public var load: LoadPrescription
    public var targetRPE: Double?
    public var targetRIR: Int?
    public var restSeconds: Int?
    public var trainerNote: String?

    public init(id: UUID = UUID(), setIndex: Int, kind: SetKind = .working,
                repTarget: RepTarget, load: LoadPrescription = .unspecified,
                targetRPE: Double? = nil, targetRIR: Int? = nil,
                restSeconds: Int? = nil, trainerNote: String? = nil) {
        self.id = id
        self.setIndex = setIndex
        self.kind = kind
        self.repTarget = repTarget
        self.load = load
        self.targetRPE = targetRPE
        self.targetRIR = targetRIR
        self.restSeconds = restSeconds
        self.trainerNote = trainerNote
    }

    public func validate() throws {
        guard setIndex >= 0 else { throw UnifiedPlanValidationError.invalidSetIndex }
        if let targetRPE, !(0...10).contains(targetRPE) {
            throw UnifiedPlanValidationError.invalidRPE
        }
        if let targetRIR, !(0...10).contains(targetRIR) {
            throw UnifiedPlanValidationError.invalidRIR
        }
        if let restSeconds, restSeconds < 0 {
            throw UnifiedPlanValidationError.invalidRest
        }
    }
}

public struct CardioItem: Codable, Equatable, Sendable {
    public let id: UUID
    public var order: Int
    public var prescription: CardioPrescription
    public var instructions: String?

    public init(id: UUID = UUID(), order: Int, prescription: CardioPrescription,
                instructions: String? = nil) {
        self.id = id
        self.order = order
        self.prescription = prescription
        self.instructions = instructions
    }

    public func validate() throws {
        guard order >= 0 else { throw UnifiedPlanValidationError.invalidItemOrder }
    }
}

public enum CardioPrescription: Codable, Equatable, Sendable {
    case steadyState(SteadyState)
    case intervals(Intervals)
    case open(OpenActivity)
}

public struct SteadyState: Codable, Equatable, Sendable {
    public var activity: CardioActivity
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var intensity: CardioIntensity?
    public var inclinePercent: Double?
    public var cadenceRange: ClosedRange<Int>?
    public var warmupSeconds: Int?
    public var cooldownSeconds: Int?

    public init(activity: CardioActivity, durationSeconds: Int? = nil,
                distanceMeters: Double? = nil, intensity: CardioIntensity? = nil,
                inclinePercent: Double? = nil, cadenceRange: ClosedRange<Int>? = nil,
                warmupSeconds: Int? = nil, cooldownSeconds: Int? = nil) {
        self.activity = activity
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.intensity = intensity
        self.inclinePercent = inclinePercent
        self.cadenceRange = cadenceRange
        self.warmupSeconds = warmupSeconds
        self.cooldownSeconds = cooldownSeconds
    }
}

public struct Intervals: Codable, Equatable, Sendable {
    public var activity: CardioActivity
    public var warmupSeconds: Int?
    public var rounds: Int
    public var work: IntervalSegment
    public var recovery: IntervalSegment
    public var cooldownSeconds: Int?

    public init(activity: CardioActivity, warmupSeconds: Int? = nil, rounds: Int,
                work: IntervalSegment, recovery: IntervalSegment,
                cooldownSeconds: Int? = nil) {
        self.activity = activity
        self.warmupSeconds = warmupSeconds
        self.rounds = rounds
        self.work = work
        self.recovery = recovery
        self.cooldownSeconds = cooldownSeconds
    }
}

public struct IntervalSegment: Codable, Equatable, Sendable {
    public var durationSeconds: Int?
    public var distanceMeters: Double?
    public var intensity: CardioIntensity

    public init(durationSeconds: Int? = nil, distanceMeters: Double? = nil,
                intensity: CardioIntensity) {
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.intensity = intensity
    }
}

public struct OpenActivity: Codable, Equatable, Sendable {
    public var activity: CardioActivity
    public var goalText: String
    public var targetIntensity: CardioIntensity?

    public init(activity: CardioActivity, goalText: String,
                targetIntensity: CardioIntensity? = nil) {
        self.activity = activity
        self.goalText = goalText
        self.targetIntensity = targetIntensity
    }
}

public enum CardioActivity: Codable, Equatable, Sendable {
    case walk
    case run
    case bike
    case row
    case swim
    case elliptical
    case stairs
    case other(String)
}

public enum PaceUnit: String, Codable, Sendable {
    case minutesPerKilometer
    case minutesPerMile
}

public enum SpeedUnit: String, Codable, Sendable {
    case kilometersPerHour
    case milesPerHour
}

public enum TalkTestLevel: String, Codable, Sendable {
    case easyConversation
    case shortPhrases
    case cannotTalk
}

public enum CardioIntensity: Codable, Equatable, Sendable {
    case rpe(ClosedRange<Double>)
    case heartRateBPM(ClosedRange<Int>)
    case percentMaxHR(ClosedRange<Double>)
    case heartRateZone(Int)
    case pace(ClosedRange<Double>, PaceUnit)
    case speed(ClosedRange<Double>, SpeedUnit)
    case powerWatts(ClosedRange<Int>)
    case talkTest(TalkTestLevel)
}

public struct MobilityItem: Codable, Equatable, Sendable {
    public let id: UUID
    public var order: Int
    public var name: String
    public var rounds: Int?
    public var perRound: RepTarget
    public var eachSide: Bool
    public var instructions: String?

    public init(id: UUID = UUID(), order: Int, name: String,
                rounds: Int? = nil, perRound: RepTarget,
                eachSide: Bool = false, instructions: String? = nil) {
        self.id = id
        self.order = order
        self.name = name
        self.rounds = rounds
        self.perRound = perRound
        self.eachSide = eachSide
        self.instructions = instructions
    }

    public func validate() throws {
        guard order >= 0 else { throw UnifiedPlanValidationError.invalidItemOrder }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UnifiedPlanValidationError.emptyMobilityName
        }
    }
}

public struct InstructionItem: Codable, Equatable, Sendable {
    public let id: UUID
    public var order: Int
    public var text: String

    public init(id: UUID = UUID(), order: Int, text: String) {
        self.id = id
        self.order = order
        self.text = text
    }

    public func validate() throws {
        guard order >= 0 else { throw UnifiedPlanValidationError.invalidItemOrder }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UnifiedPlanValidationError.emptyInstructionText
        }
    }
}

// MARK: - Session participants and feedback

public struct PartnerRef: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var displayName: String
    public var linkedUserID: String?

    public init(id: UUID = UUID(), displayName: String,
                linkedUserID: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.linkedUserID = linkedUserID
    }
}

public enum PerformerRef: Codable, Equatable, Sendable {
    case owner
    case partner(PartnerRef)
}

public struct PainFlag: Codable, Equatable, Sendable {
    public var present: Bool
    public var location: String?
    public var severity: Int?
    public var note: String?

    public init(present: Bool, location: String? = nil, severity: Int? = nil,
                note: String? = nil) {
        self.present = present
        self.location = location
        self.severity = severity
        self.note = note
    }
}

public enum UnifiedPlanValidationError: Error, Equatable, Sendable {
    case emptyPlanTitle
    case planHasNoWeeks
    case horizonMismatch
    case invalidWeekIndex(Int)
    case weekMustHaveSevenDays
    case weekdaysMustBeMondayFirst
    case dayHasTooManySessions(Weekday)
    case emptySessionTitle
    case invalidItemOrder
    case duplicateItemID
    case invalidSetIndex
    case duplicateSetID
    case invalidRPE
    case invalidRIR
    case invalidRest
    case emptyMobilityName
    case emptyInstructionText
}
