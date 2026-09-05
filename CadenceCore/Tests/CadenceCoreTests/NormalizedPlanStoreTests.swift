import XCTest
import SwiftData
@testable import CadenceCore

final class NormalizedPlanStoreTests: XCTestCase {
    func testAllPlanItemFamiliesRoundTripThroughNormalizedRows() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let planID = PlanID(raw: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let strengthID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        let setID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
        let session = Session(
            id: sessionID, title: "Full session", goal: .strength,
            items: [
                .strength(StrengthItem(
                    id: strengthID, exerciseKey: ExerciseKey(raw: "bench_press"), order: 0,
                    instructions: "Brace", tempo: "3-1-1-0", defaultRestSeconds: 120,
                    sets: [PrescribedSet(
                        id: setID, setIndex: 0, repTarget: .exact(5),
                        load: .percent1RM(percent: 0.8, calculatedWeight: 80), targetRIR: 2)])),
                .cardio(CardioItem(
                    order: 1, prescription: .open(OpenActivity(activity: .walk, goalText: "Easy")))),
                .mobility(MobilityItem(order: 2, name: "Hip opener", perRound: .duration(seconds: 30))),
                .instruction(InstructionItem(order: 3, text: "Stop if pain changes."))
            ], sessionRPE: 8, painFlag: PainFlag(present: false),
            partners: [PartnerRef(displayName: "Sam")])
        let monday = PlanDay(weekday: .monday, sessions: [session])
        let days = Weekday.mondayThroughSunday.map { $0 == .monday ? monday : PlanDay(weekday: $0) }
        let plan = Plan(
            id: planID, title: "Normalized week", provenance: .selfAuthored,
            goal: .strength, weeks: [PlanWeek(index: 0, days: days)],
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2),
            authoredOnIdiom: .regular, status: .active,
            rationale: EngineRationale(summary: "Test rationale"))

        let header = try NormalizedPlanStore.upsert(plan, originDevice: "iphone", in: context)
        let restored = try XCTUnwrap(try NormalizedPlanStore.fetch(id: planID, in: context))

        XCTAssertEqual(header.id, planID.raw)
        XCTAssertEqual(restored, plan)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersistedPlanWeek>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersistedPlanDay>()).count, 7)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersistedPlanSession>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersistedPlanItem>()).count, 4)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersistedPlanSet>()).count, 1)
    }

    func testNewerUpsertReplacesOnlyThePlanTreeAndPreservesStableIDs() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let weekID = UUID()
        let dayID = UUID()
        let sessionID = UUID()
        let planID = PlanID(raw: UUID())
        let first = plan(id: planID, weekID: weekID, dayID: dayID, sessionID: sessionID,
                         title: "First", updatedAt: 10, itemCount: 1)
        _ = try NormalizedPlanStore.upsert(first, originDevice: "iphone", in: context)
        let second = plan(id: planID, weekID: weekID, dayID: dayID, sessionID: sessionID,
                          title: "Second", updatedAt: 20, itemCount: 2)
        _ = try NormalizedPlanStore.upsert(second, originDevice: "ipad", in: context)

        XCTAssertEqual(try NormalizedPlanStore.fetch(id: planID, in: context)?.title, "Second")
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersistedPlanWeek>()).map(\.id), [weekID])
        let persistedDays = try context.fetch(FetchDescriptor<PersistedPlanDay>())
        XCTAssertEqual(persistedDays.count, 7)
        XCTAssertTrue(persistedDays.contains(where: { $0.id == dayID }))
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersistedPlanSession>()).map(\.id), [sessionID])
        XCTAssertEqual(try context.fetch(FetchDescriptor<PersistedPlanItem>()).count, 2)
    }

    func testClientRelationshipRoundTripsShareMetadataAndLifecycle() throws {
        let context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let relationship = ClientRelationship(
            displayName: "Alex", notes: "Prefers mornings", goal: .hypertrophy,
            status: .paused, shareZoneID: UUID(),
            shareURL: URL(string: "https://www.icloud.com/share/test"),
            createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 2))

        _ = try NormalizedPlanStore.upsert(relationship, in: context)
        let record = try XCTUnwrap(try context.fetch(FetchDescriptor<PersistedClientRelationship>()).first)

        XCTAssertEqual(try record.value(), relationship)
    }

    private func plan(id: PlanID, weekID: UUID, dayID: UUID, sessionID: UUID,
                      title: String, updatedAt: TimeInterval, itemCount: Int) -> Plan {
        let items = (0..<itemCount).map { index in
            WorkoutItem.instruction(InstructionItem(order: index, text: "Cue \(index)"))
        }
        let session = Session(id: sessionID, title: "Session", items: items)
        let days = Weekday.mondayThroughSunday.map { weekday in
            PlanDay(id: weekday == .monday ? dayID : UUID(), weekday: weekday,
                    sessions: weekday == .monday ? [session] : [])
        }
        return Plan(id: id, title: title,
                    weeks: [PlanWeek(id: weekID, index: 0, days: days)],
                    createdAt: Date(timeIntervalSince1970: 1),
                    updatedAt: Date(timeIntervalSince1970: updatedAt))
    }
}

private extension Weekday {
    static let mondayThroughSunday: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]
}
