# Phase 1 — Reprice to the coaching tier

**Branch:** `phase-1-pricing`
**Depends on:** Phase 0.
**Decision:** D1 (locked — read `decisions.md` before changing any number here).

---

## Problem

$34.99/yr requires **~140,000 downloads** to reach $100k net. $79.99/yr requires
**~61,000**. See `docs/COMPETITIVE-ANALYSIS.md` §2.

This is the highest-ROI change in the entire plan: it more than halves the
distribution problem with **zero engineering work and no product change.**

## What the code does today

`PaywallView` already reads `product.displayPrice` from StoreKit, so almost
nothing is hardcoded. **Exactly one number is:**

```
Cadence/Cadence/Store/PaywallView.swift:229
    lifetime.price < Decimal(69.99) ? "Founding price" : nil
```

That is business logic living in a `View`, where no test can reach it. Fix that
while you are here — it is the same class of mistake that produced the Phase 2 bug.

---

## Steps

### 1. New `CadenceCore/Sources/CadenceCore/PricingPolicy.swift`

```swift
/// Pricing constants and the founding-price predicate.
/// Pure, so the paywall's business logic is `swift test`-verifiable rather than
/// stranded at a SwiftUI call site.
public enum PricingPolicy {
    /// The lifetime product's full (non-promotional) price.
    public static let lifetimeFullPrice = Decimal(149.99)

    /// True while the lifetime product is still below its full price — i.e. the
    /// launch "founding price" window is open.
    public static func isFoundingPrice(_ price: Decimal) -> Bool {
        price < lifetimeFullPrice
    }
}
```

### 2. `Store/PaywallView.swift:229`

```swift
PricingPolicy.isFoundingPrice(lifetime.price) ? "Founding price" : nil
```

No price literal may remain in any `View`.

### 3. `Cadence/Cadence.storekit`

Update all three prices so local and CI StoreKit tests exercise the real values.

| Product ID | Old | New |
|---|---|---|
| `guru.parso.cladiron.pro.annual` | $34.99 | **$79.99** — keep the 1-month intro free trial |
| `guru.parso.cladiron.pro.monthly` | $4.99 | **$12.99** — no trial |
| `guru.parso.cladiron.pro.lifetime` | $49.99 | **$99.99** — founding price; full price $149.99 |

Leave the tip-jar consumables ($1.99 / $4.99 / $9.99) alone.

### 4. `docs/app-store/metadata.md` and `plans/monetization-plan.md` §2

Update the price table, and **reverse the positioning**. It currently reads:

> "annual undercuts Fitbod (~$96/yr) ~3x… the cheapest lifetime of any serious app
> in the category."

Replace with:

> Cladiron is the value option **within the coaching tier**, not the discount
> option in the tracker tier. RP Hypertrophy charges $299/yr for one coach's
> opinion; Cladiron charges $79.99 and shows you the paper behind every
> prescription.

---

## Tests — new `CadenceCoreTests/PricingPolicyTests.swift`

| Case | Expected |
|---|---|
| `isFoundingPrice(99.99)` | `true` — the launch price is a founding price |
| `isFoundingPrice(149.99)` | `false` — at full price the badge disappears |
| `isFoundingPrice(159.99)` | `false` — guards against a price *above* full price being mislabeled |
| `isFoundingPrice(149.98)` | `true` — boundary |

---

## Acceptance

- `swift test` green.
- No price literal in any `View`.
- The paywall renders `displayPrice` from StoreKit for all three products, and the
  "Founding price" badge is driven by `PricingPolicy`.

## Manual — founder, not the agent

- App Store Connect: set the three price points.
- Schedule the lifetime price change $99.99 → $149.99 for launch + 60 days.
- Do **not** hardcode a countdown; read the display price from StoreKit.

## Commit

```
feat: reprice Pro to the coaching tier ($79.99/yr) + testable founding-price policy
```
