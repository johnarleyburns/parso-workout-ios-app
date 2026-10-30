import XCTest
import SwiftData
import CadenceCore
@testable import CadenceFeatures

final class WatchSetDefaultSnapshotBuilderTests: XCTestCase {
    private var context: ModelContext!
    private var bench: CadenceCore.Exercise!
    private var squat: CadenceCore.Exercise!
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
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
            context.insert(e)
        }
        return s
    }

    private func build(limit: Int = 21) throws -> WatchSetDefaultSnapshot {
        try context.save()
        return try WatchSetDefaultSnapshotBuilder.make(context: context, now: now, sessionLimit: limit)
    }

    func testOwnerHistoryLaddersSamplesAndFirstLoad() throws {
        session(day: 1, sets: [(bench, 60, 8, false, nil), (bench, 60, 7, false, nil)])
        session(day: 2, sets: [(bench, 50, 10, true, nil), (bench, 65, 8, false, nil), (bench, 70, 6, false, nil)])
        let snap = try build()
        let owner = try XCTUnwrap(snap.performers.first { $0.id == "owner" })
        let ex = try XCTUnwrap(owner.exercises.first { $0.id == "bench press" })
        XCTAssertEqual(ex.repLadders, [[8, 7], [8, 6]])
        XCTAssertEqual(ex.samples, [.init(weightKg: 60, reps: 8), .init(weightKg: 60, reps: 7),
                                    .init(weightKg: 65, reps: 8), .init(weightKg: 70, reps: 6)])
        XCTAssertEqual(ex.firstWorkingWeightKg, 65)
        XCTAssertEqual(owner.generalRepLadders, [[8, 7], [8, 6]])
        XCTAssertEqual(ex.firstWorkingWeightKg,
                       WorkoutRepository.firstWorkingSetWeight(for: bench, performedBy: nil, excluding: nil))
    }

    func testPartnerAndOwnerStayIsolatedEvenWithSameNames() throws {
        let a = Person(name: "Sam"), b = Person(name: "sam")
        context.insert(a); context.insert(b)
        session(day: 1, sets: [(bench, 100, 5, false, nil), (bench, 40, 12, false, a),
                               (bench, 30, 15, false, b)])
        let snap = try build()
        XCTAssertEqual(snap.performers.count, 3)
        func benchRow(_ id: String) -> WatchSetDefaultSnapshot.Exercise? {
            snap.performers.first { $0.id == id }?.exercises.first { $0.id == "bench press" }
        }
        XCTAssertEqual(benchRow("owner")?.samples, [.init(weightKg: 100, reps: 5)])
        XCTAssertEqual(benchRow(a.id.uuidString)?.samples, [.init(weightKg: 40, reps: 12)])
        XCTAssertEqual(benchRow(b.id.uuidString)?.samples, [.init(weightKg: 30, reps: 15)])
    }

    func testPartnerWithoutLiftKeepsGeneralLadders() throws {
        let p = Person(name: "Pat"); context.insert(p)
        session(day: 1, sets: [(bench, 60, 8, false, nil), (squat, 20, 20, false, p), (squat, 20, 20, false, p)])
        let snap = try build()
        let row = try XCTUnwrap(snap.performers.first { $0.id == p.id.uuidString })
        XCTAssertEqual(row.generalRepLadders, [[20, 20]])
        XCTAssertNil(row.exercises.first { $0.id == "bench press" })
    }

    func testInvalidSetsAndOldSessionsAreIgnored() throws {
        session(day: 0, sets: [(bench, 999, 1, false, nil)])
        session(day: 1, sets: [(bench, 60, 8, false, nil), (bench, 20, 12, true, nil),
                               (bench, 60, 0, false, nil), (bench, 0, 5, false, nil)])
        let snap = try build(limit: 1)
        let owner = try XCTUnwrap(snap.performers.first { $0.id == "owner" })
        let ex = try XCTUnwrap(owner.exercises.first)
        XCTAssertEqual(ex.samples, [.init(weightKg: 60, reps: 8)])
        XCTAssertEqual(ex.repLadders, [[8, 5]])
        XCTAssertEqual(owner.generalRepLadders, [[8, 5]])
    }

    func testDeterministic() throws {
        let p = Person(name: "Pat"); context.insert(p)
        session(day: 1, sets: [(bench, 60, 8, false, nil), (squat, 80, 5, false, p)])
        XCTAssertEqual(try build(), try build())
    }
}
