import XCTest
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

final class WatchCardioSuggestionTests: XCTestCase {
    private func suggestion() -> CardioSuggestion {
        CardioSuggestion(type: .run, durationMinutes: 30, intensity: .easy,
                         rationale: "test", citationIDs: [])
    }

    func testEnvelopeRoundTripsThroughEncodeDecode() throws {
        let envelope = WatchCardioSuggestionEnvelope.make(suggestion: suggestion(), issuedAt: Date())
        let data = try envelope.encoded()
        guard case .success(let decoded) = WatchCardioSuggestionEnvelope.decode(data) else {
            return XCTFail("expected successful decode")
        }
        XCTAssertEqual(decoded, envelope)
    }

    func testExpiredEnvelopeIsNotStartable() {
        let issuedAt = Date(timeIntervalSince1970: 1000)
        let envelope = WatchCardioSuggestionEnvelope.make(suggestion: suggestion(), issuedAt: issuedAt)
        XCTAssertFalse(envelope.isStartable(now: issuedAt.addingTimeInterval(WatchCardioSuggestionEnvelope.maximumLifetime + 1)))
    }

    func testResolveWithNoEnvelopeNeedsSyncWithNoSnapshotReason() {
        let result = WatchCardioSuggestResolver.resolve(envelope: nil, now: Date())
        guard case .needsSync(let reason, let lastSyncedAt) = result else {
            return XCTFail("expected .needsSync")
        }
        XCTAssertEqual(reason, .noSnapshot)
        XCTAssertNil(lastSyncedAt)
    }

    func testResolveWithFreshEnvelopeIsReady() {
        let now = Date()
        let envelope = WatchCardioSuggestionEnvelope.make(suggestion: suggestion(), issuedAt: now)
        let result = WatchCardioSuggestResolver.resolve(envelope: envelope, now: now)
        guard case .ready(let ready, _, let syncedAt) = result else {
            return XCTFail("expected .ready")
        }
        XCTAssertEqual(ready, suggestion())
        XCTAssertEqual(syncedAt, now)
    }

    func testResolveWithExpiredEnvelopeNeedsSyncWithExpiredReason() {
        let issuedAt = Date(timeIntervalSince1970: 1000)
        let envelope = WatchCardioSuggestionEnvelope.make(suggestion: suggestion(), issuedAt: issuedAt)
        let result = WatchCardioSuggestResolver.resolve(
            envelope: envelope, now: issuedAt.addingTimeInterval(WatchCardioSuggestionEnvelope.maximumLifetime + 1))
        guard case .needsSync(let reason, _) = result else { return XCTFail("expected .needsSync") }
        XCTAssertEqual(reason, .expired)
    }

    func testContextPayloadRoundTripAndAbsent() throws {
        let envelope = WatchCardioSuggestionEnvelope.make(suggestion: suggestion(), issuedAt: Date())
        let context = try WatchSync.contextDict(envelope)
        XCTAssertEqual(WatchCardioSuggestionPayload(context: context), .envelope(envelope))
        XCTAssertEqual(WatchCardioSuggestionPayload(context: [:]), .absent)
        XCTAssertEqual(WatchCardioSuggestionPayload(context: [WatchSync.Key.cardioSuggestionSnapshot: Data([1])]), .invalid)
    }
}
