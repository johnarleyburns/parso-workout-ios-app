import Foundation
import Testing
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WatchHRCommandTests {
    @Test func startRoundTripsThroughPropertyListPayload() throws {
        let requestID = UUID()
        let command = WatchHRCommand(action: .start, requestID: requestID,
                                     workoutType: "run", issuedAt: 1234.5)
        let decoded = try #require(WatchHRCommand(payload: command.payload))
        #expect(decoded == command)
    }

    @Test func stopRoundTripsWithRequestIdentity() throws {
        let requestID = UUID()
        let command = WatchHRCommand(action: .stop, requestID: requestID, issuedAt: 1235)
        #expect(WatchHRCommand(payload: command.payload) == command)
    }

    @Test func commandsAreStrictlyOrderedWhenClockDoesNotAdvance() {
        let first = WatchHRCommand.nextIssuedAt(now: 100, after: nil)
        let second = WatchHRCommand.nextIssuedAt(now: 99, after: first)
        let third = WatchHRCommand.nextIssuedAt(now: 100, after: second)
        #expect(second > first)
        #expect(third > second)
    }

    @Test func oldOrDuplicateCommandIsNotNewer() {
        #expect(!WatchHRCommand(action: .stop, requestID: UUID(), issuedAt: 10)
            .isNewer(than: 10))
        #expect(!WatchHRCommand(action: .stop, requestID: UUID(), issuedAt: 9)
            .isNewer(than: 10))
        #expect(WatchHRCommand(action: .stop, requestID: UUID(), issuedAt: 11)
            .isNewer(than: 10))
    }
}
