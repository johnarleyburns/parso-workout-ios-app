import Foundation
import StoreKit
import Observation
import CadenceCore

/// The outcome of a purchase attempt, surfaced to the paywall UI.
enum PurchaseOutcome: Equatable {
    case success(ProEntitlement)
    case userCancelled
    case pending            // Ask to Buy — awaiting approval
    case failed(String)
}

/// StoreKit 2 mechanism for Cladiron Pro. On-device JWS verification only — no
/// RevenueCat, no server, no telemetry (brand requirement, monetization plan §3).
///
/// The pure entitlement derivation + offline-cache policy live in
/// `CadenceCore.EntitlementResolver` / `EntitlementCachePolicy` (unit-tested);
/// this shell is the StoreKit glue, validated on device/sandbox.
@MainActor
@Observable
final class StoreService {

    /// Single source of truth for Coach unlock, observed app-wide.
    private(set) var entitlement: ProEntitlement = .free
    var isPro: Bool { entitlement.isPro }

    private(set) var products: [Product] = []
    private(set) var purchasingID: String?
    var lastError: String?

    /// When the current introductory trial ends (set only while on a trial), used
    /// for the quiet "Trial — X days left" header and the 3-days-before reminder.
    private(set) var trialEndDate: Date?

    /// Whole days remaining in the trial, or nil when not on a trial.
    var trialDaysRemaining: Int? {
        guard entitlement.source == .trial, let end = trialEndDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
        return max(0, days)
    }

    var annual: Product? { products.first { $0.id == ProProductID.annual } }
    var monthly: Product? { products.first { $0.id == ProProductID.monthly } }
    var lifetime: Product? { products.first { $0.id == ProProductID.lifetime } }

    /// The intro (free-trial) offer on the annual plan, if configured.
    var annualIntroOffer: Product.SubscriptionOffer? { annual?.subscription?.introductoryOffer }

    private static let cacheKey = "cladiron.pro.entitlementCache"

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private let uiTestForcedEntitlement: ProEntitlement?

    init() {
        // UI tests can force an entitlement so both gated and unlocked states are
        // exercisable without a live StoreKit session.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-proLocked") {
            uiTestForcedEntitlement = .free
        } else if args.contains("-proUnlocked") {
            uiTestForcedEntitlement = .pro(source: .lifetime)
        } else if args.contains("-uiTest") {
            // Existing coach UI tests assume the Coach is present; default UI-test
            // runs to unlocked. Paywall/gating tests opt in with `-proLocked`.
            uiTestForcedEntitlement = .pro(source: .lifetime)
        } else {
            uiTestForcedEntitlement = nil
        }

        if let forced = uiTestForcedEntitlement {
            entitlement = forced
            return
        }

        // Trust the offline cache immediately at cold launch so a network blip
        // never locks a paying user out; StoreKit reconfirms in `start()`.
        entitlement = EntitlementCachePolicy.effective(loadCache())
    }

    deinit { updatesTask?.cancel() }

    /// Begin listening for transactions and load products/entitlement. Call once
    /// at app launch.
    func start() async {
        guard uiTestForcedEntitlement == nil else { return }
        updatesTask = listenForTransactions()
        await loadProducts()
        await refreshEntitlement()
    }

    func loadProducts() async {
        do {
            let all = try await Product.products(for: Array(ProProductID.all))
            products = all.sorted { $0.price < $1.price }
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func purchase(_ product: Product) async -> PurchaseOutcome {
        purchasingID = product.id
        defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Couldn't verify the purchase."
                    return .failed("Couldn't verify the purchase.")
                }
                await transaction.finish()
                await refreshEntitlement()
                return .success(entitlement)
            case .userCancelled:
                return .userCancelled
            case .pending:
                return .pending
            @unknown default:
                return .failed("Unknown purchase result.")
            }
        } catch {
            lastError = error.localizedDescription
            return .failed(error.localizedDescription)
        }
    }

    /// App Review requirement — wired to a visible "Restore Purchases" button.
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlement()
    }

    /// Rebuild entitlement from `Transaction.currentEntitlements` and cache it.
    func refreshEntitlement() async {
        guard uiTestForcedEntitlement == nil else { return }
        var records: [EntitlementRecord] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            records.append(record(from: transaction))
        }
        let resolved = EntitlementResolver.resolve(records: records)
        entitlement = resolved
        saveCache(CachedEntitlement(entitlement: resolved, recordedAt: Date()))
        updateTrialState(records: records, resolved: resolved)
    }

    /// Track the trial end date and (de)schedule the single value-receipt reminder.
    private func updateTrialState(records: [EntitlementRecord], resolved: ProEntitlement) {
        guard resolved.source == .trial else {
            trialEndDate = nil
            TrialNotifier.cancel()
            return
        }
        let end = records
            .filter { $0.isIntroductoryOffer && $0.revocationDate == nil }
            .compactMap(\.expirationDate)
            .min()
        trialEndDate = end
        if let end { TrialNotifier.scheduleReminder(trialEnd: end) }
    }

    // MARK: - Private

    private func record(from transaction: StoreKit.Transaction) -> EntitlementRecord {
        EntitlementRecord(
            productID: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            revocationDate: transaction.revocationDate,
            isIntroductoryOffer: transaction.offerType == .introductory,
            isUpgraded: transaction.isUpgraded
        )
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
    }

    private func loadCache() -> CachedEntitlement? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(CachedEntitlement.self, from: data)
    }

    private func saveCache(_ cache: CachedEntitlement) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}
