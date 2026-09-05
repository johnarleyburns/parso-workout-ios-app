import Foundation
import SwiftData

/// Additive SwiftData envelope for the unified value model. The domain model
/// remains a Codable value graph; this record is deliberately boring so it can
/// be mirrored by SwiftData/CloudKit without making every associated-value enum
/// a separate persistence entity before the planner migration is complete.
@Model
public final class PersistedPlan {
    public var id: UUID = UUID()
    public var payloadVersion: Int = UnifiedPlanStore.currentPayloadVersion
    public var planData: Data = Data()
    public var updatedAt: Date = Date()
    public var originDevice: String = ""
    public var deletedAt: Date?

    public init(plan: Plan, originDevice: String = "") throws {
        self.id = plan.id.raw
        self.payloadVersion = UnifiedPlanStore.currentPayloadVersion
        self.planData = try UnifiedPlanStore.encode(plan)
        self.updatedAt = plan.updatedAt
        self.originDevice = originDevice
    }

    public func decodedPlan() throws -> Plan {
        try UnifiedPlanStore.decode(planData, version: payloadVersion)
    }
}

public enum UnifiedPlanStoreError: Error, Equatable, Sendable {
    case unsupportedPayloadVersion(Int)
    case invalidPayload
}

public enum UnifiedPlanStore {
    public static let currentPayloadVersion = 1

    /// Inserts a new plan or applies the newer value by `updatedAt`. Equal-date
    /// writes use the origin-device ID as a deterministic tie-breaker, matching
    /// the value-level sharing contract.
    @discardableResult
    public static func upsert(_ plan: Plan, originDevice: String = "",
                              in context: ModelContext) throws -> PersistedPlan {
        try plan.validate()
        let id = plan.id.raw
        let existing = try context.fetch(FetchDescriptor<PersistedPlan>(
            predicate: #Predicate { $0.id == id }
        )).first

        if let existing {
            let shouldReplace = plan.updatedAt > existing.updatedAt ||
                (plan.updatedAt == existing.updatedAt && originDevice > existing.originDevice)
            guard shouldReplace else { return existing }
            existing.payloadVersion = currentPayloadVersion
            existing.planData = try encode(plan)
            existing.updatedAt = plan.updatedAt
            existing.originDevice = originDevice
            try context.save()
            return existing
        }

        let record = try PersistedPlan(plan: plan, originDevice: originDevice)
        context.insert(record)
        try context.save()
        return record
    }

    public static func fetch(id: PlanID, in context: ModelContext) throws -> Plan? {
        let rawID = id.raw
        guard let record = try context.fetch(FetchDescriptor<PersistedPlan>(
            predicate: #Predicate { $0.id == rawID }
        )).first else { return nil }
        return try record.decodedPlan()
    }

    public static func all(in context: ModelContext) throws -> [Plan] {
        try context.fetch(FetchDescriptor<PersistedPlan>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\PersistedPlan.updatedAt, order: .reverse)]
        )).map { try $0.decodedPlan() }
    }

    public static func encode(_ plan: Plan) throws -> Data {
        try JSONEncoder().encode(plan)
    }

    public static func decode(_ data: Data, version: Int) throws -> Plan {
        guard version == currentPayloadVersion else {
            throw UnifiedPlanStoreError.unsupportedPayloadVersion(version)
        }
        guard let plan = try? JSONDecoder().decode(Plan.self, from: data) else {
            throw UnifiedPlanStoreError.invalidPayload
        }
        return plan
    }
}
