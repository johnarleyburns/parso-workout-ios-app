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
    /// Native cycles such as an eight-day rotation. DB++ keeps these cycles
    /// native; the app may derive a seven-day view for presentation only.
    case nativeCycle(days: Int)
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

/// How strongly the knowledge base supports an engine decision. This is kept in
/// the unified plan model so generated plans can carry their confidence across
/// persistence, Watch projection, and the eventual rationale surface.
public enum EvidenceConfidence: String, Codable, Sendable, Equatable, Comparable {
    case strong
    case moderate
    case limited
    case judgmentCall

    private var rank: Int {
        switch self {
        case .judgmentCall: return 0
        case .limited: return 1
        case .moderate: return 2
        case .strong: return 3
        }
    }

    public static func < (lhs: EvidenceConfidence, rhs: EvidenceConfidence) -> Bool {
        lhs.rank < rhs.rank
    }
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

    /// A persisted rationale is safe to render only when every decision has at
    /// least one citation that resolves through the bundled registry. Hand-authored
    /// plans may omit rationale entirely; engine-authored plans use this as the
    /// EvidenceGate contract at the unified-plan boundary.
    public var isEvidenceGated: Bool {
        !decisions.isEmpty && decisions.allSatisfy { decision in
            !decision.citationIDs.isEmpty
                && decision.citationIDs.allSatisfy { CitationRegistry.citation(forId: $0) != nil }
        }
    }
}

/// The small set of engine identifiers that must travel with a generated or
/// adapted plan. The citation registry stays bundled read-only data; these are
/// provenance fields, not a second evidence store.
public struct PlanEngineProvenance: Codable, Equatable, Sendable {
    public var engine: String
    public var engineVersion: String?
    public var planID: String?
    public var revisionID: String?
    public var policyID: String?
    public var schemaVersion: String?

    public init(engine: String = "free-exercise-db-plusplus",
                engineVersion: String? = nil, planID: String? = nil,
                revisionID: String? = nil, policyID: String? = nil,
                schemaVersion: String? = nil) {
        self.engine = engine
        self.engineVersion = engineVersion
        self.planID = planID
        self.revisionID = revisionID
        self.policyID = policyID
        self.schemaVersion = schemaVersion
    }
}

/// App-owned phase metadata. DB++ has the same concept in its canonical PLAN;
/// this type keeps periodization visible to the app without coupling SwiftData
/// or UI concerns to the package's JSON representation.
public struct PlanPhase: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var durationCycles: Int
    public var cycleLengthDays: Int?
    public var progression: ProgressionIntent?
    public var isDeload: Bool

    public init(id: String, title: String, durationCycles: Int,
                cycleLengthDays: Int? = nil, progression: ProgressionIntent? = nil,
                isDeload: Bool = false) {
        self.id = id
        self.title = title
        self.durationCycles = durationCycles
        self.cycleLengthDays = cycleLengthDays
        self.progression = progression
        self.isDeload = isDeload
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              durationCycles > 0,
              cycleLengthDays == nil || cycleLengthDays! > 0 else {
            throw UnifiedPlanValidationError.invalidPlanMetadata
        }
    }
}

public struct RationaleDecision: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var claim: String
    public var basis: String
    public var citationIDs: [String]
    public var confidence: EvidenceConfidence?

    public init(id: UUID = UUID(), claim: String, basis: String,
                citationIDs: [String] = [], confidence: EvidenceConfidence? = nil) {
        self.id = id
        self.claim = claim
        self.basis = basis
        self.citationIDs = citationIDs
        self.confidence = confidence
    }
}

// MARK: - Unified plan hierarchy

public struct Plan: Codable, Equatable, Sendable, Identifiable {
    public let id: PlanID
    /// Stable application revision. A revision changes when a proposal is
    /// accepted; executed revisions remain immutable for adherence/reconciliation.
    public var revisionID: String
    public var title: String
    public var provenance: PlanProvenance
    /// Reuses the shipped app goal taxonomy for this first value-model slice.
    /// The existing type remains the compatibility bridge for coach features.
    public var goal: TrainingGoal
    public var horizon: PlanHorizon
    public var weeks: [PlanWeek]
    public var createdAt: Date
    public var updatedAt: Date
    /// Native cycle length. A single-week plan defaults to seven days; future
    /// rotations must not be forced into a seven-day storage shape.
    public var cycleLengthDays: Int
    public var phases: [PlanPhase]?
    public var authoredOnIdiom: AuthoringIdiom?
    public var status: PlanStatus
    public var notes: String?
    public var rationale: EngineRationale?
    public var engineProvenance: PlanEngineProvenance?
    public var assistance: Set<PlanAssistance>?
    /// Scheme definitions are app-owned authoring metadata. DB++ receives
    /// materialized planned sets, never this registry.
    public var setSchemes: [SetScheme]?

