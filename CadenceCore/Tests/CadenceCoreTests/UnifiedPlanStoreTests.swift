#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct UnifiedPlanStoreTests {
    @Test func validatedUnifiedPlanRoundTripsThroughSwiftDataEnvelope() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let plan = fixturePlan(title: "Week one", updatedAt: Date(timeIntervalSince1970: 100))

        let record = try UnifiedPlanStore.upsert(plan, originDevice: "iphone", in: context)
        let restored = try #require(try UnifiedPlanStore.fetch(id: plan.id, in: context))

        #expect(record.id == plan.id.raw)
        #expect(record.payloadVersion == UnifiedPlanStore.currentPayloadVersion)
        #expect(restored == plan)
        #expect(try UnifiedPlanStore.all(in: context) == [plan])
    }

    @Test func olderOrEqualPlanDoesNotOverwriteNewerPayload() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let newer = fixturePlan(title: "Newer", updatedAt: Date(timeIntervalSince1970: 200))
        _ = try UnifiedPlanStore.upsert(newer, originDevice: "ipad", in: context)

        let older = Plan(id: newer.id, title: "Older", weeks: newer.weeks,
                         createdAt: newer.createdAt,
                         updatedAt: Date(timeIntervalSince1970: 100))
        let retained = try UnifiedPlanStore.upsert(older, originDevice: "iphone", in: context)

        #expect(try retained.decodedPlan() == newer)
        #expect(try UnifiedPlanStore.fetch(id: newer.id, in: context) == newer)
    }

    @Test func contentEquivalentPlanDoesNotRewriteRevisionTimestamp() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let original = fixturePlan(title: "Stable", updatedAt: Date(timeIntervalSince1970: 200))
        let record = try UnifiedPlanStore.upsert(original, originDevice: "iphone", in: context)

        var regenerated = original
        regenerated.updatedAt = Date(timeIntervalSince1970: 900)
        let retained = try UnifiedPlanStore.upsert(regenerated, originDevice: "iphone", in: context)

        #expect(record === retained)
        #expect(retained.updatedAt == original.updatedAt)
        #expect(try UnifiedPlanStore.fetch(id: original.id, in: context) == original)
    }

    @Test func equalTimestampUsesStableOriginDeviceTieBreak() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let timestamp = Date(timeIntervalSince1970: 300)
        let base = fixturePlan(title: "Phone", updatedAt: timestamp)
        _ = try UnifiedPlanStore.upsert(base, originDevice: "iphone", in: context)

        let ipadPlan = Plan(id: base.id, title: "iPad", weeks: base.weeks,
                            createdAt: base.createdAt, updatedAt: timestamp)
        _ = try UnifiedPlanStore.upsert(ipadPlan, originDevice: "z-ipad", in: context)

        #expect(try UnifiedPlanStore.fetch(id: base.id, in: context)?.title == "iPad")
    }

    @Test func unsupportedOrCorruptPayloadFailsWithoutChangingLegacyRecords() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let plan = fixturePlan(title: "Valid", updatedAt: Date(timeIntervalSince1970: 400))
        let record = try UnifiedPlanStore.upsert(plan, originDevice: "iphone", in: context)

        record.payloadVersion = 99
        #expect(throws: UnifiedPlanStoreError.unsupportedPayloadVersion(99)) {
            try record.decodedPlan()
        }
        record.payloadVersion = UnifiedPlanStore.currentPayloadVersion
        record.planData = Data("not-json".utf8)
        #expect(throws: UnifiedPlanStoreError.invalidPayload) {
            try record.decodedPlan()
        }
    }

    private func fixturePlan(title: String, updatedAt: Date) -> Plan {
        let days = Weekday.mondayThroughSunday.map { PlanDay(weekday: $0) }
        return Plan(title: title, weeks: [PlanWeek(index: 0, days: days)],
                    createdAt: Date(timeIntervalSince1970: 1), updatedAt: updatedAt)
    }
}

private extension Weekday {
    static var mondayThroughSunday: [Weekday] {
        [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
    }
}
#endif
