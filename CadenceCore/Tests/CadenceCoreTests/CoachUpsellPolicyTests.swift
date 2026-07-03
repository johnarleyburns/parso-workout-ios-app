import XCTest
@testable import CadenceCore

/// The upsell-cadence guard: insights are always shown (not this policy's concern);
/// only the prominent "Unlock the Coach" CTA is throttled here.
final class CoachUpsellPolicyTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func date(daysFromNow days: Double) -> Date {
        now.addingTimeInterval(days * 24 * 60 * 60)
    }

    func testProNeverSeesCTA() {
        XCTAssertFalse(CoachUpsellPolicy.shouldShowCTA(isPro: true, lastShown: nil, now: now))
        XCTAssertFalse(CoachUpsellPolicy.shouldShowCTA(isPro: true,
                                                       lastShown: date(daysFromNow: -365),
                                                       now: now))
    }

    func testShowsWhenNeverShownBefore() {
        XCTAssertTrue(CoachUpsellPolicy.shouldShowCTA(isPro: false, lastShown: nil, now: now))
    }

    func testHiddenWithinInterval() {
        XCTAssertFalse(CoachUpsellPolicy.shouldShowCTA(isPro: false,
                                                       lastShown: date(daysFromNow: -1),
                                                       now: now))
        XCTAssertFalse(CoachUpsellPolicy.shouldShowCTA(isPro: false,
                                                       lastShown: date(daysFromNow: -13),
                                                       now: now))
    }

    func testShownAgainAfterInterval() {
        XCTAssertTrue(CoachUpsellPolicy.shouldShowCTA(isPro: false,
                                                      lastShown: date(daysFromNow: -14),
                                                      now: now))
        XCTAssertTrue(CoachUpsellPolicy.shouldShowCTA(isPro: false,
                                                      lastShown: date(daysFromNow: -30),
                                                      now: now))
    }

    func testIntervalBoundaryIsInclusive() {
        let lastShown = now.addingTimeInterval(-CoachUpsellPolicy.minimumInterval)
        XCTAssertTrue(CoachUpsellPolicy.shouldShowCTA(isPro: false, lastShown: lastShown, now: now))
    }
}
