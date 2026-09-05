import Foundation
import SwiftData

// MARK: - Normalized plan records

/// Normalized SwiftData rows for the unified value graph. The existing
/// `PersistedPlan` envelope remains the compatibility/read-recovery path; these
/// rows make the hierarchy addressable by stable IDs for CloudKit and future
/// client relationship queries without putting execution data in a second
/// domain model.
@Model
public final class PersistedPlanHeader {
    public var id: UUID = UUID()
    public var title: String = ""
    public var provenanceData: Data = Data()
    public var goalRaw: String = "hypertrophy"
    public var horizonData: Data = Data()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var authoredOnIdiomRaw: String?
    public var statusRaw: String = "draft"
    public var notes: String?
    public var rationaleData: Data?
    public var originDevice: String = ""

    public init(plan: Plan, originDevice: String = "") throws {
        self.id = plan.id.raw
        self.title = plan.title
        self.provenanceData = try NormalizedPlanStore.encode(plan.provenance)
        self.goalRaw = plan.goal.rawValue
        self.horizonData = try NormalizedPlanStore.encode(plan.horizon)
        self.createdAt = plan.createdAt
        self.updatedAt = plan.updatedAt
        self.authoredOnIdiomRaw = plan.authoredOnIdiom?.rawValue
        self.statusRaw = plan.status.rawValue
        self.notes = plan.notes
        self.rationaleData = try plan.rationale.map(NormalizedPlanStore.encode)
        self.originDevice = originDevice
    }
}

@Model
public final class PersistedPlanWeek {
    public var id: UUID = UUID()
    public var planID: UUID = UUID()
    public var index: Int = 0
    public var intendedProgressionRaw: String?
    public var isDeload: Bool = false

    public init(week: PlanWeek, planID: PlanID) {
        self.id = week.id
        self.planID = planID.raw
        self.index = week.index
        self.intendedProgressionRaw = week.intendedProgression?.rawValue
        self.isDeload = week.isDeload
    }
}

@Model
public final class PersistedPlanDay {
    public var id: UUID = UUID()
    public var weekID: UUID = UUID()
    public var weekdayRaw: Int = Weekday.monday.rawValue

    public init(day: PlanDay, weekID: UUID) {
        self.id = day.id
        self.weekID = weekID
        self.weekdayRaw = day.weekday.rawValue
    }
}

@Model
public final class PersistedPlanSession {
    public var id: UUID = UUID()
    public var dayID: UUID = UUID()
    public var title: String = ""
    public var goalRaw: String = "hypertrophy"
    public var estimatedDurationMinutes: Int?
    public var statusRaw: String = "planned"
    public var startedAt: Date?
    public var completedAt: Date?
    public var sessionRPE: Double?
    public var painData: Data?
    public var note: String?
    public var partnersData: Data = Data()

    public init(session: Session, dayID: UUID) throws {
        self.id = session.id
        self.dayID = dayID
        self.title = session.title
        self.goalRaw = session.goal.rawValue
        self.estimatedDurationMinutes = session.estimatedDurationMinutes
        self.statusRaw = session.status.rawValue
        self.startedAt = session.startedAt
        self.completedAt = session.completedAt
        self.sessionRPE = session.sessionRPE
        self.painData = try session.painFlag.map(NormalizedPlanStore.encode)
        self.note = session.note
        self.partnersData = try NormalizedPlanStore.encode(session.partners)
    }
}

@Model
public final class PersistedPlanItem {
    public var id: UUID = UUID()
    public var sessionID: UUID = UUID()
    public var kindRaw: String = "strength"
    public var order: Int = 0
    /// Encodes only the item-specific value, never its parent session or sets.
    public var payloadData: Data = Data()

    public init(item: WorkoutItem, sessionID: UUID) throws {
        self.id = item.id
        self.sessionID = sessionID
        self.order = item.order
        switch item {
        case let .strength(value):
            self.kindRaw = "strength"
            let base = StrengthItem(id: value.id, exerciseKey: value.exerciseKey,
                                    order: value.order, instructions: value.instructions,
                                    tempo: value.tempo,
                                    defaultRestSeconds: value.defaultRestSeconds,
                                    alternateExerciseKey: value.alternateExerciseKey,
                                    sets: [], schemeApplied: value.schemeApplied,
                                    supersetGroup: value.supersetGroup)
            self.payloadData = try NormalizedPlanStore.encode(base)
        case let .cardio(value):
            self.kindRaw = "cardio"
            self.payloadData = try NormalizedPlanStore.encode(value)
        case let .mobility(value):
            self.kindRaw = "mobility"
            self.payloadData = try NormalizedPlanStore.encode(value)
        case let .instruction(value):
            self.kindRaw = "instruction"
            self.payloadData = try NormalizedPlanStore.encode(value)
        }
    }
}

