import XCTest
@testable import CadenceCore

final class CoachWarningModalityTests: XCTestCase {
    func testModalityDefaultsToGeneralWhenNotSpecified() {
        let w = CoachWarning(id: "x", message: "m")
        XCTAssertEqual(w.modality, .general)
    }

    func testModalityIsStoredWhenSpecified() {
        let w = CoachWarning(id: "x", message: "m", modality: .strength)
        XCTAssertEqual(w.modality, .strength)
    }
}
