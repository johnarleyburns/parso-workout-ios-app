import Testing
@testable import CadenceCore

struct CloudKitAccountGateTests {
    @Test func knownCloudKitAccountStatusesMapToUserFacingAvailability() {
        #expect(CloudKitAccountGate.availability(for: 1) == .available)
        #expect(CloudKitAccountGate.availability(for: 3) == .restricted)
        #expect(CloudKitAccountGate.availability(for: 4) == .noAccount)
    }

    @Test func unknownAndCouldNotDetermineStatusesDoNotClaimSync() {
        #expect(CloudKitAccountGate.availability(for: 0) == .temporarilyUnavailable)
        #expect(CloudKitAccountGate.availability(for: 2) == .temporarilyUnavailable)
        #expect(!CloudKitAccountGate.availability(for: 2).canSync)
    }
}
