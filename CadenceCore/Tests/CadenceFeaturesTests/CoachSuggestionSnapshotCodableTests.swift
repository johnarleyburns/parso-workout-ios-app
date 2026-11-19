import Foundation
import Testing
@testable import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct CoachSuggestionSnapshotCodableTests {
    private typealias F = CoachSuggestionFixtures

    @Test func jsonAndPlistRoundTripPreserveEveryGeneratorInput() throws {
        let snapshot = F.snapshot(F.request(candidates: F.catalog, recent: ["bench"]))
        let json = try JSONEncoder().encode(snapshot)
        let plist = try PropertyListEncoder().encode(snapshot)
        for data in [json, plist] {
            guard case .success(let decoded) = CoachSuggestionSnapshot.decode(data) else {
                Issue.record("decode failed")
                return
            }
            #expect(decoded == snapshot)
            #expect(decoded.request.input == snapshot.request.input)
            #expect(CoachSuggestionFingerprint.make(request: decoded.request) == snapshot.fingerprint)
        }
    }

    @Test func unsupportedSchemaAndCorruptDataFailClosed() throws {
        let snapshot = F.snapshot(F.request(candidates: F.catalog))
        let future = CoachSuggestionSnapshot(
            schemaVersion: 99, generatedAt: snapshot.generatedAt, dayKey: snapshot.dayKey,
            fingerprint: snapshot.fingerprint, request: snapshot.request)
        #expect(CoachSuggestionSnapshot.decode(try JSONEncoder().encode(future))
                       == .failure(.unsupportedSchema(99)))
        #expect(CoachSuggestionService.generate(from: future) == nil)
        #expect(CoachSuggestionSnapshot.decode(Data("garbage".utf8)) == .failure(.corrupt))
        #expect(CoachSuggestionSnapshot.decode(Data("{\"schemaVersion\":1}".utf8)) == .failure(.corrupt))
    }

    @Test func fingerprintTracksSemanticInputsNotTransportMetadata() {
        let base = F.request(candidates: F.catalog, recent: ["bench"])
        let fp = CoachSuggestionFingerprint.make(request: base)
        #expect(fp == CoachSuggestionFingerprint.make(request: base))

        let variants: [CoachSuggestionRequest] = [
            F.request(candidates: F.catalog, recent: []),
            F.request(candidates: Array(F.catalog.dropLast()), recent: ["bench"]),
            F.request(candidates: F.catalog, recent: ["bench"], tracked: [.chest]),
            F.request(candidates: F.catalog, recent: ["bench"], history: nil),
            F.request(candidates: F.catalog, recent: ["bench"], asOf: F.asOf.addingTimeInterval(86_400)),
            CoachSuggestionRequest(input: base.input, unit: .kilograms, warmupMinutes: 5, cooldownMinutes: 5),
            CoachSuggestionRequest(input: base.input, unit: base.unit, warmupMinutes: 6, cooldownMinutes: 5),
            CoachSuggestionRequest(input: base.input, unit: base.unit, warmupMinutes: 5, cooldownMinutes: 7),
        ]
        for v in variants { #expect(CoachSuggestionFingerprint.make(request: v) != fp) }

        let a = CoachSuggestionSnapshotBuilder.make(request: base, generatedAt: F.asOf)
        let b = CoachSuggestionSnapshotBuilder.make(request: base, generatedAt: F.asOf.addingTimeInterval(500))
        #expect(a.fingerprint == b.fingerprint)
    }
}