    public init(id: PlanID = PlanID(), revisionID: String = "r1", title: String,
                provenance: PlanProvenance = .selfAuthored,
                goal: TrainingGoal = .hypertrophy,
                horizon: PlanHorizon = .singleWeek,
                weeks: [PlanWeek], createdAt: Date = Date(),
                updatedAt: Date = Date(), cycleLengthDays: Int = 7,
                phases: [PlanPhase]? = nil, authoredOnIdiom: AuthoringIdiom? = nil,
                status: PlanStatus = .draft, notes: String? = nil,
                rationale: EngineRationale? = nil,
                engineProvenance: PlanEngineProvenance? = nil,
                assistance: Set<PlanAssistance>? = nil,
                setSchemes: [SetScheme]? = nil) {
        self.id = id
        self.revisionID = revisionID
        self.title = title
        self.provenance = provenance
        self.goal = goal
        self.horizon = horizon
        self.weeks = weeks
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.cycleLengthDays = cycleLengthDays
        self.phases = phases
        self.authoredOnIdiom = authoredOnIdiom
        self.status = status
        self.notes = notes
        self.rationale = rationale
        self.engineProvenance = engineProvenance
        self.assistance = assistance
        self.setSchemes = setSchemes
    }

    /// Source-compatible constructor retained for clients compiled against the
    /// original unified-plan shape. New callers can use the expanded overload
    /// above when they need revision, cycle, phase, or engine metadata.
    public init(id: PlanID = PlanID(), title: String,
                provenance: PlanProvenance = .selfAuthored,
                goal: TrainingGoal = .hypertrophy,
                horizon: PlanHorizon = .singleWeek,
                weeks: [PlanWeek], createdAt: Date = Date(),
                updatedAt: Date = Date(), authoredOnIdiom: AuthoringIdiom? = nil,
                status: PlanStatus = .draft, notes: String? = nil,
                rationale: EngineRationale? = nil) {
        self.init(id: id, revisionID: "r1", title: title, provenance: provenance,
                  goal: goal, horizon: horizon, weeks: weeks, createdAt: createdAt,
                  updatedAt: updatedAt, cycleLengthDays: 7, phases: nil,
                  authoredOnIdiom: authoredOnIdiom, status: status, notes: notes,
                  rationale: rationale, engineProvenance: nil)
    }