@Model
public final class PersistedPlanSet {
    public var id: UUID = UUID()
    public var itemID: UUID = UUID()
    public var setIndex: Int = 0
    public var payloadData: Data = Data()

    public init(set: PrescribedSet, itemID: UUID) throws {
        self.id = set.id
        self.itemID = itemID
        self.setIndex = set.setIndex
        self.payloadData = try NormalizedPlanStore.encode(set)
    }
}

// MARK: - Client relationship persistence

public enum ClientRelationshipStatus: String, Codable, Equatable, Sendable {
    case active
    case paused
    case archived
    case disconnected
}

public struct ClientRelationship: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var displayName: String
    public var notes: String?
    public var goal: TrainingGoal?
    public var status: ClientRelationshipStatus
    public var shareZoneID: UUID?
    public var shareURL: URL?
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID = UUID(), displayName: String, notes: String? = nil,
                goal: TrainingGoal? = nil,
                status: ClientRelationshipStatus = .active,
                shareZoneID: UUID? = nil, shareURL: URL? = nil,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.notes = notes
        self.goal = goal
        self.status = status
        self.shareZoneID = shareZoneID
        self.shareURL = shareURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class PersistedClientRelationship {
    public var id: UUID = UUID()
    public var displayName: String = ""
    public var notes: String?
    public var goalRaw: String?
    public var statusRaw: String = ClientRelationshipStatus.active.rawValue
    public var shareZoneID: UUID?
    public var shareURLString: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(relationship: ClientRelationship) {
        self.id = relationship.id
        self.displayName = relationship.displayName
        self.notes = relationship.notes
        self.goalRaw = relationship.goal?.rawValue
        self.statusRaw = relationship.status.rawValue
        self.shareZoneID = relationship.shareZoneID
        self.shareURLString = relationship.shareURL?.absoluteString
        self.createdAt = relationship.createdAt
        self.updatedAt = relationship.updatedAt
    }

    public func value() throws -> ClientRelationship {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let status = ClientRelationshipStatus(rawValue: statusRaw) else {
            throw NormalizedPlanStoreError.invalidRelationship
        }
        return ClientRelationship(
            id: id, displayName: displayName, notes: notes,
            goal: goalRaw.flatMap(TrainingGoal.init(rawValue:)), status: status,
            shareZoneID: shareZoneID,
            shareURL: shareURLString.flatMap(URL.init(string:)),
            createdAt: createdAt, updatedAt: updatedAt)
    }
}

public enum NormalizedPlanStoreError: Error, Equatable, Sendable {
    case invalidPlan
    case invalidRelationship
    case missingParent
    case unsupportedItemKind(String)
}

public enum NormalizedPlanStore {
    public static let currentSchemaVersion = 1

