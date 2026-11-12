import Foundation
import CadenceCore
import StoreKit
import Observation

/// Single-product StoreKit 2 layer for the optional one-time Supporter purchase
/// (a consumable thank-you; it never gates a feature and is not restorable).
/// Value policy lives in `CadenceCore.ContributionTransactionPolicy` (unit-tested).
@MainActor
@Observable
final class ContributionStore {
    enum StoreError: LocalizedError {
        case productUnavailable
        case unverified

        var errorDescription: String? {
            switch self {
            case .productUnavailable: return String(localized: "Support options aren't available yet. Please check back soon.")
            case .unverified: return String(localized: "Couldn't verify the purchase.")
            }
        }
    }

    static let productID = SupportProductConfiguration.productID

    private(set) var product: Product?
    private(set) var isSupporter: Bool
    private(set) var purchasingID: String?
    var lastError: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var ledger: TransactionFinishLedger
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let migrated = ContributionTransactionPolicy.migratedSupporter(
            current: defaults.bool(forKey: SupportProductConfiguration.supporterDefaultsKey),
            legacy: defaults.bool(forKey: SupportProductConfiguration.legacySupporterDefaultsKey))
        if migrated { defaults.set(true, forKey: SupportProductConfiguration.supporterDefaultsKey) }
        self.isSupporter = migrated
        self.ledger = TransactionFinishLedger(isSupporter: migrated)
        updatesTask = listenForTransactions()
        Task { try? await loadProduct() }
    }

    deinit { updatesTask?.cancel() }

    @discardableResult
    func loadProduct() async throws -> Product {
        if let product { return product }
        let found = try await Product.products(for: [Self.productID])
        guard let first = found.first(where: { $0.id == Self.productID }) else {
            throw StoreError.productUnavailable
        }
        product = first
        return first
    }

    /// Returns true on verified success; false on cancel/pending; throws otherwise.
    @discardableResult
    func purchase() async throws -> Bool {
        lastError = nil
        purchasingID = Self.productID
        defer { purchasingID = nil }
        do {
            let product = try await loadProduct()
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else { throw StoreError.unverified }
                await handle(transaction)
                return ContributionTransactionPolicy.isSuccess(.verified(productID: transaction.productID))
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func handle(_ transaction: Transaction) async {
        let effects = ledger.observe(
            transactionID: transaction.id, productID: transaction.productID, verified: true)
        if effects.contains(.markSupporter) { markSupporter() }
        if effects.contains(.finish) { await transaction.finish() }
    }

    private func markSupporter() {
        guard !isSupporter else { return }
        isSupporter = true
        defaults.set(true, forKey: SupportProductConfiguration.supporterDefaultsKey)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self?.handle(transaction)
            }
        }
    }
}
