import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadenceCore
import CadencePhoneFeatures

struct WatchSetDefaultSnapshotTests {
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

    @Test func syncedHistoryCarriesExactLastSetInsteadOfAnOlderRepMatch() throws {
        let last = WorkoutMath.canonical(205, from: .pounds)
        let old = WorkoutMath.canonical(250, from: .pounds)
        let snapshot = S(generatedAt: Date(), performers: [
            .init(id: "owner", displayName: "Me", exercises: [
                .init(id: "Back Squat", displayName: "Back Squat", repLadders: [[6, 8]],
                    samples: [.init(weightKg: old, reps: 6), .init(weightKg: last, reps: 8)], firstWorkingWeightKg: old)
            ], generalRepLadders: [])
        ])
        let history = snapshot.history(exerciseKey: "Back Squat", performerID: "owner")
        let lastPrior = try #require(history.lastPriorWorkingSet)
        #expect(abs(lastPrior.weight - last) <= 0.0001)
        let resolved = PerformerSetPlanner.resolve(setIndex: 0, performerPlan: nil, ownerPlan: [],
            ownerLadder: nil, isOwner: true, history: history)
        #expect(resolved.reps == 8)
        #expect(abs((resolved.weightKg ?? 0) - last) <= 0.0001)
    }

    @Test func sampleCarriesActualSetTimestampAndDecodesLegacyPayloads() throws {
        let date = Date(timeIntervalSince1970: 200)
        let sample = S.Sample(weightKg: 92.986, reps: 8, completedAt: date)
        #expect(try JSONDecoder().decode(S.Sample.self, from: JSONEncoder().encode(sample)) == sample)
        let legacy = Data(#"{"weightKg":92.986,"reps":8}"#.utf8)
        #expect(try JSONDecoder().decode(S.Sample.self, from: legacy).completedAt == nil)
    }

    @Test func codableAndPropertyListRoundTrip() throws {
        let s = snapshot()
        let decoded = try JSONDecoder().decode(S.self, from: JSONEncoder().encode(s))
        #expect(decoded == s)
        let plist = s.propertyList
        #expect(PropertyListSerialization.propertyList(plist, isValidFor: .binary))
        #expect(S(propertyList: plist) == s)
    }

    @Test func historyNeverCrossesPerformers() {
        let s = snapshot()
        let owner = s.history(exerciseKey: "bench press", performerID: "owner")
        let other = s.history(exerciseKey: "bench press", performerID: partner)
        #expect(owner.firstWorkingWeightKg == 80)
        #expect(owner.weightSamples.map(\.weight) == [80])
        #expect(owner.generalRepLadders == [[5, 5, 5]])
        #expect(owner.repLadders == [[5, 5]])
        #expect(other.firstWorkingWeightKg == 40)
        #expect(other.generalRepLadders == [[8, 8]])
        #expect(owner.repsLoggedThisSession.isEmpty)
        #expect(owner.lastWeightThisSessionKg == nil)
    }

    @Test func missingKeysYieldEmpty() {
        let s = snapshot()
        // A missing movement keeps only that performer's general rep habit (#432).
        let missing = s.history(exerciseKey: "deadlift", performerID: "owner")
        #expect(missing.generalRepLadders == [[5, 5, 5]])
        #expect(missing.repLadders.isEmpty)
        #expect(missing.weightSamples.isEmpty)
        #expect(missing.firstWorkingWeightKg == nil)
        #expect(s.history(exerciseKey: "squat", performerID: UUID().uuidString) == .empty)
    }

    @Test func historyFallsBackToNameMatchWhenIDIsUnknown() {
        let s = snapshot()
        // A Watch-local-only performer id (never synced to the phone, e.g. the
        // `legacy-name:` sentinel for a partner added by typed name) must still
        // resolve that partner's synced history by matching displayName.
        let unknownID = "legacy-name:sam"
        let byName = s.history(exerciseKey: "bench press", performerID: unknownID, performerName: "Me")
        #expect(byName.firstWorkingWeightKg == 40, "falls back to the partner's own synced row by name")
        // A real id match still wins outright and ignores the name.
        let byID = s.history(exerciseKey: "bench press", performerID: partner, performerName: "someone else entirely")
        #expect(byID.firstWorkingWeightKg == 40)
        // The sentinel for the owner's own name must never accidentally match a partner.
        let unmatched = s.history(exerciseKey: "bench press", performerID: unknownID, performerName: "Nobody Here")
        #expect(unmatched == .empty)
        // No performerName at all behaves exactly as before: id-only, no match.
        #expect(s.history(exerciseKey: "bench press", performerID: unknownID) == .empty)
    }

    @Test func keyNormalization() {
        #expect(S.canonicalKey(" Bench   Press ") == S.canonicalKey("bench press"))
        #expect(snapshot().history(exerciseKey: " Bench Press ", performerID: "owner").firstWorkingWeightKg == 80)
    }

    @Test func boundsKeepNewestInOrder() {
        let ladders = (1...30).map { [$0] }
        let samples = (1...60).map { S.Sample(weightKg: Double($0), reps: 5) }
        let e = S.Exercise(id: "x", displayName: "x", repLadders: ladders, samples: samples,
                           firstWorkingWeightKg: 1)
        #expect(e.repLadders.map { $0[0] } == Array(19...30))
        #expect(e.samples.map(\.weightKg) == (13...60).map(Double.init))
        let p = S.Performer(id: "owner", displayName: "o", exercises: [], generalRepLadders: ladders)
        #expect(p.generalRepLadders.map { $0[0] } == Array(10...30))
    }

    @Test func invalidValuesAreDropped() {
        let e = S.Exercise(id: "x", displayName: "x", repLadders: [[0, -1], [5]],
                           samples: [.init(weightKg: .nan, reps: 5), .init(weightKg: 0, reps: 5),
                                     .init(weightKg: 50, reps: 0), .init(weightKg: 50, reps: 5)],
                           firstWorkingWeightKg: -3)
        #expect(e.repLadders == [[5]])
        #expect(e.samples.count == 1)
        #expect(e.firstWorkingWeightKg == nil)
        let s = S(generatedAt: Date(), performers: [.init(id: "bogus", displayName: "b", exercises: [], generalRepLadders: [])])
        #expect(s.performers.isEmpty)
    }

    @Test func futureVersionAndMalformedFailSafely() {
        var plist = snapshot().propertyList
        plist["version"] = S.currentVersion + 1
        #expect(S(propertyList: plist) == nil)
        #expect(S(propertyList: ["version": 1]) == nil)
        #expect(S(propertyList: [:]) == nil)
    }
}