    @discardableResult
    public static func upsert(_ plan: Plan, originDevice: String = "",
                              in context: ModelContext) throws -> PersistedPlanHeader {
        try plan.validate()
        let id = plan.id.raw
        let existing = try context.fetch(FetchDescriptor<PersistedPlanHeader>(
            predicate: #Predicate { $0.id == id })).first
        if let existing {
            let newer = plan.updatedAt > existing.updatedAt ||
                (plan.updatedAt == existing.updatedAt && originDevice > existing.originDevice)
            guard newer else { return existing }
            try deleteChildren(of: id, in: context)
            try populate(plan, originDevice: originDevice, header: existing, in: context)
            try context.save()
            return existing
        }

        let header = try PersistedPlanHeader(plan: plan, originDevice: originDevice)
        context.insert(header)
        try populate(plan, originDevice: originDevice, header: header, in: context)
        try context.save()
        return header
    }

    public static func fetch(id: PlanID, in context: ModelContext) throws -> Plan? {
        guard let header = try context.fetch(FetchDescriptor<PersistedPlanHeader>(
            predicate: #Predicate { $0.id == id.raw })).first else { return nil }
        return try decode(header: header, in: context)
    }

    public static func upsert(_ relationship: ClientRelationship,
                              in context: ModelContext) throws -> PersistedClientRelationship {
        guard !relationship.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NormalizedPlanStoreError.invalidRelationship
        }
        let existing = try context.fetch(FetchDescriptor<PersistedClientRelationship>(
            predicate: #Predicate { $0.id == relationship.id })).first
        if let existing {
            guard relationship.updatedAt >= existing.updatedAt else { return existing }
            existing.displayName = relationship.displayName
            existing.notes = relationship.notes
            existing.goalRaw = relationship.goal?.rawValue
            existing.statusRaw = relationship.status.rawValue
            existing.shareZoneID = relationship.shareZoneID
            existing.shareURLString = relationship.shareURL?.absoluteString
            existing.createdAt = relationship.createdAt
            existing.updatedAt = relationship.updatedAt
            try context.save()
            return existing
        }
        let record = PersistedClientRelationship(relationship: relationship)
        context.insert(record)
        try context.save()
        return record
    }

    private static func populate(_ plan: Plan, originDevice: String,
                                header: PersistedPlanHeader,
                                in context: ModelContext) throws {
        header.title = plan.title
        header.provenanceData = try encode(plan.provenance)
        header.goalRaw = plan.goal.rawValue
        header.horizonData = try encode(plan.horizon)
        header.createdAt = plan.createdAt
        header.updatedAt = plan.updatedAt
        header.authoredOnIdiomRaw = plan.authoredOnIdiom?.rawValue
        header.statusRaw = plan.status.rawValue
        header.notes = plan.notes
        header.rationaleData = try plan.rationale.map(encode)
        header.originDevice = originDevice

        for week in plan.weeks {
            context.insert(PersistedPlanWeek(week: week, planID: plan.id))
            for day in week.days {
                context.insert(PersistedPlanDay(day: day, weekID: week.id))
                for session in day.sessions {
                    context.insert(try PersistedPlanSession(session: session, dayID: day.id))
                    for item in session.items {
                        context.insert(try PersistedPlanItem(item: item, sessionID: session.id))
                        if case let .strength(strength) = item {
                            for set in strength.sets {
                                context.insert(try PersistedPlanSet(set: set, itemID: strength.id))
                            }
                        }
                    }
                }
            }
        }
    }

    private static func decode(header: PersistedPlanHeader,
                               in context: ModelContext) throws -> Plan {
        let planID = header.id
        let weeks = try context.fetch(FetchDescriptor<PersistedPlanWeek>(
            predicate: #Predicate { $0.planID == planID },
            sortBy: [SortDescriptor(\PersistedPlanWeek.index)]))
        guard !weeks.isEmpty else {
            throw NormalizedPlanStoreError.invalidPlan
        }
        let daysByWeek = try context.fetch(FetchDescriptor<PersistedPlanDay>(
            sortBy: [SortDescriptor(\PersistedPlanDay.weekdayRaw)]))
        let sessions = try context.fetch(FetchDescriptor<PersistedPlanSession>())
        let items = try context.fetch(FetchDescriptor<PersistedPlanItem>())
        let sets = try context.fetch(FetchDescriptor<PersistedPlanSet>())

        let decodedWeeks = try weeks.map { week in
            let weekDays = daysByWeek.filter { $0.weekID == week.id }.sorted {
                mondayFirstRank($0.weekdayRaw) < mondayFirstRank($1.weekdayRaw)
            }
            let decodedDays = try weekDays.map { day in
                guard let weekday = Weekday(rawValue: day.weekdayRaw) else {
                    throw NormalizedPlanStoreError.invalidPlan
                }
                let decodedSessions = try sessions.filter { $0.dayID == day.id }.map { session in
                    let decodedItems = try items.filter { $0.sessionID == session.id }.sorted {
                        $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order
                    }.map { item in
                        try decodeItem(item, sets: sets.filter { $0.itemID == item.id })
                    }
                    guard let goal = TrainingGoal(rawValue: session.goalRaw),
                          let status = SessionStatus(rawValue: session.statusRaw) else {
                        throw NormalizedPlanStoreError.invalidPlan
                    }
                    return Session(id: session.id, title: session.title, goal: goal,
                                   items: decodedItems,
                                   estimatedDurationMinutes: session.estimatedDurationMinutes,
                                   status: status, startedAt: session.startedAt,
                                   completedAt: session.completedAt, sessionRPE: session.sessionRPE,
                                   painFlag: try session.painData.map { try decode($0) },
                                   note: session.note,
                                   partners: try decode(session.partnersData))
                }
                return PlanDay(id: day.id, weekday: weekday, sessions: decodedSessions)
            }
            let progression: ProgressionIntent?
            if let raw = week.intendedProgressionRaw {
                guard let decoded = ProgressionIntent(rawValue: raw) else {
                    throw NormalizedPlanStoreError.invalidPlan
                }
                progression = decoded
            } else {
                progression = nil
            }
            return PlanWeek(id: week.id, index: week.index, days: decodedDays,
                            intendedProgression: progression, isDeload: week.isDeload)
        }
        guard let goal = TrainingGoal(rawValue: header.goalRaw),
              let horizon = try? decode(header.horizonData) as PlanHorizon,
              let provenance = try? decode(header.provenanceData) as PlanProvenance,
              let status = PlanStatus(rawValue: header.statusRaw) else {
            throw NormalizedPlanStoreError.invalidPlan
        }
        return Plan(id: PlanID(raw: header.id), title: header.title,
                    provenance: provenance, goal: goal, horizon: horizon,
                    weeks: decodedWeeks, createdAt: header.createdAt,
                    updatedAt: header.updatedAt,
                    authoredOnIdiom: header.authoredOnIdiomRaw.flatMap(AuthoringIdiom.init(rawValue:)),
                    status: status, notes: header.notes,
                    rationale: try header.rationaleData.map { try decode($0) })
    }

    private static func decodeItem(_ item: PersistedPlanItem,
                                   sets: [PersistedPlanSet]) throws -> WorkoutItem {
        switch item.kindRaw {
        case "strength":
            var value = try decode(item.payloadData) as StrengthItem
            value.sets = try sets.sorted {
                $0.setIndex == $1.setIndex ? $0.id.uuidString < $1.id.uuidString : $0.setIndex < $1.setIndex
            }.map { try decode($0.payloadData) as PrescribedSet }
            return .strength(value)
        case "cardio": return .cardio(try decode(item.payloadData) as CardioItem)
        case "mobility": return .mobility(try decode(item.payloadData) as MobilityItem)
        case "instruction": return .instruction(try decode(item.payloadData) as InstructionItem)
        default: throw NormalizedPlanStoreError.unsupportedItemKind(item.kindRaw)
        }
    }

    private static func deleteChildren(of planID: UUID, in context: ModelContext) throws {
        let weeks = try context.fetch(FetchDescriptor<PersistedPlanWeek>(predicate: #Predicate { $0.planID == planID }))
        let weekIDs = Set(weeks.map(\PersistedPlanWeek.id))
        let days = try context.fetch(FetchDescriptor<PersistedPlanDay>()) .filter { weekIDs.contains($0.weekID) }
        let dayIDs = Set(days.map(\PersistedPlanDay.id))
        let sessions = try context.fetch(FetchDescriptor<PersistedPlanSession>()) .filter { dayIDs.contains($0.dayID) }
        let sessionIDs = Set(sessions.map(\PersistedPlanSession.id))
        let items = try context.fetch(FetchDescriptor<PersistedPlanItem>()) .filter { sessionIDs.contains($0.sessionID) }
        let itemIDs = Set(items.map(\PersistedPlanItem.id))
        for set in try context.fetch(FetchDescriptor<PersistedPlanSet>()) where itemIDs.contains(set.itemID) { context.delete(set) }
        for item in items { context.delete(item) }
        for session in sessions { context.delete(session) }
        for day in days { context.delete(day) }
        for week in weeks { context.delete(week) }
    }

    private static func mondayFirstRank(_ rawValue: Int) -> Int {
        switch rawValue {
        case Weekday.monday.rawValue: return 0
        case Weekday.tuesday.rawValue: return 1
        case Weekday.wednesday.rawValue: return 2
        case Weekday.thursday.rawValue: return 3
        case Weekday.friday.rawValue: return 4
        case Weekday.saturday.rawValue: return 5
        case Weekday.sunday.rawValue: return 6
        default: return Int.max
        }
    }

    fileprivate static func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder().encode(value)
    }

    fileprivate static func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}
