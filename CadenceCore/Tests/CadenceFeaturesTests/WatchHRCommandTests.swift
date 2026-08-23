import XCTest
@testable import CadenceFeatures

final class WatchHRCommandTests: XCTestCase {
    func testStartRoundTripsThroughPropertyListPayload() throws {
        let requestID = UUID()
        let command = WatchHRCommand(action: .start, requestID: requestID,
                                     workoutType: "run", issuedAt: 1234.5)
        let decoded = try XCTUnwrap(WatchHRCommand(payload: command.payload))
        XCTAssertEqual(decoded, command)
    }

    func testStopRoundTripsWithRequestIdentity() throws {
        let requestID = UUID()
        let command = WatchHRCommand(action: .stop, requestID: requestID, issuedAt: 1235)
        XCTAssertEqual(WatchHRCommand(payload: command.payload), command)
    }

    func testCommandsAreStrictlyOrderedWhenClockDoesNotAdvance() {
        let first = WatchHRCommand.nextIssuedAt(now: 100, after: nil)
        let second = WatchHRCommand.nextIssuedAt(now: 99, after: first)
        let third = WatchHRCommand.nextIssuedAt(now: 100, after: second)
        XCTAssertGreaterThan(second, first)
        XCTAssertGreaterThan(third, second)
    }

    func testOldOrDuplicateCommandIsNotNewer() {
        XCTAssertFalse(WatchHRCommand(action: .stop, requestID: UUID(), issuedAt: 10)
            .isNewer(than: 10))
        XCTAssertFalse(WatchHRCommand(action: .stop, requestID: UUID(), issuedAt: 9)
            .isNewer(than: 10))
        XCTAssertTrue(WatchHRCommand(action: .stop, requestID: UUID(), issuedAt: 11)
            .isNewer(than: 10))
    }
}
