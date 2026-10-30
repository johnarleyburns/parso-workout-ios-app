import XCTest
@testable import CadenceFeatures
import CadenceCore

final class WatchSetDefaultSnapshotTests: XCTestCase {
    typealias S = WatchSetDefaultSnapshot
    private let partner = UUID().uuidString

    private func ex(_ name: String, w: Double, ladders: [[Int]] = [[5, 5]]) -> S.Exercise {
        S.Exercise(id: name, displayName: name, repLadders: ladders,
                   samples: [.init(weightKg: w, reps: 5)], firstWorkingWeightKg: w)
    }

    private func snapshot() -> S {
        S(generatedAt: Date(timeIntervalSince1970: 1_000), performers: [
            .init(id: "owner", displayName: "Me",
                  exercises: [ex("Bench Press", w: 80), ex("Squat", w: 100)],
                  generalRepLadders: [[5, 5, 5]]),
            .init(id: partner, displayName: "Me",
                  exercises: [ex("Bench Press", w: 40), ex("Squat", w: 50)],
                  generalRepLadders: [[8, 8]])
        ])
    }

    func testCodableAndPropertyListRoundTrip() throws {
        let s = snapshot()
        let decoded = try JSONDecoder().decode(S.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded, s)
        let plist = s.propertyList
        XCTAssertTrue(PropertyListSerialization.propertyList(plist, isValidFor: .binary))
        XCTAssertEqual(S(propertyList: plist), s)
    }

    func testHistoryNeverCrossesPerformers() {
        let s = snapshot()
        let owner = s.history(exerciseKey: "bench press", performerID: "owner")
        let other = s.history(exerciseKey: "bench press", performerID: partner)
        XCTAssertEqual(owner.firstWorkingWeightKg, 80)
        XCTAssertEqual(owner.weightSamples.map(\.weight), [80])
        XCTAssertEqual(owner.generalRepLadders, [[5, 5, 5]])
        XCTAssertEqual(owner.repLadders, [[5, 5]])
        XCTAssertEqual(other.firstWorkingWeightKg, 40)
        XCTAssertEqual(other.generalRepLadders, [[8, 8]])
        XCTAssertTrue(owner.repsLoggedThisSession.isEmpty)
        XCTAssertNil(owner.lastWeightThisSessionKg)
    }

    func testMissingKeysYieldEmpty() {
        let s = snapshot()
        XCTAssertEqual(s.history(exerciseKey: "deadlift", performerID: "owner"), .empty)
        XCTAssertEqual(s.history(exerciseKey: "squat", performerID: UUID().uuidString), .empty)
    }

    func testKeyNormalization() {
        XCTAssertEqual(S.canonicalKey(" Bench   Press "), S.canonicalKey("bench press"))
        XCTAssertEqual(snapshot().history(exerciseKey: " Bench Press ", performerID: "owner").firstWorkingWeightKg, 80)
    }

    func testBoundsKeepNewestInOrder() {
        let ladders = (1...30).map { [$0] }
        let samples = (1...60).map { S.Sample(weightKg: Double($0), reps: 5) }
        let e = S.Exercise(id: "x", displayName: "x", repLadders: ladders, samples: samples,
                           firstWorkingWeightKg: 1)
        XCTAssertEqual(e.repLadders.map { $0[0] }, Array(19...30))
        XCTAssertEqual(e.samples.map(\.weightKg), (13...60).map(Double.init))
        let p = S.Performer(id: "owner", displayName: "o", exercises: [], generalRepLadders: ladders)
        XCTAssertEqual(p.generalRepLadders.map { $0[0] }, Array(10...30))
    }

    func testInvalidValuesAreDropped() {
        let e = S.Exercise(id: "x", displayName: "x", repLadders: [[0, -1], [5]],
                           samples: [.init(weightKg: .nan, reps: 5), .init(weightKg: 0, reps: 5),
                                     .init(weightKg: 50, reps: 0), .init(weightKg: 50, reps: 5)],
                           firstWorkingWeightKg: -3)
        XCTAssertEqual(e.repLadders, [[5]])
        XCTAssertEqual(e.samples.count, 1)
        XCTAssertNil(e.firstWorkingWeightKg)
        let s = S(generatedAt: Date(), performers: [.init(id: "bogus", displayName: "b", exercises: [], generalRepLadders: [])])
        XCTAssertTrue(s.performers.isEmpty)
    }

    func testFutureVersionAndMalformedFailSafely() {
        var plist = snapshot().propertyList
        plist["version"] = S.currentVersion + 1
        XCTAssertNil(S(propertyList: plist))
        XCTAssertNil(S(propertyList: ["version": 1]))
        XCTAssertNil(S(propertyList: [:]))
    }
}
