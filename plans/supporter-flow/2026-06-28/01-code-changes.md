# Supporter Flow — Proposed Code Changes

_Plan only. The code below is a **reference implementation to review**, not yet applied._
_Adapts the radio app's `ObservableObject` pattern to Cladiron's Observation (`@Observable` +
`.environment`) and puts the pure engine in `CadenceCore`._

---

## A. CadenceCore — pure decision engine (testable)

### New file: `CadenceCore/Sources/CadenceCore/ContributionPromptEngine.swift`
Ported verbatim from the radio app, renaming the engagement counter `tracksPlayed → workoutsCompleted`.

```swift
import Foundation

/// Pure decision logic for *when* to show the contribution prompt. No UI, no
/// StoreKit, no I/O — deterministic given its inputs, so it's fully unit-tested.
/// The caller owns the persisted counters (UserDefaults in the app layer).
public struct ContributionPromptEngine: Sendable {
    public var minWorkouts = 12
    public var minSessions = 2
    public var snoozeDays: Double = 7
    public var snoozeLaunches = 5

    public init() {}

    public struct Inputs: Equatable, Sendable {
        public var workoutsCompleted: Int
        public var sessionCount: Int
        public var isSupporter: Bool
        public var optedOut: Bool
        public var promptedThisSession: Bool
        public var lastPromptAt: Date?
        public var launchesSinceLastPrompt: Int
        public var now: Date = Date()
        public init(workoutsCompleted: Int, sessionCount: Int, isSupporter: Bool,
                    optedOut: Bool, promptedThisSession: Bool, lastPromptAt: Date?,
                    launchesSinceLastPrompt: Int, now: Date = Date()) { /* assign all */ }
    }

    public func shouldPrompt(_ i: Inputs) -> Bool {
        if i.optedOut || i.isSupporter { return false }
        if i.promptedThisSession { return false }
        guard i.sessionCount >= minSessions else { return false }
        guard i.workoutsCompleted >= minWorkouts else { return false }
        if let last = i.lastPromptAt {
            let daysSince = i.now.timeIntervalSince(last) / 86_400
            if daysSince < snoozeDays { return false }
            if i.launchesSinceLastPrompt < snoozeLaunches { return false }
        }
        return true
    }
}
```

### New file: `CadenceCore/Tests/CadenceCoreTests/ContributionPromptEngineTests.swift`
Mirror of the radio tests (rename `tracksPlayed → workoutsCompleted`). Cases:
`testPromptsWhenFullyEligible`, `testNeverOnFirstSession`, `testRequiresEnoughWorkouts`
(11 false / 12 true), `testNeverWhenOptedOut`, `testNeverWhenAlreadySupporter`,
`testAtMostOncePerSession`, `testSnoozeNeedsBothTimeAndLaunches`. **Gate: `swift test` stays green.**

> Note: these tests are date-relative but use a fixed `now`, so they are immune to the
> midnight-boundary flakiness seen in the existing recovery-window suite.

---

## B. App target — StoreKit store (`@Observable`)

### New file: `Cadence/Cadence/App/ContributionStore.swift`

```swift
import Foundation
import StoreKit
import Observation

/// StoreKit 2 layer for one-time contribution tips (consumables). Dormant until
/// the product IDs are configured in App Store Connect (no products → the Support
/// UI shows a placeholder and nothing is purchasable).
@MainActor @Observable
final class ContributionStore {
    static let productIDs = [
        "guru.parso.cladiron.tip.small",     // $1.99
        "guru.parso.cladiron.tip.medium",    // $4.99
        "guru.parso.cladiron.tip.generous",  // $9.99
    ]

    private(set) var products: [Product] = []
    private(set) var everContributed = UserDefaults.standard.bool(forKey: "cladiron.everContributed")
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
        do { products = try await Product.products(for: Self.productIDs).sorted { $0.price < $1.price } }
        catch { lastError = error.localizedDescription }
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        purchasingID = product.id; defer { purchasingID = nil }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let txn) = verification else { lastError = "Couldn't verify the purchase."; return false }
                markContributed(); await txn.finish(); return true
            case .userCancelled, .pending: return false
            @unknown default: return false
            }
        } catch { lastError = error.localizedDescription; return false }
    }

    func restore() async {
        try? await AppStore.sync()
        for await result in Transaction.currentEntitlements where { if case .verified = result { return true }; return false }() {
            markContributed()
        }
    }

    private func markContributed() {
        guard !everContributed else { return }
        everContributed = true
        UserDefaults.standard.set(true, forKey: "cladiron.everContributed")
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let txn) = result else { continue }
                await self?.markContributed(); await txn.finish()
            }
        }
    }
}
```
> Differences from radio: `@Observable` instead of `ObservableObject`/`@Published`;
> `@ObservationIgnored` on the task; consumables don't appear in `currentEntitlements`
> after `finish()`, so `restore()` is a courtesy (mainly resets the local bool if it was
> lost). Keep it for parity / App Review expectations.

