import XCTest
@testable import CadenceCore

final class ContributionTransactionPolicyTests: XCTestCase {
    private let id = "guru.parso.workout.support.dev"
    private typealias P = ContributionTransactionPolicy

    func testSingleConfiguredID() {
        XCTAssertEqual(SupportProductConfiguration.productID, id)
        XCTAssertTrue(P.grantsSupporterStatus(productID: id))
        XCTAssertFalse(P.grantsSupporterStatus(productID: "guru.parso.cladiron." + "tip.generous"))
        XCTAssertFalse(P.grantsSupporterStatus(productID: "other"))
    }
    func testUpdateEffects() {
        XCTAssertEqual(P.effects(forUpdateVerified: true, productID: id), [.markSupporter, .finish])
        XCTAssertFalse(P.effects(forUpdateVerified: true, productID: "other").contains(.markSupporter))
        XCTAssertEqual(P.effects(forUpdateVerified: false, productID: id), [])
    }
    func testPurchaseOutcomes() {
        XCTAssertEqual(P.effects(for: .verified(productID: id)), [.markSupporter, .finish])
        for o: P.PurchaseOutcome in [.cancelled, .pending, .unverified, .failed] {
            XCTAssertEqual(P.effects(for: o), [])
            XCTAssertFalse(P.isSuccess(o))
        }
        XCTAssertTrue(P.isSuccess(.verified(productID: id)))
        XCTAssertFalse(P.isSuccess(.verified(productID: "other")))
    }
    func testReplayFinishesOnce() {
        var ledger = TransactionFinishLedger()
        XCTAssertEqual(ledger.observe(transactionID: 7, productID: id, verified: true), [.markSupporter, .finish])
        XCTAssertEqual(ledger.observe(transactionID: 7, productID: id, verified: true), [.markSupporter])
        XCTAssertTrue(ledger.isSupporter)
        _ = ledger.observe(transactionID: 8, productID: id, verified: false)
        XCTAssertTrue(ledger.isSupporter)
    }
    func testUnverifiedNeverSupporter() {
        var ledger = TransactionFinishLedger()
        XCTAssertEqual(ledger.observe(transactionID: 1, productID: id, verified: false), [])
        XCTAssertFalse(ledger.isSupporter)
    }
    func testMigration() {
        XCTAssertTrue(P.migratedSupporter(current: false, legacy: true))
        XCTAssertFalse(P.migratedSupporter(current: false, legacy: false))
        XCTAssertTrue(P.migratedSupporter(current: true, legacy: false))
        XCTAssertTrue(P.migratedSupporter(current: P.migratedSupporter(current: false, legacy: true), legacy: true))
    }
    func testSingularPresentation() {
        XCTAssertEqual(SupportProductPresentation.make(displayPrice: nil), .unavailable)
        XCTAssertEqual(SupportProductPresentation.make(displayPrice: "$9.99"), .available(price: "$9.99"))
    }
    func testPureTargetsDoNotImportStoreKitUIOrDefaults() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        for f in files where f.lastPathComponent.hasPrefix("Contribution") || f.lastPathComponent.hasPrefix("SupportDevelopment") {
            let text = try String(contentsOf: f, encoding: .utf8)
            for banned in ["import StoreKit", "import SwiftUI", "UserDefaults.", ": UserDefaults", "UserDefaults("] {
                XCTAssertFalse(text.contains(banned), "\(f.lastPathComponent) contains \(banned)")
            }
        }
    }
}
