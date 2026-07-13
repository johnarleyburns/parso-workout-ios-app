import XCTest
@testable import CadenceCore

/// The founding-price predicate, lifted out of `PaywallView` so the paywall's
/// business logic is testable rather than stranded at a SwiftUI call site.
final class PricingPolicyTests: XCTestCase {

    func testLaunchPriceIsAFoundingPrice() {
        XCTAssertTrue(PricingPolicy.isFoundingPrice(Decimal(99.99)))
    }

    func testFullPriceIsNotAFoundingPrice() {
        XCTAssertFalse(PricingPolicy.isFoundingPrice(Decimal(149.99)))
    }

    func testPriceAboveFullPriceIsNotMislabeled() {
        XCTAssertFalse(PricingPolicy.isFoundingPrice(Decimal(159.99)))
    }

    func testBoundaryJustBelowFullPrice() {
        XCTAssertTrue(PricingPolicy.isFoundingPrice(Decimal(149.98)))
    }
}
