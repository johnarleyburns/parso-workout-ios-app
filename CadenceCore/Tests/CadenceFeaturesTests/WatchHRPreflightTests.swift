import XCTest
@testable import CadenceFeatures

final class WatchHRPreflightTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func obs(_ n: UInt8, at offset: TimeInterval, sampleID: String? = nil) -> WatchHRObservation {
        WatchHRObservation(observationID: UUID(uuid: (n, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)),
                           source: .watchHealthKit, sampleEnd: t0.timeIntervalSince1970 + offset,
                           bpm: 120, sampleID: sampleID)
    }

    func testReserveIsStableUntilCancelled() {
        var ledger = WatchHRPreflightLedger()
        let a = ledger.reserve(now: t0)
        XCTAssertEqual(ledger.reserve(now: t0.addingTimeInterval(60)), a)
        ledger.cancel()
        let b = ledger.reserve(now: t0.addingTimeInterval(120))
        XCTAssertNotEqual(a.phoneWorkoutSessionID, b.phoneWorkoutSessionID)
        XCTAssertNotEqual(a.captureEpoch, b.captureEpoch)
    }

    func testAdoptKeepsOnlyInBoundsAndDeduplicates() throws {
        var ledger = WatchHRPreflightLedger()
        let r = ledger.reserve(now: t0)
        let id = r.phoneWorkoutSessionID
        XCTAssertEqual(ledger.buffer(obs(1, at: -30), sessionID: id), .buffered)
        XCTAssertEqual(ledger.buffer(obs(2, at: 5), sessionID: id), .buffered)
        XCTAssertEqual(ledger.buffer(obs(2, at: 5), sessionID: id), .duplicate)
        XCTAssertEqual(ledger.buffer(obs(3, at: 9, sampleID: "hk"), sessionID: id), .buffered)
        XCTAssertEqual(ledger.buffer(obs(4, at: 9, sampleID: "hk"), sessionID: id), .duplicate)
        let adopted = try XCTUnwrap(ledger.adopt(sessionID: id, start: t0, end: t0.addingTimeInterval(10)))
        XCTAssertEqual(adopted.map(\.sampleEnd), [t0.timeIntervalSince1970 + 5, t0.timeIntervalSince1970 + 9])
        XCTAssertNil(ledger.reservation)
        XCTAssertEqual(ledger.buffer(obs(5, at: 6), sessionID: id), .tombstoned)
    }

    func testCancelTombstonesAndNeverLeaksToLaterWorkout() {
        var ledger = WatchHRPreflightLedger()
        let a = ledger.reserve(now: t0).phoneWorkoutSessionID
        _ = ledger.buffer(obs(1, at: 1), sessionID: a)
        XCTAssertEqual(ledger.cancel(), a)
        let b = ledger.reserve(now: t0.addingTimeInterval(5)).phoneWorkoutSessionID
        XCTAssertEqual(ledger.buffer(obs(2, at: 2), sessionID: a), .tombstoned)
        XCTAssertNil(ledger.adopt(sessionID: a, start: t0, end: t0.addingTimeInterval(100)))
        XCTAssertEqual(ledger.adopt(sessionID: b, start: t0, end: t0.addingTimeInterval(100))?.count, 0)
    }

    func testUnknownSessionIsNeverReassigned() {
        var ledger = WatchHRPreflightLedger()
        _ = ledger.reserve(now: t0)
        XCTAssertEqual(ledger.buffer(obs(1, at: 1), sessionID: UUID()), .unknown)
        XCTAssertNil(ledger.adopt(sessionID: UUID(), start: t0, end: t0.addingTimeInterval(10)))
        XCTAssertNotNil(ledger.reservation)
    }

    func testLedgerSurvivesEncodeDecodeRecreation() throws {
        var ledger = WatchHRPreflightLedger()
        let id = ledger.reserve(now: t0).phoneWorkoutSessionID
        _ = ledger.buffer(obs(1, at: 1), sessionID: id)
        let restored = try JSONDecoder().decode(WatchHRPreflightLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(restored, ledger)
        XCTAssertEqual(restored.reservation?.buffered.count, 1)
    }

    func testStaleReservationIsTombstonedAndReplaced() {
        var ledger = WatchHRPreflightLedger()
        let a = ledger.reserve(now: t0)
        let b = ledger.reserve(now: t0.addingTimeInterval(WatchHRPreflightLedger.staleAfter + 1))
        XCTAssertNotEqual(a.phoneWorkoutSessionID, b.phoneWorkoutSessionID)
        XCTAssertTrue(ledger.isTombstoned(a.phoneWorkoutSessionID))
    }

    func testCommandCarriesCaptureEpoch() throws {
        let epoch = UUID(), session = UUID()
        let cmd = WatchHRCommand(action: .start, requestID: UUID(), workoutType: "strength", issuedAt: 5,
                                 phoneWorkoutSessionID: session, captureEpoch: epoch)
        let parsed = try XCTUnwrap(WatchHRCommand(payload: cmd.payload))
        XCTAssertEqual(parsed.captureEpoch, epoch)
        XCTAssertEqual(parsed.phoneWorkoutSessionID, session)
    }
}
