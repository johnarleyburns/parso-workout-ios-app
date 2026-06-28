# Supporter / Contributions Flow — Overview

_Plan only. No code is implemented by this document._
_Date: 2026-06-28 · Topic: port the "supporter" (tip-jar) contribution flow from `../parso-radio-ios-app` (Lorewave) into Cladiron (Cadence)._

## 1. Problem / goal

Cladiron is free, open-source, no accounts, no ads. We want an **optional, non-nagging
way for users to contribute** (a one-time "tip jar"), mirroring what the Parso Radio app
(Lorewave) already ships. The bar:

- One-time **consumable** in-app purchases (StoreKit 2), no subscriptions.
- A **persistent Support screen** reachable from Settings.
- A **gentle, engagement-gated prompt** ("toast") that appears at most rarely, is easy to
  dismiss, and can be turned off forever.
- **Dormant by default**: if no products are configured in App Store Connect, the UI shows
  a friendly placeholder and the prompt never fires (so shipping the code is safe before
  the ASC products exist).
- Pure decision logic is **unit-tested in `CadenceCore`** (`swift test`), matching this
  repo's "logic in the package, thin UI on top" rule.

## 2. What the radio app does (source of truth)

Files in `../parso-radio-ios-app`:

| File | Role |
|---|---|
| `ParsoRadio/Core/Services/Contributions/ContributionStore.swift` | StoreKit 2 layer: loads consumable products, `purchase()`, `restore()`, `Transaction.updates` listener, persists `everContributed`/`isSupporter` in UserDefaults. |
| `ParsoRadio/Core/Services/Contributions/ContributionPromptEngine.swift` | **Pure** decision logic (`shouldPrompt(Inputs) -> Bool`). No UI/StoreKit/IO. Fully unit-tested. |
| `ParsoRadio/Core/Services/Contributions/ContributionCoordinator.swift` | Owns the prompt lifecycle: engagement counters in UserDefaults, calls the engine, drives `showToast`, `dismissToast`/`optOutForever`, `beginSession()`, static `recordTrackPlayed()`. |
| `ParsoRadio/Views/ContributionToast.swift` | Dismissible bottom card: **Support / Maybe later / Don't ask again**. |
| `ParsoRadio/Views/ContributionSupportView.swift` | The Support screen: thank-you vs pitch, product rows, Restore Purchases, placeholder when no products. |
| `ParsoRadio/Views/SettingsView.swift` (§ lines 55–74) | Settings row → Support screen + "Supporter — Thank You" state + optional badge toggle. |
| `ParsoRadio/App/ParsoRadioApp.swift` (lines 29, 63–64, 159–184) | Wiring: builds the store + coordinator, `beginSession()` in `.task`, `evaluate()` on `scenePhase == .active`, toast `.overlay(alignment: .bottom)`, support `.sheet`. |
| `ParsoRadio.storekit` | Local StoreKit config (3 consumables) for simulator/sandbox testing. |
| `ParsoRadio/Core/Tests/ContributionPromptEngineTests.swift` | Unit tests for the engine. |
| `ParsoRadio/ViewModels/PlayerViewModel.swift:1232` | Engagement signal: `ContributionCoordinator.recordTrackPlayed()` per track. |

### Engine rules (from `ContributionPromptEngine`)
- Never if `optedOut` or `isSupporter`.
- Never on the first session; at most **once per session**.
- Only after engagement: `tracksPlayed ≥ 12` **and** `sessionCount ≥ 2`.
- After any prompt, snooze **both** `≥ 7 days` **and** `≥ 5 launches` before re-asking.

### Product IDs (radio)
`guru.parso.tip.small` ($1.99), `guru.parso.tip.medium` ($4.99), `guru.parso.tip.generous` ($9.99) — all **consumable**.

## 3. Key differences Cladiron must adapt

