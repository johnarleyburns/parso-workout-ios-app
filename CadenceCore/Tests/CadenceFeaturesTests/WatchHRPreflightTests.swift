import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct WatchHRPreflightTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func obs(_ n: UInt8, at offset: TimeInterval, sampleID: String? = nil) -> WatchHRObservation {
        WatchHRObservation(observationID: UUID(uuid: (n, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
                           source: .watchHealthKit, sampleEnd: t0.timeIntervalSince1970 + offset,
                           bpm: 120, sampleID: sampleID)
    }

    @Test func reserveIsStableUntilCancelled() {
        var ledger = WatchHRPreflightLedger()
        let a = ledger.reserve(now: t0)
        #expect(ledger.reserve(now: t0.addingTimeInterval(60)) == a)
        ledger.cancel()
        let b = ledger.reserve(now: t0.addingTimeInterval(120))
        #expect(a.phoneWorkoutSessionID != b.phoneWorkoutSessionID)
        #expect(a.captureEpoch != b.captureEpoch)
    }

    @Test func adoptKeepsOnlyInBoundsAndDeduplicates() throws {
        var ledger = WatchHRPreflightLedger()
        let r = ledger.reserve(now: t0)
        let id = r.phoneWorkoutSessionID
        #expect(ledger.buffer(obs(1, at: -30), sessionID: id) == .buffered)
        #expect(ledger.buffer(obs(2, at: 5), sessionID: id) == .buffered)
        #expect(ledger.buffer(obs(2, at: 5), sessionID: id) == .duplicate)
        #expect(ledger.buffer(obs(3, at: 9, sampleID: "hk"), sessionID: id) == .buffered)
        #expect(ledger.buffer(obs(4, at: 9, sampleID: "hk"), sessionID: id) == .duplicate)
        let adoptedResult = ledger.adopt(sessionID: id, start: t0, end: t0.addingTimeInterval(10))
        let adopted = try #require(adoptedResult)
        #expect(adopted.map(\.sampleEnd) == [t0.timeIntervalSince1970 + 5, t0.timeIntervalSince1970 + 9])
        #expect(ledger.reservation == nil)
        #expect(ledger.buffer(obs(5, at: 6), sessionID: id) == .tombstoned)
    }

    @Test func cancelTombstonesAndNeverLeaksToLaterWorkout() {
        var ledger = WatchHRPreflightLedger()
        let a = ledger.reserve(now: t0).phoneWorkoutSessionID
        _ = ledger.buffer(obs(1, at: 1), sessionID: a)
        #expect(ledger.cancel() == a)
        let b = ledger.reserve(now: t0.addingTimeInterval(5)).phoneWorkoutSessionID
        #expect(ledger.buffer(obs(2, at: 2), sessionID: a) == .tombstoned)
        #expect(ledger.adopt(sessionID: a, start: t0, end: t0.addingTimeInterval(100)) == nil)
        #expect(ledger.adopt(sessionID: b, start: t0, end: t0.addingTimeInterval(100))?.count == 0)
    }

    @Test func unknownSessionIsNeverReassigned() {
        var ledger = WatchHRPreflightLedger()
        _ = ledger.reserve(now: t0)
        #expect(ledger.buffer(obs(1, at: 1), sessionID: UUID()) == .unknown)
        #expect(ledger.adopt(sessionID: UUID(), start: t0, end: t0.addingTimeInterval(10)) == nil)
        #expect(ledger.reservation != nil)
    }

    @Test func ledgerSurvivesEncodeDecodeRecreation() throws {
        var ledger = WatchHRPreflightLedger()
        let id = ledger.reserve(now: t0).phoneWorkoutSessionID
        _ = ledger.buffer(obs(1, at: 1), sessionID: id)
        let restored = try JSONDecoder().decode(WatchHRPreflightLedger.self, from: JSONEncoder().encode(ledger))
        #expect(restored == ledger)
        #expect(restored.reservation?.buffered.count == 1)
    }

    @Test func staleReservationIsTombstonedAndReplaced() {
        var ledger = WatchHRPreflightLedger()
        let a = ledger.reserve(now: t0)
        let b = ledger.reserve(now: t0.addingTimeInterval(WatchHRPreflightLedger.staleAfter + 1))
        #expect(a.phoneWorkoutSessionID != b.phoneWorkoutSessionID)
        #expect(ledger.isTombstoned(a.phoneWorkoutSessionID))
    }

    @Test func commandCarriesCaptureEpoch() throws {
        let epoch = UUID(), session = UUID()
        let cmd = WatchHRCommand(action: .start, requestID: UUID(), workoutType: "strength", issuedAt: 5,
                                 phoneWorkoutSessionID: session, captureEpoch: epoch)
        let parsed = try #require(WatchHRCommand(payload: cmd.payload))
        #expect(parsed.captureEpoch == epoch)
        #expect(parsed.phoneWorkoutSessionID == session)
    }
}
