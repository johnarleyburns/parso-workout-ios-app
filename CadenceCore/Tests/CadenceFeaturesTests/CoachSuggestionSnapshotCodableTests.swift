import XCTest
@testable import CadenceCore
import CadenceFeatures

final class CoachSuggestionSnapshotCodableTests: XCTestCase {
    private typealias F = CoachSuggestionFixtures

    func testJSONAndPlistRoundTripPreserveEveryGeneratorInput() throws {
        let snapshot = F.snapshot(F.request(candidates: F.catalog, recent: ["bench"]))
        let json = try JSONEncoder().encode(snapshot)
        let plist = try PropertyListEncoder().encode(snapshot)
        for data in [json, plist] {
            guard case .success(let decoded) = CoachSuggestionSnapshot.decode(data) else {
                return XCTFail("decode failed")
            }
            XCTAssertEqual(decoded, snapshot)
            XCTAssertEqual(decoded.request.input, snapshot.request.input)
            XCTAssertEqual(CoachSuggestionFingerprint.make(request: decoded.request), snapshot.fingerprint)
        }
    }

    func testUnsupportedSchemaAndCorruptDataFailClosed() throws {
        let snapshot = F.snapshot(F.request(candidates: F.catalog))
        let future = CoachSuggestionSnapshot(
            schemaVersion: 99, generatedAt: snapshot.generatedAt, dayKey: snapshot.dayKey,
            fingerprint: snapshot.fingerprint, request: snapshot.request)
        XCTAssertEqual(CoachSuggestionSnapshot.decode(try JSONEncoder().encode(future)),
                       .failure(.unsupportedSchema(99)))
        XCTAssertNil(CoachSuggestionService.generate(from: future))
        XCTAssertEqual(CoachSuggestionSnapshot.decode(Data("garbage".utf8)), .failure(.corrupt))
        XCTAssertEqual(CoachSuggestionSnapshot.decode(Data("{\"schemaVersion\":1}".utf8)), .failure(.corrupt))
    }

    func testFingerprintTracksSemanticInputsNotTransportMetadata() {
        let base = F.request(candidates: F.catalog, recent: ["bench"])
        let fp = CoachSuggestionFingerprint.make(request: base)
        XCTAssertEqual(fp, CoachSuggestionFingerprint.make(request: base))

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
        for v in variants { XCTAssertNotEqual(CoachSuggestionFingerprint.make(request: v), fp) }

        let a = CoachSuggestionSnapshotBuilder.make(request: base, generatedAt: F.asOf)
        let b = CoachSuggestionSnapshotBuilder.make(request: base, generatedAt: F.asOf.addingTimeInterval(500))
        XCTAssertEqual(a.fingerprint, b.fingerprint)
    }
}
