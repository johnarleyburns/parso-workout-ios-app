import Foundation
import Testing
import CadenceCore
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchCardioSuggestionTests {
    private func suggestion() -> CardioSuggestion {
        CardioSuggestion(type: .run, durationMinutes: 30, intensity: .easy,
                         rationale: "test", citationIDs: [])
    }

    @Test func envelopeRoundTripsThroughEncodeDecode() throws {
        let envelope = WatchCardioSuggestionEnvelope.make(suggestion: suggestion(), issuedAt: Date())
        let data = try envelope.encoded()
        guard case .success(let decoded) = WatchCardioSuggestionEnvelope.decode(data) else {
            Issue.record("expected successful decode")
            return
        }
        #expect(decoded == envelope)
    }

    @Test func expiredEnvelopeIsNotStartable() {
        let issuedAt = Date(timeIntervalSince1970: 1000)
        let envelope = WatchCardioSuggestionEnvelope.make(suggestion: suggestion(), issuedAt: issuedAt)
        #expect(!envelope.isStartable(now: issuedAt.addingTimeInterval(WatchCardioSuggestionEnvelope.maximumLifetime + 1)))
    }

    @Test func resolveWithNoEnvelopeNeedsSyncWithNoSnapshotReason() {
        let result = WatchCardioSuggestResolver.resolve(envelope: nil, now: Date())
        guard case .needsSync(let reason, let lastSyncedAt) = result else {
            Issue.record("expected .needsSync")
            return
        }
        #expect(reason == .noSnapshot)
        #expect(lastSyncedAt == nil)
    }

    @Test func resolveWithFreshEnvelopeIsReady() {
        let now = Date()
        let envelope = WatchCardioSuggestionEnvelope.make(suggestion: suggestion(), issuedAt: now)
        let result = WatchCardioSuggestResolver.resolve(envelope: envelope, now: now)
        guard case .ready(let ready, _, let syncedAt) = result else {
            Issue.record("expected .ready")
            return
        }
        #expect(ready == suggestion())
        #expect(syncedAt == now)
    }

    @Test func resolveWithExpiredEnvelopeNeedsSyncWithExpiredReason() {
        let issuedAt = Date(timeIntervalSince1970: 1000)
        let envelope = WatchCardioSuggestionEnvelope.make(suggestion: suggestion(), issuedAt: issuedAt)
        let result = WatchCardioSuggestResolver.resolve(
            envelope: envelope, now: issuedAt.addingTimeInterval(WatchCardioSuggestionEnvelope.maximumLifetime + 1))
        guard case .needsSync(let reason, _) = result else {
            Issue.record("expected .needsSync")
            return
        }
        #expect(reason == .expired)
    }

    @Test func contextPayloadRoundTripAndAbsent() throws {
        let envelope = WatchCardioSuggestionEnvelope.make(suggestion: suggestion(), issuedAt: Date())
        let context = try WatchSync.contextDict(envelope)
        #expect(WatchCardioSuggestionPayload(context: context) == .envelope(envelope))
        #expect(WatchCardioSuggestionPayload(context: [:]) == .absent)
        #expect(WatchCardioSuggestionPayload(context: [WatchSync.Key.cardioSuggestionSnapshot: Data([1])]) == .invalid)
    }
}