    private enum CodingKeys: String, CodingKey {
        case id, revisionID, title, provenance, goal, horizon, weeks, createdAt,
             updatedAt, cycleLengthDays, phases, authoredOnIdiom, status, notes,
             rationale, engineProvenance, assistance, setSchemes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PlanID.self, forKey: .id)
        revisionID = try container.decodeIfPresent(String.self, forKey: .revisionID) ?? "r1"
        title = try container.decode(String.self, forKey: .title)
        provenance = try container.decode(PlanProvenance.self, forKey: .provenance)
        goal = try container.decode(TrainingGoal.self, forKey: .goal)
        horizon = try container.decode(PlanHorizon.self, forKey: .horizon)
        weeks = try container.decode([PlanWeek].self, forKey: .weeks)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        cycleLengthDays = try container.decodeIfPresent(Int.self, forKey: .cycleLengthDays) ?? 7
        phases = try container.decodeIfPresent([PlanPhase].self, forKey: .phases)
        authoredOnIdiom = try container.decodeIfPresent(AuthoringIdiom.self, forKey: .authoredOnIdiom)
        status = try container.decode(PlanStatus.self, forKey: .status)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        rationale = try container.decodeIfPresent(EngineRationale.self, forKey: .rationale)
        engineProvenance = try container.decodeIfPresent(PlanEngineProvenance.self, forKey: .engineProvenance)
        assistance = try container.decodeIfPresent(Set<PlanAssistance>.self, forKey: .assistance)
        setSchemes = try container.decodeIfPresent([SetScheme].self, forKey: .setSchemes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(revisionID, forKey: .revisionID)
        try container.encode(title, forKey: .title)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(goal, forKey: .goal)
        try container.encode(horizon, forKey: .horizon)
        try container.encode(weeks, forKey: .weeks)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(cycleLengthDays, forKey: .cycleLengthDays)
        try container.encodeIfPresent(phases, forKey: .phases)
        try container.encodeIfPresent(authoredOnIdiom, forKey: .authoredOnIdiom)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(rationale, forKey: .rationale)
        try container.encodeIfPresent(engineProvenance, forKey: .engineProvenance)
        try container.encodeIfPresent(assistance, forKey: .assistance)
        try container.encodeIfPresent(setSchemes, forKey: .setSchemes)
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
        case let .nativeCycle(days) where days < 1 || cycleLengthDays != days:
            throw UnifiedPlanValidationError.horizonMismatch
        default:
            break
        }
        guard !revisionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              cycleLengthDays > 0 else {
            throw UnifiedPlanValidationError.invalidPlanMetadata
        }
        for phase in phases ?? [] {
            try phase.validate()
        }
        for scheme in setSchemes ?? [] {
            try scheme.validate()
        }
        guard Set((setSchemes ?? []).map(\.id)).count == (setSchemes ?? []).count else {
            throw UnifiedPlanValidationError.duplicateSetSchemeID
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
    /// DB++/ACTUAL laterality is optional in the app model because existing
    /// sessions predate it. Keep it as a string at this boundary so the app can
    /// preserve future package values without a destructive enum migration.
    public var laterality: String?
    public var progression: ProgressionIntent?
    public var performerOverrides: [PerformerPrescriptionOverride]?

    public init(id: UUID = UUID(), exerciseKey: ExerciseKey, order: Int,
                instructions: String? = nil, tempo: String? = nil,
                defaultRestSeconds: Int? = nil,
                alternateExerciseKey: ExerciseKey? = nil,
                sets: [PrescribedSet] = [], schemeApplied: SetSchemeID? = nil,
                supersetGroup: SupersetGroupID? = nil, laterality: String? = nil,
                progression: ProgressionIntent? = nil,
                performerOverrides: [PerformerPrescriptionOverride]? = nil) {
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
        self.laterality = laterality
        self.progression = progression
        self.performerOverrides = performerOverrides
    }

    /// Source-compatible constructor retained for the pre-Phase-2 model.
    public init(id: UUID = UUID(), exerciseKey: ExerciseKey, order: Int,
                instructions: String? = nil, tempo: String? = nil,
                defaultRestSeconds: Int? = nil,
                alternateExerciseKey: ExerciseKey? = nil,
                sets: [PrescribedSet] = [], schemeApplied: SetSchemeID? = nil,
                supersetGroup: SupersetGroupID? = nil) {
        self.init(id: id, exerciseKey: exerciseKey, order: order,
                  instructions: instructions, tempo: tempo,
                  defaultRestSeconds: defaultRestSeconds,
                  alternateExerciseKey: alternateExerciseKey, sets: sets,
                  schemeApplied: schemeApplied, supersetGroup: supersetGroup,
                  laterality: nil, progression: nil, performerOverrides: nil)
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

public enum SetKind: String, Codable, Sendable, Hashable {
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
    public var targetRPERange: ClosedRange<Double>?
    public var targetRIRRange: ClosedRange<Int>?

    public init(id: UUID = UUID(), setIndex: Int, kind: SetKind = .working,
                repTarget: RepTarget, load: LoadPrescription = .unspecified,
                targetRPE: Double? = nil, targetRIR: Int? = nil,
                restSeconds: Int? = nil, trainerNote: String? = nil,
                targetRPERange: ClosedRange<Double>? = nil,
                targetRIRRange: ClosedRange<Int>? = nil) {
        self.id = id
        self.setIndex = setIndex
        self.kind = kind
        self.repTarget = repTarget
        self.load = load
        self.targetRPE = targetRPE
        self.targetRIR = targetRIR
        self.restSeconds = restSeconds
        self.trainerNote = trainerNote
        self.targetRPERange = targetRPERange
        self.targetRIRRange = targetRIRRange
    }

    /// Source-compatible constructor retained for the pre-Phase-2 model.
    public init(id: UUID = UUID(), setIndex: Int, kind: SetKind = .working,
                repTarget: RepTarget, load: LoadPrescription = .unspecified,
                targetRPE: Double? = nil, targetRIR: Int? = nil,
                restSeconds: Int? = nil, trainerNote: String? = nil) {
        self.init(id: id, setIndex: setIndex, kind: kind, repTarget: repTarget,
                  load: load, targetRPE: targetRPE, targetRIR: targetRIR,
                  restSeconds: restSeconds, trainerNote: trainerNote,
                  targetRPERange: nil, targetRIRRange: nil)
    }

    public func validate() throws {
        guard setIndex >= 0 else { throw UnifiedPlanValidationError.invalidSetIndex }
        if let targetRPE, !(0...10).contains(targetRPE) {
            throw UnifiedPlanValidationError.invalidRPE
        }
        if let targetRIR, !(0...10).contains(targetRIR) {
            throw UnifiedPlanValidationError.invalidRIR
        }
        if let targetRPERange, targetRPERange.lowerBound < 0 || targetRPERange.upperBound > 10 || targetRPERange.lowerBound > targetRPERange.upperBound {
            throw UnifiedPlanValidationError.invalidRPE
        }
        if let targetRIRRange, targetRIRRange.lowerBound < 0 || targetRIRRange.upperBound > 10 || targetRIRRange.lowerBound > targetRIRRange.upperBound {
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

/// Per-performer prescription overrides stay in the app model. DB++ PLAN is a
/// single-subject canonical artifact; partner rotation and distinct partner loads
/// are host-app execution semantics.
public struct PerformerPrescriptionOverride: Codable, Equatable, Sendable {
    public var performer: PerformerRef
    public var setsByItemID: [String: [PrescribedSet]]

    public init(performer: PerformerRef, setsByItemID: [String: [PrescribedSet]] = [:]) {
        self.performer = performer
        self.setsByItemID = setsByItemID
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
    case invalidPlanMetadata
    case invalidTemplate
    case invalidScheme
    case invalidPlanningRequest
    case invalidReadinessSignal
    case invalidRepeatRequest
    case duplicateSetSchemeID
    case invalidPerformanceProfile
    case invalidVolumeSnapshot
}