---

## C. App target — coordinator (`@Observable`, counters in UserDefaults)

### New file: `Cadence/Cadence/App/ContributionCoordinator.swift`

```swift
import Foundation
import Observation
import CadenceCore

@MainActor @Observable
final class ContributionCoordinator {
    var showToast = false

    @ObservationIgnored private let engine = ContributionPromptEngine()
    @ObservationIgnored private let store: ContributionStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var promptedThisSession = false

    private enum Key {
        static let workouts      = "contrib.workoutsCompleted"
        static let sessions      = "contrib.sessionCount"
        static let optedOut      = "contrib.optedOut"
        static let lastPrompt    = "contrib.lastPromptAt"
        static let launchesSince = "contrib.launchesSinceLastPrompt"
    }

    init(store: ContributionStore, defaults: UserDefaults = .standard) {
        self.store = store; self.defaults = defaults
    }

    func beginSession() {
        defaults.set(defaults.integer(forKey: Key.sessions) + 1, forKey: Key.sessions)
        defaults.set(defaults.integer(forKey: Key.launchesSince) + 1, forKey: Key.launchesSince)
        promptedThisSession = false
    }

    /// Bump on each genuine completed workout. Static so call sites needn't hold a ref.
    static func recordWorkoutCompleted(defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: Key.workouts) + 1, forKey: Key.workouts)
    }

    func evaluate() {
        guard !showToast else { return }
        let inputs = ContributionPromptEngine.Inputs(
            workoutsCompleted: defaults.integer(forKey: Key.workouts),
            sessionCount: defaults.integer(forKey: Key.sessions),
            isSupporter: store.isSupporter,
            optedOut: defaults.bool(forKey: Key.optedOut),
            promptedThisSession: promptedThisSession,
            lastPromptAt: defaults.object(forKey: Key.lastPrompt) as? Date,
            launchesSinceLastPrompt: defaults.integer(forKey: Key.launchesSince),
            now: Date())
        guard engine.shouldPrompt(inputs) else { return }
        promptedThisSession = true
        defaults.set(Date(), forKey: Key.lastPrompt)
        defaults.set(0, forKey: Key.launchesSince)
        showToast = true
    }

    func dismissToast() { showToast = false }
    func optOutForever() { defaults.set(true, forKey: Key.optedOut); showToast = false }
}
```

---

## D. App target — UI

