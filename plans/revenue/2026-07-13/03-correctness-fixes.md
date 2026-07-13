# Phase 2 — Launch-blocking correctness

**Branch:** `phase-2-correctness`
**Depends on:** nothing. Can run in parallel with Phase 1.

Two defects that will cost money the day the app ships.

---

## 2a. Paying subscribers are being shown the upsell

### The bug

```
Cadence/Cadence/Features/Home/HomeView.swift:171
    CoachUpsellPolicy.shouldShowCTA(isPro: false, lastShown: ...)
```

`isPro` is **hardcoded to the literal `false`** instead of being threaded from
`store.isPro`.

`CoachUpsellPolicy.shouldShowCTA` opens with:

```swift
guard !isPro else { return false }
```

That early-return is therefore **unreachable from Home.** A paying subscriber —
annual, monthly, lifetime, or mid-trial — gets shown a green "Unlock the Coach"
billboard advertising the thing they already bought.

That is a refund and a one-star review, and it lands on exactly the users you can
least afford to annoy.

### Why it happened, and how to fix it properly

The policy itself is correct and already unit-tested
(`CadenceCore/CoachUpsellPolicy.swift`, `CoachUpsellPolicyTests`). The bug is at
the **call site**, which lives in a SwiftUI `View` — where no test can reach it.

**Do not patch the literal.** Move the decision down a layer, where it is
permanently protected by a test. This is precisely the pattern
`scripts/check-test-pyramid.sh` exists to enforce.

### Steps

1. **`CadenceCore/Sources/CadenceCore/CoachUpsellPolicy.swift`** — leave as-is. It
   is correct.

2. **`CadenceCore/Sources/CadenceCore/ProEntitlement.swift`** — add `isPro` if it
   does not already exist:
   ```swift
   public var isPro: Bool {
       if case .pro = self { return true }
       return false
   }
   ```

3. **`CadenceFeatures/HomeCoachModel.swift`** — add the call site here, so it is
   headlessly testable:
   ```swift
   /// Whether Home should render the prominent "Unlock the Coach" CTA.
   ///
   /// Wraps `CoachUpsellPolicy` so the entitlement is threaded through exactly
   /// once, in tested code, rather than at a SwiftUI call site — which is how a
   /// hardcoded `isPro: false` once shipped an advertisement to paying users.
   public func upsellCTAVisible(entitlement: ProEntitlement,
                                lastShown: Date?,
                                now: Date = Date()) -> Bool {
       CoachUpsellPolicy.shouldShowCTA(isPro: entitlement.isPro,
                                       lastShown: lastShown,
                                       now: now)
   }
   ```

4. **`HomeView.swift:171`** — call
   `model.upsellCTAVisible(entitlement: store.entitlement, lastShown: ...)`.
   **No boolean literal at the call site.**

### Tests — extend `CadenceFeaturesTests/HomeCoachModelTests.swift`

| Entitlement | `lastShown` | Expected |
|---|---|---|
| `.pro(.subscription)` | `nil` | hidden |
| `.pro(.trial)` | `nil` | hidden |
| `.pro(.lifetime)` | `nil` | hidden |
| `.free` | `nil` (never shown) | **shown** |
| `.free` | 13 days ago | hidden (respects the 14-day interval) |
| `.free` | 15 days ago | shown |

Include a regression test **named for the bug** — e.g.
`test_proUserWithNoPriorImpression_neverSeesUpsell()`. That is the exact case the
hardcoded `false` broke, and the one a future refactor is most likely to
reintroduce.

---

## 2b. `CoachGate` is dead code

`Cadence/Cadence/Features/Coach/CoachGate.swift` defines `CoachGate` and
`CoachLockedView`. **Neither is ever instantiated anywhere in the codebase.**

The real gate is `CoachSurfacePresenter.state(entitlement:)`, called from
`HomeView.swift:157`.

Delete the file. `grep -r "CoachGate\|CoachLockedView"` first to confirm zero
references. Right now it is a trap for anyone reading the paywall logic — an agent
looking for "where is the coach gated?" finds a plausible-looking gate that does
nothing.

---

## Acceptance

- `swift test` green, with the new `HomeCoachModelTests` cases.
- `grep -r CoachGate` returns nothing.
- `xcodebuild` builds.
- `scripts/check-test-pyramid.sh` green.

## Commit

```
fix: paying subscribers were shown the upsell CTA; lift the decision into HomeCoachModel
```
