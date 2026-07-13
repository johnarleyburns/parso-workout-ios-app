import XCTest
import CadenceCore
import CadenceFeatures

final class TrialStateTests: XCTestCase {
    private func rec(intro: Bool, revoked: Date? = nil, expires: Date?) -> EntitlementRecord {
        EntitlementRecord(productID: "annual", purchaseDate: Date(),
                          expirationDate: expires, revocationDate: revoked,
                          isIntroductoryOffer: intro)
    }

    func testEndDateIsEarliestActiveIntroExpiration() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let early = now.addingTimeInterval(3 * 86_400)
        let late = now.addingTimeInterval(9 * 86_400)
        let records = [rec(intro: true, expires: late), rec(intro: true, expires: early)]
        XCTAssertEqual(TrialState.endDate(from: records), early)
    }

    func testEndDateIgnoresNonIntroAndRevoked() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let d = now.addingTimeInterval(5 * 86_400)
        let records = [rec(intro: false, expires: now.addingTimeInterval(86_400)),
                       rec(intro: true, revoked: now, expires: now.addingTimeInterval(2 * 86_400)),
                       rec(intro: true, expires: d)]
        XCTAssertEqual(TrialState.endDate(from: records), d)
    }

    func testEndDateNilWhenNoTrial() {
        XCTAssertNil(TrialState.endDate(from: [rec(intro: false, expires: Date())]))
    }

    func testDaysRemaining() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let end = now.addingTimeInterval(7 * 86_400 + 3600)
        XCTAssertEqual(TrialState.daysRemaining(until: end, now: now), 7)
    }

    func testDaysRemainingClampsAtZero() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(TrialState.daysRemaining(until: now.addingTimeInterval(-86_400), now: now), 0)
    }

    func testDaysRemainingNilWithoutEnd() {
        XCTAssertNil(TrialState.daysRemaining(until: nil))
    }
}