### New file: `Cadence/Cadence/Features/Settings/ContributionToast.swift`
Same layout as the radio `ContributionToast` (Support / Maybe later / Don't ask again),
Cladiron copy:
> Title: **"Enjoying Cladiron?"** · Body: **"It's free, open-source, and has no ads or
> subscriptions. An optional tip helps support continued development."**

### New file: `Cadence/Cadence/Features/Settings/ContributionSupportView.swift`
Same structure as the radio `ContributionSupportView`, with `@Observable` access:
- `let store: ContributionStore` (Observation tracks reads; no `@ObservedObject` needed).
- Supporter state → "Thank you for your support!" + invite another tip.
- Else → pitch (drop the Internet-Archive line per D3): *"Cladiron is free, open-source, and
  ad-free. An optional contribution supports continued development."*
- `if store.products.isEmpty` → placeholder "Support options aren't available yet."
- Product rows with `displayName` / `description` / `displayPrice`, spinner on `purchasingID`.
- "Restore Purchases" button → `await store.restore()`.
- Keep the `.accessibilityLabel`/`.accessibilityHint` on each row (radio already does this).
- `navigationTitle("Support Cladiron")`, optional `showsDoneButton` for the sheet.

---

## E. Settings integration

### `Cadence/Cadence/Features/Settings/SettingsView.swift`
**Append a NEW `Section` at the very bottom** (just before/after the existing `About`
section — per the repo's §06 "append-only" convention so existing coordinate-tap UI tests
keep their offsets). The store is injected via environment:

```swift
@Environment(ContributionStore.self) private var contributionStore
...
Section {
    NavigationLink {
        ContributionSupportView(store: contributionStore)
    } label: {
        Label(contributionStore.isSupporter ? "Supporter — Thank You" : "Support Cladiron",
              systemImage: contributionStore.isSupporter ? "heart.fill" : "heart")
            .foregroundStyle(contributionStore.isSupporter ? Color.pink : Color.accentColor)
    }
    .accessibilityIdentifier("settings.support")
} footer: {
    Text("Cladiron is free and open-source. A one-time tip is an optional way to support development.")
}
```
(Per D5, skip the radio's "Show Supporter Badge" toggle unless you want a badge.)

### `Cadence/Cadence/Features/Settings/AboutView.swift` (D4)
Reword line 84 from *"No subscriptions, no ads, no upsells."* to e.g.
*"No subscriptions and no ads. An optional tip jar is the only thing you can buy — and it's
never required."* Keep the existing `principle("dollarsign.circle", "Free & open source", …)`.

---

## F. App wiring

### `Cadence/Cadence/CadenceApp.swift`
Build the store + coordinator, inject them, and host the toast + support sheet at the
WindowGroup root (mirrors `ParsoRadioApp` lines 159–184, adapted to Observation):

```swift
@State private var contributionStore = ContributionStore()
@State private var contributions: ContributionCoordinator   // set in init after store
@Environment(\.scenePhase) private var scenePhase
@State private var showSupport = false
// in init(): _contributions = State(initialValue: ContributionCoordinator(store: <the store>))
// (or lazily build the coordinator in a small wrapper to share the same store instance)
```
```swift
WindowGroup {
    RootTabView()
        .environment(model).environment(settings).environment(active)
        .environment(contributionStore)
        .environment(contributions)
        .task { model.activateWCSession() }
        .task { contributions.beginSession() }
        .overlay(alignment: .bottom) {
            if contributions.showToast {
                ContributionToast(
                    onSupport: { contributions.dismissToast(); showSupport = true },
                    onLater:   { contributions.dismissToast() },
                    onNever:   { contributions.optOutForever() })
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: contributions.showToast)
        .sheet(isPresented: $showSupport) {
            NavigationStack { ContributionSupportView(store: contributionStore, showsDoneButton: true) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { contributions.evaluate() }
        }
}
```
> Implementation note: `@State` can't reference another `@State` at init cleanly. Simplest
> robust pattern — make `ContributionCoordinator` build/hold its own `ContributionStore`,
> OR expose the store via the coordinator (`contributions.store`) and inject only the
> coordinator. Decide during implementation; either keeps a single shared store instance.

### Engagement hook — `recordWorkoutCompleted()`
Call it exactly where a workout genuinely completes. Concrete call sites in the current code:
- **Strength finish:** where `ActiveWorkoutModel.finishedSummary` is set (workout ended). Add
  `ContributionCoordinator.recordWorkoutCompleted()` there.
- **Cardio / interval / swim / logged saves:** the `onSaved` callbacks wired in
  `HomeView.swift` (e.g. `RecordCardioView`, `OutdoorCardioView`, `IntervalView`,
  `SwimRecordView`, `TimerCardioSetupView`, `LogWorkoutPicker`) all funnel through
  `markWorkoutHistoryChanged()` (HomeView.swift:329). Add the bump **inside the genuine
  user-completed save paths** (not the HealthKit-ingest path in `syncCardioFromHealth()`,
  which would over-count Watch imports).
- Recommended: add a single private helper in HomeView that calls both
  `markWorkoutHistoryChanged()` and `ContributionCoordinator.recordWorkoutCompleted()` from
  the real-completion callbacks, leaving the HealthKit-ingest path calling only
  `markWorkoutHistoryChanged()`.

---

## G. Local StoreKit config (testing)

### New file: `Cadence/Cadence.storekit`
Three **consumable** products mirroring `ParsoRadio.storekit`, with Cladiron IDs/copy:

| productID | type | price | displayName | description |
|---|---|---|---|---|
| `guru.parso.cladiron.tip.small` | consumable | 1.99 | Buy us a coffee | A small thank-you that helps support Cladiron's development. |
| `guru.parso.cladiron.tip.medium` | consumable | 4.99 | Supporter | Support continued development of this free, open-source coach. |
| `guru.parso.cladiron.tip.generous` | consumable | 9.99 | Patron | A generous contribution to keep Cladiron free, open-source, and independent. |

Enable it in the **Run** scheme (Xcode step in `02-manual-steps.md` M7) so the Support
screen and toast are exercisable in the simulator with no ASC setup.

---

## H. Verification (after implementing, not now)
- `cd CadenceCore && swift test` — engine tests green; total count unchanged otherwise.
- `xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence -destination '…iPhone…' build`.
- Run with the `.storekit` file: open Settings → Support, buy each tier (sandbox), confirm
  "Supporter — Thank You", confirm toast stops after becoming a supporter, confirm
  "Don't ask again" persists, confirm placeholder when products are absent.
- (Optional) a UI test asserting the Settings "Support" row exists
  (`settings.support` identifier) and opens the Support screen.
