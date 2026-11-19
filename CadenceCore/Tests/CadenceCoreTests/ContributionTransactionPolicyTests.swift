import Foundation
import Testing
@testable import CadenceCore

struct ContributionTransactionPolicyTests {
    private let id = "guru.parso.workout.support.dev"
    private typealias P = ContributionTransactionPolicy

    @Test func singleConfiguredID() {
        #expect(SupportProductConfiguration.productID == id)
        #expect(P.grantsSupporterStatus(productID: id))
        #expect(!P.grantsSupporterStatus(productID: "guru.parso.cladiron." + "tip.generous"))
        #expect(!P.grantsSupporterStatus(productID: "other"))
    }
    @Test func updateEffects() {
        #expect(P.effects(forUpdateVerified: true, productID: id) == [.markSupporter, .finish])
        #expect(!P.effects(forUpdateVerified: true, productID: "other").contains(.markSupporter))
        #expect(P.effects(forUpdateVerified: false, productID: id) == [])
    }
    @Test func purchaseOutcomes() {
        #expect(P.effects(for: .verified(productID: id)) == [.markSupporter, .finish])
        for o: P.PurchaseOutcome in [.cancelled, .pending, .unverified, .failed] {
            #expect(P.effects(for: o) == [])
            #expect(!P.isSuccess(o))
        }
        #expect(P.isSuccess(.verified(productID: id)))
        #expect(!P.isSuccess(.verified(productID: "other")))
    }
    @Test func replayFinishesOnce() {
        var ledger = TransactionFinishLedger()
        #expect(ledger.observe(transactionID: 7, productID: id, verified: true) == [.markSupporter, .finish])
        #expect(ledger.observe(transactionID: 7, productID: id, verified: true) == [.markSupporter])
        #expect(ledger.isSupporter)
        _ = ledger.observe(transactionID: 8, productID: id, verified: false)
        #expect(ledger.isSupporter)
    }
    @Test func unverifiedNeverSupporter() {
        var ledger = TransactionFinishLedger()
        #expect(ledger.observe(transactionID: 1, productID: id, verified: false) == [])
        #expect(!ledger.isSupporter)
    }
    @Test func migration() {
        #expect(P.migratedSupporter(current: false, legacy: true))
        #expect(!P.migratedSupporter(current: false, legacy: false))
        #expect(P.migratedSupporter(current: true, legacy: false))
        #expect(P.migratedSupporter(current: P.migratedSupporter(current: false, legacy: true), legacy: true))
    }
    @Test func singularPresentation() {
        #expect(SupportProductPresentation.make(displayPrice: nil) == .unavailable)
        #expect(SupportProductPresentation.make(displayPrice: "$9.99") == .available(price: "$9.99"))
    }
    @Test func pureTargetsDoNotImportStoreKitUIOrDefaults() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        for f in files where f.lastPathComponent.hasPrefix("Contribution") || f.lastPathComponent.hasPrefix("SupportDevelopment") {
            let text = try String(contentsOf: f, encoding: .utf8)
            for banned in ["import StoreKit", "import SwiftUI", "UserDefaults.", ": UserDefaults", "UserDefaults("] {
                #expect(!text.contains(banned), "\(f.lastPathComponent) contains \(banned)")
            }
        }
    }
}
