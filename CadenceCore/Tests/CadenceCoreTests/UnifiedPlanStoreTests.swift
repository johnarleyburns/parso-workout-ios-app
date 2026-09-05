import XCTest
import SwiftData
@testable import CadenceCore

final class UnifiedPlanStoreTests: XCTestCase {
    func testValidatedUnifiedPlanRoundTripsThroughSwiftDataEnvelope() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let plan = fixturePlan(title: "Week one", updatedAt: Date(timeIntervalSince1970: 100))

        let record = try UnifiedPlanStore.upsert(plan, originDevice: "iphone", in: context)
        let restored = try XCTUnwrap(try UnifiedPlanStore.fetch(id: plan.id, in: context))

        XCTAssertEqual(record.id, plan.id.raw)
        XCTAssertEqual(record.payloadVersion, UnifiedPlanStore.currentPayloadVersion)
        XCTAssertEqual(restored, plan)
        XCTAssertEqual(try UnifiedPlanStore.all(in: context), [plan])
    }

    func testOlderOrEqualPlanDoesNotOverwriteNewerPayload() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let newer = fixturePlan(title: "Newer", updatedAt: Date(timeIntervalSince1970: 200))
        _ = try UnifiedPlanStore.upsert(newer, originDevice: "ipad", in: context)

        let older = Plan(id: newer.id, title: "Older", weeks: newer.weeks,
                         createdAt: newer.createdAt,
                         updatedAt: Date(timeIntervalSince1970: 100))
        let retained = try UnifiedPlanStore.upsert(older, originDevice: "iphone", in: context)

        XCTAssertEqual(try retained.decodedPlan(), newer)
        XCTAssertEqual(try UnifiedPlanStore.fetch(id: newer.id, in: context), newer)
    }

    func testEqualTimestampUsesStableOriginDeviceTieBreak() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let timestamp = Date(timeIntervalSince1970: 300)
        let base = fixturePlan(title: "Phone", updatedAt: timestamp)
        _ = try UnifiedPlanStore.upsert(base, originDevice: "iphone", in: context)

        let ipadPlan = Plan(id: base.id, title: "iPad", weeks: base.weeks,
                            createdAt: base.createdAt, updatedAt: timestamp)
        _ = try UnifiedPlanStore.upsert(ipadPlan, originDevice: "z-ipad", in: context)

        XCTAssertEqual(try UnifiedPlanStore.fetch(id: base.id, in: context)?.title, "iPad")
    }

    func testUnsupportedOrCorruptPayloadFailsWithoutChangingLegacyRecords() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let plan = fixturePlan(title: "Valid", updatedAt: Date(timeIntervalSince1970: 400))
        let record = try UnifiedPlanStore.upsert(plan, originDevice: "iphone", in: context)

        record.payloadVersion = 99
        XCTAssertThrowsError(try record.decodedPlan()) { error in
            XCTAssertEqual(error as? UnifiedPlanStoreError, .unsupportedPayloadVersion(99))
        }
        record.payloadVersion = UnifiedPlanStore.currentPayloadVersion
        record.planData = Data("not-json".utf8)
        XCTAssertThrowsError(try record.decodedPlan()) { error in
            XCTAssertEqual(error as? UnifiedPlanStoreError, .invalidPayload)
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
