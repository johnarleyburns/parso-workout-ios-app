import XCTest
import CadenceCore
import CadenceFeatures

final class SetHistoryTextTests: XCTestCase {

    func testLastSetThisSessionText() {
        // 83.9146 kg ≈ 185 lb
        let set = SetEntry(weight: 83.9146, reps: 8, rpe: 7)
        XCTAssertEqual(SetHistoryText.lastSetThisSession(set, unit: .pounds),
                       "Last set 185 lb × 8 · RPE 7")
    }

    func testLastSetThisSessionKilograms() {
        let set = SetEntry(weight: 80, reps: 5)
        XCTAssertEqual(SetHistoryText.lastSetThisSession(set, unit: .kilograms),
                       "Last set 80 kg × 5")
    }

    func testLastSetBodyweightFormat() {
        let set = SetEntry(weight: 10, reps: 12, usesBodyweight: true, rpe: 7)
        XCTAssertEqual(SetHistoryText.lastSetThisSession(set, unit: .kilograms),
                       "Last set BW + 10 kg × 12 · RPE 7")
        let pure = SetEntry(weight: 0, reps: 12, usesBodyweight: true)
        XCTAssertEqual(SetHistoryText.lastSetThisSession(pure, unit: .kilograms),
                       "Last set BW × 12")
    }

    func testLastSetNilForFirstSet() {
        XCTAssertNil(SetHistoryText.lastSetThisSession(nil, unit: .kilograms),
                     "No this-session set → nil, never a fabricated default")
    }
}