| Concern | Radio (Lorewave) | Cladiron (Cadence) — adaptation |
|---|---|---|
| State/DI framework | `ObservableObject` + `@Published` + `@StateObject`/`@EnvironmentObject`; `AppDependencies` container | **Observation framework**: `@Observable` classes injected via `.environment(...)` (see `CadenceApp.swift`, `AppModel`/`AppSettings`/`ActiveWorkoutModel`). No deps container. |
| Testable logic location | `ParsoRadio/Core/...` + `Core/Tests` | **`CadenceCore` Swift package** (`swift test`). The pure engine + its tests go here. |
| App entry | `ParsoRadioApp.swift` WindowGroup | `CadenceApp.swift` WindowGroup → `RootTabView()`. |
| Engagement signal | per **track played** | per **workout completed** (strength finished / cardio saved / logged). |
| Settings | `SettingsView.swift` Support section | `SettingsView.swift` — **append a new Section at the very bottom** (repo convention §06: appended sections keep existing coordinate-tap UI-test offsets). |
| Bundle id / team | `guru.parso.lorewave.*` (radio) | `guru.parso.ios-workout-app`, team `3264Y8YUGV`. |
| Product IDs | `guru.parso.tip.*` | Use **app-scoped** IDs to avoid clashing with the radio app's products in the same developer account, e.g. `guru.parso.cladiron.tip.small/medium/generous`. |
| Copy / framing | "hosting, copyright/DMCA … 10% to Internet Archive" | Cladiron has no hosting/DMCA. Reframe as **"supports continued development"**. The Internet-Archive donation line does **not** apply — drop it (see decision D3). |
| About copy | n/a | `AboutView.swift:84` currently says *"No subscriptions, no ads, no upsells."* A tip jar is not an upsell, but reconcile the wording (decision D4). |
| Privacy posture | — | Cladiron ships `PrivacyInfo.xcprivacy` = **Data Not Collected**. IAP keeps that valid (nothing leaves the device; only a local `everContributed` bool). Re-confirm the ASC privacy questionnaire (manual step M9). |

## 4. Target architecture (Cladiron)

```
CadenceCore (pure, swift test)
└── ContributionPromptEngine.swift        # ported verbatim (rename tracks→workouts)
    └── Tests/.../ContributionPromptEngineTests.swift

Cadence app target
├── App/ContributionStore.swift           # @Observable StoreKit 2 layer
├── App/ContributionCoordinator.swift      # @Observable toast lifecycle + counters
├── Features/Settings/ContributionSupportView.swift   # Support screen
├── Features/Settings/ContributionToast.swift          # bottom card
├── Features/Settings/SettingsView.swift   # + appended "Support" section
├── Features/Settings/AboutView.swift      # copy reconciliation (D4)
├── CadenceApp.swift                       # build store+coordinator, inject, toast overlay, support sheet, beginSession/evaluate
└── (engagement hook) HomeView.swift / completion callbacks  # recordWorkoutCompleted()

Cadence.storekit                            # local StoreKit config for testing
```

Detailed file-by-file proposals: **`01-code-changes.md`**.
Exact App Store Connect + Xcode steps: **`02-manual-steps.md`**.

## 5. Decision sheet (needs your answers before implementing)

- **D1 — Product tiers & prices.** Keep three consumables at $1.99 / $4.99 / $9.99? Or
  different tiers? Display names (e.g. "Buy us a coffee" / "Supporter" / "Patron")?
- **D2 — Engagement gate values.** Radio uses `minWorkouts(tracks)=12`, `minSessions=2`,
  snooze `7 days`/`5 launches`. For a workout app, 12 *completed workouts* is ~2–4 weeks of
  training. Keep 12, or lower (e.g. 6) since workouts are higher-effort than track plays?
- **D3 — Charity line.** Radio donates 10% to the Internet Archive. Cladiron has no
  equivalent. Confirm we **drop** the donation framing (recommended), or pick a cause.
- **D4 — About copy.** `AboutView` says "no upsells." Reword to something like "no ads, no
  subscriptions — an optional tip jar if you want to support development." Approve wording.
- **D5 — Supporter badge.** Radio shows an optional "Supporter" badge on Now Playing. Does
  Cladiron want a badge anywhere (e.g. on Home or About)? If not, drop the badge toggle.
- **D6 — Prompt placement.** Toast as a bottom card over the tab bar (radio pattern). OK to
  surface it app-wide from `CadenceApp`, evaluated on `scenePhase == .active`?
- **D7 — Product ID namespace.** Confirm `guru.parso.cladiron.tip.*` (recommended) vs reusing
  the radio IDs (not recommended — IDs are unique per app in ASC, can't be shared).

Record answers verbatim in a `decisions.md` here once settled, then implement per
`01-code-changes.md` in a single branch + PR.

## 6. Rollout (one PR)

This is small enough for **one branch/PR**:
1. CadenceCore: add `ContributionPromptEngine` + tests; `swift test` green.
2. App: add `ContributionStore`, `ContributionCoordinator`, `ContributionToast`,
   `ContributionSupportView`; wire into `CadenceApp`; add Settings section; engagement hook.
3. Add `Cadence.storekit`; enable it in the Run scheme for local testing.
4. Verify: `swift test` + `xcodebuild` build + manual sandbox purchase on device.
5. Manual ASC setup (`02-manual-steps.md`) can proceed in parallel; the code ships dormant
   until products are live.
