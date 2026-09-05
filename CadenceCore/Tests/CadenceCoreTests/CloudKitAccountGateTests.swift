import XCTest
@testable import CadenceCore

final class CloudKitAccountGateTests: XCTestCase {
    func testKnownCloudKitAccountStatusesMapToUserFacingAvailability() {
        XCTAssertEqual(CloudKitAccountGate.availability(for: 1), .available)
        XCTAssertEqual(CloudKitAccountGate.availability(for: 3), .restricted)
        XCTAssertEqual(CloudKitAccountGate.availability(for: 4), .noAccount)
    }

    func testUnknownAndCouldNotDetermineStatusesDoNotClaimSync() {
        XCTAssertEqual(CloudKitAccountGate.availability(for: 0), .temporarilyUnavailable)
        XCTAssertEqual(CloudKitAccountGate.availability(for: 2), .temporarilyUnavailable)
        XCTAssertFalse(CloudKitAccountGate.availability(for: 2).canSync)
    }
}
