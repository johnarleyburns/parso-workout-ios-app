# Cladiron Revenue Plan — Overview

_Created 2026-07-13. Analysis: `docs/COMPETITIVE-ANALYSIS.md`._

**Audience: an agentic coding model.** Execute phases in order, one branch and one
PR each, merged to `main`. `swift test` is the gate on every phase.

Start here, then read `decisions.md` (locked — do not re-litigate), then the phase
file you are executing. `handoff.md` is the paste-ready prompt that launches the work.

---

## Why this plan exists

Cladiron is feature-complete, fully monetized in code, and **has never been
submitted to the App Store**. Revenue is $0.

Everything needed to take money already ships: StoreKit 2
(`Cadence/Cadence/Store/StoreService.swift`), a three-tier paywall
(`Store/PaywallView.swift`), the onboarding → paywall funnel
(`Features/Onboarding/OnboardingView.swift:37`), trial notifications, and
entitlement resolution with offline caching
(`CadenceCore/Sources/CadenceCore/ProEntitlement.swift`). There is no release
tag; `MARKETING_VERSION` is 1.0 / build 1.

Goal: **$100k+/yr**. The binding constraint is not a feature gap — it is
distribution and price. See `docs/COMPETITIVE-ANALYSIS.md` §2 for the arithmetic;
the short version is that at $34.99/yr the goal needs ~140,000 downloads, and at
$79.99/yr it needs ~61,000.

---

## Phase table

| Phase | File | What | Depends on |
|---|---|---|---|
| 0 | `01-docs-and-positioning.md` | Land the analysis; fix three contradictory monetization stories; GPLv3 App Store exception | — |
| 1 | `02-pricing.md` | Reprice to the coaching tier; extract the founding-price predicate out of a `View` | 0 |
| 2 | `03-correctness-fixes.md` | **Paying subscribers are shown the upsell** (real bug); delete dead `CoachGate` | — |
| 3 | `04-bundled-images.md` | Bundle exercise imagery; make NFR-3 (no-network core) *true* and CI-enforced | — |
| 4 | `05-passive-readiness.md` | **The wedge.** HRV/sleep/RHR from HealthKit, fused with self-report | 0 (citations) |
| 5 | `06-data-durability.md` | iCloud backup/restore of the export blob — kills the data-loss 1-star | — |
| 6 | `07-acquisition-loop.md` | PR timeline, consistency heatmap, shareable PR card | 0 |

Phases 2, 3, and 5 are independent of each other and of 1/4/6 — they may be
reordered if convenient. Do **not** reorder 0 before 1, 4, or 6 (they depend on
its doc and citation changes).

---

## Testing posture — applies to every phase

- **Copious `swift test`. Essentially no new simulator tests.** This is already
  the enforced convention, not a preference.
- `scripts/check-test-pyramid.sh` (CI) enforces three things and will fail the
  build: `CadenceFeatures` may not import SwiftUI / StoreKit / HealthKit / UIKit;
  **≤12 XCUITests total**; a 400-LOC budget per `Features/` file, with a
  shrink-only ratchet for the six grandfathered large views.
- **Every phase pushes logic *down*** into `CadenceCore` (pure) or
  `CadenceFeatures` (headless `@Observable`). **If a fix is tempting to make
  inside a `View`, that is the signal it belongs one layer down.** Phase 2 exists
  precisely because a business rule was written at a SwiftUI call site, where no
  test could reach it — and it shipped a bug that charges paying users an
  advertisement.
- Baseline today: **945 `swift test` tests** (797 `CadenceCoreTests` + 148
  `CadenceFeaturesTests`) and 10 UI smoke tests. Every phase should grow the
  former and none should grow the latter.

**Per-phase gate:**

```sh
cd CadenceCore && swift test
xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build
scripts/check-test-pyramid.sh
scripts/check-no-network.sh    # from Phase 3 onward
```

---

## Out of scope — do not build

- **The Apple Watch app.** Table stakes, and it removes a switching objection —
  but nobody buys a *coaching subscription* because of a Watch app. The plumbing
  already works: `WatchWorkoutManager.swift` runs a real `HKWorkoutSession` and
  relays HR over `WCSession`. The gap is purely the logging UI —
  `Cadence Watch App/ContentView.swift` is still the Xcode "Hello, world!"
  template and is not even referenced. Post-launch, funded by revenue.
- **Launch execution** — TestFlight, the App Store Connect listing, the Apple
  featuring nomination, the USPTO word-mark filing. Founder manual steps, not
  agent work.
- **Paid UA, Android, a social feed, nutrition, analytics/telemetry SDKs.**

---

## Definition of done for the whole plan

- No file in the repo claims the Coach is free.
- No runtime network fetch anywhere in the app or core — and a CI guardrail keeps
  it that way.
- Paying subscribers never see an upsell.
- The coach reads HRV, sleep, and resting HR, and cites a paper for every claim
  it makes about them.
- A lost phone no longer means a lost training log.
- There is exactly one honest, zero-privacy-cost way for a user to show the app to
  a friend.
