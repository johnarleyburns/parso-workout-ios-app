#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

final class WatchSetDefaultSnapshotBuilderTests {
    private var context: ModelContext!
    private var bench: CadenceCore.Exercise!
    private var squat: CadenceCore.Exercise!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        context = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        bench = Exercise(name: "Bench Press")
        squat = Exercise(name: "Squat")
        context.insert(bench); context.insert(squat)
    }

    @discardableResult
    private func session(day: Int, sets: [(CadenceCore.Exercise, Double, Int, Bool, Person?)]) -> WorkoutSession {
        let s = WorkoutSession(title: "S\(day)", date: base.addingTimeInterval(Double(day) * 86_400),
                               endedAt: base.addingTimeInterval(Double(day) * 86_400 + 3_600))
        context.insert(s)
        for (i, t) in sets.enumerated() {
            let e = SetEntry(weight: t.1, reps: t.2, order: i, isWarmup: t.3,
                             session: s, exercise: t.0, performedBy: t.4)
            e.completedAt = s.date.addingTimeInterval(Double(i))
            context.insert(e)
        }
        return s
    }

    private func sample(_ weight: Double, _ reps: Int, day: Int, order: Int = 0) -> WatchSetDefaultSnapshot.Sample {
        .init(weightKg: weight, reps: reps, completedAt: base.addingTimeInterval(Double(day) * 86_400 + Double(order)))
    }

    private func build(limit: Int = 21) throws -> WatchSetDefaultSnapshot {
        try context.save()
        return try WatchSetDefaultSnapshotBuilder.make(context: context, now: now, sessionLimit: limit)
    }

    @Test func ownerHistoryLaddersSamplesAndFirstLoad() throws {
        session(day: 1, sets: [(bench, 60, 8, false, nil), (bench, 60, 7, false, nil)])
        session(day: 2, sets: [(bench, 50, 10, true, nil), (bench, 65, 8, false, nil), (bench, 70, 6, false, nil)])
        let snap = try build()
        let owner = try #require(snap.performers.first { $0.id == "owner" })
        let ex = try #require(owner.exercises.first { $0.id == "bench press" })
        #expect(ex.repLadders == [[8, 7], [8, 6]])
        #expect(ex.samples == [sample(60, 8, day: 1), sample(60, 7, day: 1, order: 1),
                                    sample(65, 8, day: 2, order: 1), sample(70, 6, day: 2, order: 2)])
        #expect(snap.history(exerciseKey: "Bench Press", performerID: "owner").lastPriorWorkingSet?.date ==
                       base.addingTimeInterval(2 * 86_400 + 2))
        #expect(ex.firstWorkingWeightKg == 65)
        #expect(owner.generalRepLadders == [[8, 7], [8, 6]])
        #expect(ex.firstWorkingWeightKg ==
                       WorkoutRepository.firstWorkingSetWeight(for: bench, performedBy: nil, excluding: nil))
    }

    @Test func partnerAndOwnerStayIsolatedEvenWithSameNames() throws {
        let a = Person(name: "Sam"), b = Person(name: "sam")
        context.insert(a); context.insert(b)
        session(day: 1, sets: [(bench, 100, 5, false, nil), (bench, 40, 12, false, a),
                               (bench, 30, 15, false, b)])
        let snap = try build()
        #expect(snap.performers.count == 3)
        func benchRow(_ id: String) -> WatchSetDefaultSnapshot.Exercise? {
            snap.performers.first { $0.id == id }?.exercises.first { $0.id == "bench press" }
        }
        #expect(benchRow("owner")?.samples == [sample(100, 5, day: 1)])
        #expect(benchRow(a.id.uuidString)?.samples == [sample(40, 12, day: 1, order: 1)])
        #expect(benchRow(b.id.uuidString)?.samples == [sample(30, 15, day: 1, order: 2)])
    }

    @Test func partnerWithoutLiftKeepsGeneralLadders() throws {
        let p = Person(name: "Pat"); context.insert(p)
        session(day: 1, sets: [(bench, 60, 8, false, nil), (squat, 20, 20, false, p), (squat, 20, 20, false, p)])
        let snap = try build()
        let row = try #require(snap.performers.first { $0.id == p.id.uuidString })
        #expect(row.generalRepLadders == [[20, 20]])
        #expect(row.exercises.first { $0.id == "bench press" } == nil)
    }

    @Test func invalidSetsAndOldSessionsAreIgnored() throws {
        session(day: 0, sets: [(bench, 999, 1, false, nil)])
        session(day: 1, sets: [(bench, 60, 8, false, nil), (bench, 20, 12, true, nil),
                               (bench, 60, 0, false, nil), (bench, 0, 5, false, nil)])
        let snap = try build(limit: 1)
        let owner = try #require(snap.performers.first { $0.id == "owner" })
        let ex = try #require(owner.exercises.first)
        #expect(ex.samples == [sample(60, 8, day: 1)])
        #expect(ex.repLadders == [[8, 5]])
        #expect(owner.generalRepLadders == [[8, 5]])
    }

    @Test func deterministic() throws {
        let p = Person(name: "Pat"); context.insert(p)
        session(day: 1, sets: [(bench, 60, 8, false, nil), (squat, 80, 5, false, p)])
        let first = try build()
        let second = try build()
        #expect(first == second)
    }
}
#endif
