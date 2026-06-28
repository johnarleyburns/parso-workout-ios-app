import Foundation
import StoreKit
import Observation

/// StoreKit 2 layer for one-time contribution tips (consumables). Dormant until
/// the product IDs below are configured in App Store Connect (no products → the
/// Support UI shows a friendly placeholder and nothing is purchasable, so this
/// can ship before the ASC products exist).
///
/// The pure "when to prompt" decision lives in `CadenceCore.ContributionPromptEngine`
/// (unit-tested); this shell is the StoreKit mechanism, validated on device/sandbox.
@MainActor
@Observable
final class ContributionStore {
    static let productIDs = [
        "guru.parso.cladiron.tip.small",      // $1.99
        "guru.parso.cladiron.tip.medium",     // $4.99
        "guru.parso.cladiron.tip.generous",   // $9.99
    ]

    private static let everContributedKey = "cladiron.everContributed"

    private(set) var products: [Product] = []
    private(set) var everContributed = UserDefaults.standard.bool(forKey: ContributionStore.everContributedKey)
    private(set) var purchasingID: String?
    var lastError: String?

    var isSupporter: Bool { everContributed }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = listenForTransactions()
        Task { await loadProducts() }
    }

    deinit { updatesTask?.cancel() }

    func loadProducts() async {
        do {
            let all = try await Product.products(for: Self.productIDs)
            products = all.sorted { $0.price < $1.price }
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Couldn't verify the purchase."
                    return false
                }
                markContributed()
                await transaction.finish()
                return true
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        for await result in Transaction.currentEntitlements {
            if case .verified = result { markContributed() }
        }
    }

    private func markContributed() {
        guard !everContributed else { return }
        everContributed = true
        UserDefaults.standard.set(true, forKey: Self.everContributedKey)
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await self?.markContributed()
                await transaction.finish()
            }
        }
    }
}
