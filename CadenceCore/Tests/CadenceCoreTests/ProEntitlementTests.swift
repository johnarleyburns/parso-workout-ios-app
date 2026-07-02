import XCTest
@testable import CadenceCore

final class ProEntitlementTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func date(daysFromNow days: Double) -> Date {
        now.addingTimeInterval(days * 24 * 60 * 60)
    }

    // MARK: - Resolver

    func testNoRecordsIsFree() {
        XCTAssertEqual(EntitlementResolver.resolve(records: [], now: now), .free)
    }

    func testLifetimeUnlocksPro() {
        let r = EntitlementRecord(productID: ProProductID.lifetime, purchaseDate: date(daysFromNow: -100))
        XCTAssertEqual(EntitlementResolver.resolve(records: [r], now: now), .pro(source: .lifetime))
    }

    func testActiveSubscriptionUnlocksPro() {
        let r = EntitlementRecord(
            productID: ProProductID.annual,
            purchaseDate: date(daysFromNow: -10),
            expirationDate: date(daysFromNow: 355)
        )
        XCTAssertEqual(EntitlementResolver.resolve(records: [r], now: now), .pro(source: .subscription))
    }

    func testIntroductoryOfferReportsTrialSource() {
        let r = EntitlementRecord(
            productID: ProProductID.annual,
            purchaseDate: date(daysFromNow: -3),
            expirationDate: date(daysFromNow: 27),
            isIntroductoryOffer: true
        )
        XCTAssertEqual(EntitlementResolver.resolve(records: [r], now: now), .pro(source: .trial))
    }

    func testExpiredSubscriptionIsFree() {
        let r = EntitlementRecord(
            productID: ProProductID.monthly,
            purchaseDate: date(daysFromNow: -40),
            expirationDate: date(daysFromNow: -10)
        )
        XCTAssertEqual(EntitlementResolver.resolve(records: [r], now: now), .free)
    }

    func testRevokedTransactionIsFree() {
        let r = EntitlementRecord(
            productID: ProProductID.lifetime,
            purchaseDate: date(daysFromNow: -100),
            revocationDate: date(daysFromNow: -1)
        )
        XCTAssertEqual(EntitlementResolver.resolve(records: [r], now: now), .free)
    }

    func testUpgradedSubscriptionIsIgnored() {
        let upgraded = EntitlementRecord(
            productID: ProProductID.monthly,
            purchaseDate: date(daysFromNow: -20),
            expirationDate: date(daysFromNow: 10),
            isUpgraded: true
        )
        XCTAssertEqual(EntitlementResolver.resolve(records: [upgraded], now: now), .free)
    }

    func testFamilySharedLifetimeUnlocksPro() {
        // Family-shared transactions arrive as ordinary records with no revocation.
        let r = EntitlementRecord(productID: ProProductID.lifetime, purchaseDate: date(daysFromNow: -5))
        XCTAssertEqual(EntitlementResolver.resolve(records: [r], now: now), .pro(source: .lifetime))
    }

    func testLifetimeBeatsActiveSubscription() {
        let sub = EntitlementRecord(
            productID: ProProductID.annual,
            purchaseDate: date(daysFromNow: -10),
            expirationDate: date(daysFromNow: 355)
        )
        let lifetime = EntitlementRecord(productID: ProProductID.lifetime, purchaseDate: date(daysFromNow: -1))
        XCTAssertEqual(EntitlementResolver.resolve(records: [sub, lifetime], now: now), .pro(source: .lifetime))
    }

    func testSubscriptionBeatsTrialWhenBothPresent() {
        let trial = EntitlementRecord(
            productID: ProProductID.monthly,
            purchaseDate: date(daysFromNow: -3),
            expirationDate: date(daysFromNow: 27),
            isIntroductoryOffer: true
        )
        let sub = EntitlementRecord(
            productID: ProProductID.annual,
            purchaseDate: date(daysFromNow: -1),
            expirationDate: date(daysFromNow: 364)
        )
        XCTAssertEqual(EntitlementResolver.resolve(records: [trial, sub], now: now), .pro(source: .subscription))
    }

    func testUnknownProductIsIgnored() {
        let tip = EntitlementRecord(productID: "guru.parso.cladiron.tip.small", purchaseDate: date(daysFromNow: -1))
        XCTAssertEqual(EntitlementResolver.resolve(records: [tip], now: now), .free)
    }

    // MARK: - Offline cache policy

    func testFreeCacheAlwaysUsable() {
        let cached = CachedEntitlement(entitlement: .free, recordedAt: date(daysFromNow: -400))
        XCTAssertTrue(EntitlementCachePolicy.isUsable(cached, now: now))
        XCTAssertEqual(EntitlementCachePolicy.effective(cached, now: now), .free)
    }

    func testLifetimeCacheNeverGoesStale() {
        let cached = CachedEntitlement(entitlement: .pro(source: .lifetime), recordedAt: date(daysFromNow: -3650))
        XCTAssertTrue(EntitlementCachePolicy.isUsable(cached, now: now))
        XCTAssertEqual(EntitlementCachePolicy.effective(cached, now: now), .pro(source: .lifetime))
    }

    func testSubscriptionCacheUsableWithinCeiling() {
        let cached = CachedEntitlement(entitlement: .pro(source: .subscription), recordedAt: date(daysFromNow: -29))
        XCTAssertTrue(EntitlementCachePolicy.isUsable(cached, now: now))
        XCTAssertEqual(EntitlementCachePolicy.effective(cached, now: now), .pro(source: .subscription))
    }

    func testSubscriptionCacheStaleAfterCeiling() {
        let cached = CachedEntitlement(entitlement: .pro(source: .subscription), recordedAt: date(daysFromNow: -31))
        XCTAssertFalse(EntitlementCachePolicy.isUsable(cached, now: now))
        XCTAssertEqual(EntitlementCachePolicy.effective(cached, now: now), .free)
    }

    func testTrialCacheStaleAfterCeiling() {
        let cached = CachedEntitlement(entitlement: .pro(source: .trial), recordedAt: date(daysFromNow: -31))
        XCTAssertEqual(EntitlementCachePolicy.effective(cached, now: now), .free)
    }

    func testNilCacheIsFree() {
        XCTAssertEqual(EntitlementCachePolicy.effective(nil, now: now), .free)
    }

    // MARK: - Codable round-trip (persistence)

    func testEntitlementCodableRoundTrip() throws {
        for value: ProEntitlement in [.free, .pro(source: .lifetime), .pro(source: .subscription), .pro(source: .trial)] {
            let data = try JSONEncoder().encode(CachedEntitlement(entitlement: value, recordedAt: now))
            let decoded = try JSONDecoder().decode(CachedEntitlement.self, from: data)
            XCTAssertEqual(decoded.entitlement, value)
        }
    }
}
