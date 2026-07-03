# Cladiron Monetization Plan — Implementation Handoff

Status: APPROVED — ready for agent implementation
Repo: parso-workout-ios-app (internal codename Cadence; user-visible name Cladiron — never rename internals)
Audience: coding agent (§4–§7) + founder manual steps (§8)

## Decision log (final)

| # | Decision | Value |
|---|---|---|
| 1 | License | Relicense MIT → GPLv3 |
| 2 | Lifetime price | $69.99, launch intro $49.99 (first 60 days) |
| 3 | Trial | 30 days (1-month intro offer), annual plan only |
| 4 | Tier boundary | **Everything free except the coach.** Partner workouts, tracker, analytics history — all free. App must be 100% usable forever without the coach. Coach = the sole upsell, with quarterly updates from current strength/fitness research |
| 5 | Annual / monthly | $34.99/yr (default-selected) / $4.99/mo (no trial) |

---

## 1. Product principle (binding, cite in PRs)

> The free app is complete. The coach is an expert addition, not a crippled-app unlock.

- No tracker/logging/analytics/social feature is ever gated. Nothing ever migrates free → paid.
- CSV / full data export: free, forever.
- The only gated surface is the Coach: program generation, autoregulation (RIR-based load/volume adjustment, deload detection), adaptation guidance, "why this set" citation rationale, and quarterly protocol packs.
- Coach tab remains **visible** in free with a live preview (program structure shown, day-to-day coaching locked) — the preview *is* the paywall funnel.

## 2. Products & pricing

| Product | Type | Product ID | Price | Offer |
|---|---|---|---|---|
| Pro Annual | Auto-renewable | `cladiron.pro.annual` | $34.99/yr | Intro offer: 1 month free trial |
| Pro Monthly | Auto-renewable | `cladiron.pro.monthly` | $4.99/mo | none |
| Pro Lifetime | Non-consumable | `cladiron.pro.lifetime` | $49.99 launch → $69.99 (scheduled price change at day 60) | — |

Prefix product IDs with the app's bundle ID convention if the repo already uses reverse-DNS IDs elsewhere; otherwise use exactly the IDs above. Both subscriptions live in one subscription group ("Cladiron Pro") at the same service level (they unlock identical entitlements; group exists so users can crossgrade annual↔monthly).

Competitive positioning check (do not change without founder sign-off): annual undercuts Fitbod (~$96/yr) ~3x; lifetime undercuts Hevy ($74.99) and Strong ($99.99); intro lifetime $49.99 is the cheapest lifetime of any serious app in the category.

Notes:
- Non-consumables cannot have App Store "introductory offers" — the $49.99 intro is implemented as the launch price with a **scheduled price change** to $69.99 (manual step §8.4). In-app copy may say "Founding price — $49.99 (goes to $69.99 soon)"; do not hardcode a countdown, read the display price from StoreKit.
- Trial abuse is handled by Apple: one intro offer per Apple ID per subscription group. No code needed.
- Family Sharing: enable for `pro.lifetime` and `pro.annual` (manual step; code must honor `Transaction.ownershipType == .familyShared`).
- If a user with an active subscription buys lifetime: allowed; show a post-purchase notice "You can cancel your subscription in Settings → Apple ID → Subscriptions — Lifetime now covers you." Do not attempt programmatic cancellation (impossible).

## 3. Monetization architecture overview

- **StoreKit 2 only.** No RevenueCat, no third-party SDKs, no server. On-device JWS verification via `VerificationResult`. This is a brand requirement (privacy: "Data Not Collected"), not a shortcut.
- Entitlement is derived exclusively from `Transaction.currentEntitlements` — never persisted as a plain UserDefaults bool that could drift (caching for offline is fine, see §4.3).
- Coach knowledge base is versioned in-repo and ships with the app; quarterly "protocol pack" releases are app updates that bump the KB version and surface a changelog (§6).

---

## 4. Agent implementation spec

### 4.0 Preconditions
- Read the repo's existing feature-flag system (Liquid Glass work introduced conditional flags) and follow the same patterns.
- All new code SwiftUI + Swift Concurrency, matching existing style. No new dependencies.

### 4.1 Relicense to GPLv3 (first PR, standalone)
1. Replace `LICENSE` contents with the verbatim GNU GPLv3 text from gnu.org/licenses/gpl-3.0.txt.
2. Add `TRADEMARKS.md`:
   - "Cladiron" name, app icon, and brand assets are trademarks of John Arley Burns / Parso and are **not** licensed under the GPL. Forks must use their own name and icon.
3. README changes:
   - License badge/section → GPLv3, link to LICENSE and TRADEMARKS.md.
   - Add positioning paragraph: open source so users can verify no tracking/telemetry; App Store purchase funds development.
   - Fix any stale content encountered (LLM-README is known to have stale sections).
4. Do NOT add SPDX headers to every file (noise); a top-level LICENSE is sufficient for a sole-author repo.

### 4.2 StoreService (StoreKit 2)
New file `Store/StoreService.swift`, an `actor` (or `@MainActor @Observable` class if the app's DI pattern prefers it):

- `func loadProducts() async` — `Product.products(for:)` with the three IDs; cache; expose `annual`, `monthly`, `lifetime` and their `displayPrice` / intro offer info (`product.subscription?.introductoryOffer`).
- `func purchase(_ product: Product) async throws -> PurchaseOutcome` — handle `.success(let verification)` (verify, finish), `.userCancelled`, `.pending` (Ask to Buy: surface "pending approval" state).
- Transaction listener started at app launch: `for await result in Transaction.updates` → verify → update entitlement → `transaction.finish()`.
- `func refreshEntitlement() async` — iterate `Transaction.currentEntitlements`; Pro if any verified transaction matches the three product IDs and (for subscriptions) `revocationDate == nil` and not expired. Record source: `.lifetime`, `.subscription`, `.trial` (trial when `transaction.offer?.type == .introductory`).
- `func restore() async` — `try await AppStore.sync()` then refresh. Wire to a visible "Restore Purchases" button (App Review requirement).
- Verification helper: reject unverified transactions; log locally only (no network).

### 4.3 Entitlement model & gating
`Store/ProEntitlement.swift`:

```swift
enum ProEntitlement: Equatable {
    case free
    case pro(source: ProSource)   // .lifetime, .subscription, .trial
}
```

- Injected via Environment (`@Entry var proEntitlement`) or the app's existing DI container — single source of truth, observed app-wide.
- **Offline behavior (critical for a local-first app):** StoreKit 2 caches entitlements on-device, so `currentEntitlements` works offline. Additionally persist the last-known entitlement + timestamp (UserDefaults is acceptable *as a cache only*) and use it if StoreKit is momentarily unavailable at cold launch, with a 30-day staleness ceiling for subscription-sourced Pro (lifetime never goes stale). Never let a network blip lock a paying user out mid-workout.
- Gating: exactly one gate component, e.g. `CoachGate { CoachView() } locked: { CoachPreviewView() }`. Grep the codebase for every Coach entry point (Coach tab, program generation CTAs, "why this set" affordances, adaptation dashboard coach panels) and route all through `CoachGate`. **Do not gate:** logging, history, analytics/Progress tab, partner workouts, export, watch app features.
- Watch app: coach-driven in-workout guidance follows the same entitlement, synced via the existing phone↔watch channel; watch never shows a paywall, it shows "Unlock the Coach on your iPhone."

### 4.4 Paywall
`Store/PaywallView.swift`, presented as a sheet from CoachPreviewView and post-onboarding:

- Three options; **annual pre-selected** with "30 days free" badge; lifetime shows StoreKit displayPrice with "Founding price" tag while price < $69.99 (compare against a constant, or just always show displayPrice + static founding copy until the day-60 update removes it).
- Copy hierarchy: (1) what the Coach does — generates your program, adjusts every set to your logged performance, cites the research; (2) quarterly research updates included; (3) "Everything else in Cladiron is free forever. No ads. No account. No tracking. Open source."
- Required elements: price + renewal terms per Apple guidelines, Restore Purchases, links to Privacy Policy and Terms of Use (Apple standard EULA link is acceptable), all reachable pre-purchase.
- Trial UX: after trial starts, Coach header shows "Trial — X days left" quietly; one local notification 3 days before trial end summarizing what the coach adjusted for them (value receipt, not a nag). No other trial nagging.
- **Onboarding funnel (highest-leverage screen):** after the goals/equipment/schedule questionnaire, generate and display the real program structure (weeks, days, exercise slots) unlocked; the "Start training with the Coach" CTA opens the paywall. ~50% of all conversions industry-wide happen in the first session — the user must see their actual program before the paywall, in that session.

### 4.5 Coach preview (free tier surface)
`CoachPreviewView`: shows the generated program skeleton, 2–3 unlocked sample citations ("why this set" teasers on real exercises), and locked rows for autoregulation/adaptation. This view is the primary organic conversion surface; treat it as a first-class screen, not an ad.

### 4.6 Knowledge base versioning & changelog
- Add `CoachKB/version.json` (semver + release date + human changelog entries with citation references).
- New settings/coach surface: "Coach research updates" — renders changelog history; badge on Coach tab when KB version increases after an app update (Pro and free both see the changelog; free sees it as paywall reinforcement).
- Quarterly protocol pack = PR bumping KB content + version + changelog. Document this release process in `plans/` or `docs/RELEASING.md`.

### 4.7 Testing
- Add a `.storekit` configuration file mirroring §2 exactly (prices, 1-month trial on annual) for local/CI testing.
- Unit tests: entitlement derivation (lifetime, active sub, trial, expired sub, revoked/refunded, familyShared), offline cache staleness logic, gate routing.
- UI tests: paywall renders all three products; restore button present; free user can complete a full log→history→export loop with zero paywall interruptions (regression test for the §1 principle).
- Manual test matrix (document in PR): sandbox purchase each product, trial start/cancel, refund via sandbox, Ask to Buy pending, family shared account, airplane-mode cold launch as subscriber.

### 4.8 Out of scope for the agent (do not implement)
- Any analytics/telemetry SDK. Conversion measurement comes from App Store Connect (§8.7).
- Server-side receipt validation, webhooks, App Store Server Notifications (no server exists).
- Promo codes / offer codes UI (can add later; ASC supports offer codes without code changes for subscriptions via redemption sheet — optional `presentOfferCodeRedeemSheet` can be added in a follow-up).
- Android, web checkout, external purchase links.

---

## 5. Suggested PR sequence

1. **PR1 — Relicense** (§4.1). Zero code risk, unblocks publicity.
2. **PR2 — StoreService + entitlement + tests** (§4.2–4.3, 4.7 units). No UI.
3. **PR3 — Gates + Coach preview** (§4.3 gating, 4.5). App fully functional free.
4. **PR4 — Paywall + onboarding funnel + trial notification** (§4.4).
5. **PR5 — KB versioning/changelog** (§4.6).
6. **PR6 — StoreKit config file + UI tests + manual test matrix doc** (§4.7).

---

## 6. Quarterly protocol pack cadence (founder process)

- Q-cycle: review new meta-analyses/RCTs in strength & hypertrophy (MASS Research Review, Stronger by Science, PubMed alerts) → update KB rules/citations → changelog → app update.
- Each pack doubles as a long-form article on parso.guru (the owned-audience engine) and the App Store "What's New" text.
- Minimum bar per pack: 1 programming-logic improvement + 3 new/updated citations. If a quarter has nothing worth shipping, say so honestly in the changelog rather than padding — the credibility *is* the product.

---

## 7. Success metrics (no telemetry — App Store Connect only)

| Metric | Source | Target |
|---|---|---|
| Install → trial start | ASC Analytics (aggregated, opt-in users) | ≥8% |
| Trial → paid | ASC Subscription reports | ≥30% (30-day trials benchmark ~42.5% median) |
| Annual share of revenue | ASC Sales | ≥60% |
| Lifetime attach | ASC Sales | informational |

Gates: Day 90 <500 installs → distribution problem, shift to content/ASO. Month 6 trial→paid <15% → rework onboarding-to-first-coached-workout. Month 12 <$5k total → maintenance mode, keep as brand/audience asset.

---

## 8. MANUAL STEPS — founder, App Store Connect & legal

Do these in order. §8.1–8.2 before PR2 sandbox testing; §8.3–8.6 before release submission.

### 8.1 Agreements & banking (blocks everything)
1. App Store Connect → Business (Agreements, Tax, and Banking): accept the **Paid Applications Agreement**.
2. Enter banking (business account for the Parso entity) and complete US tax forms (W-9 as US entity). Status must show "Active" before paid IAPs can be created/tested meaningfully.

### 8.2 Create the in-app purchases
1. ASC → your app → **Monetization → Subscriptions** → Create Subscription Group: name `Cladiron Pro`.
2. Inside the group, create:
   - `cladiron.pro.annual` — Auto-Renewable, duration 1 year, price $34.99 (USD base; accept Apple's automatic worldwide equalization — do not hand-tune regions at launch).
     - Add **Introductory Offer**: type Free Trial, duration **1 month**, all countries, no end date.
   - `cladiron.pro.monthly` — Auto-Renewable, duration 1 month, price $4.99. No intro offer.
3. ASC → **Monetization → In-App Purchases** → create `cladiron.pro.lifetime` — Non-Consumable, price **$49.99**.
4. For each of the three: add localization (display name + description; en-US minimum — display names: "Cladiron Pro — Annual", "Cladiron Pro — Monthly", "Cladiron Pro — Lifetime"), and upload a **review screenshot** (screenshot of the paywall; can be from simulator; required before IAP review).
5. Enable **Family Sharing** on `cladiron.pro.lifetime` and `cladiron.pro.annual` (product page toggle — irreversible, this is intended).
6. Subscription group localization: group display name "Cladiron Pro".

### 8.3 Sandbox testing setup
1. ASC → Users and Access → **Sandbox Testers**: create 2–3 sandbox Apple IDs.
2. On a test device: Settings → Developer → Sandbox Apple Account (iOS 18+ path may differ slightly) → sign in with a sandbox tester.
3. Run the manual test matrix from PR6 (purchase each product, cancel trial, refund via sandbox subscription management, Ask to Buy).

### 8.4 Schedule the lifetime price change ($49.99 → $69.99)
1. After launch date is known: ASC → `cladiron.pro.lifetime` → Pricing → **Plan a Price Change** → new price $69.99, start date = launch + 60 days, all countries.
2. Calendar reminder for launch+55d: verify the change is still scheduled and ship the app update that removes "Founding price" copy (agent follow-up task).

### 8.5 App submission metadata
1. **App Privacy**: answer the questionnaire as **Data Not Collected** (accurate: no telemetry, no accounts; StoreKit purchases are Apple-collected, not developer-collected). This label is a marketing asset — screenshot it for the website.
2. Privacy Policy URL: publish a short policy at parso.guru (states: no data collected, purchases handled by Apple, iCloud sync is user's private CloudKit). Required field.
3. EULA: use Apple's standard EULA (default; link it from the paywall).
4. Screenshots: lead with (a) adaptation dashboard, (b) "why this set" citation UI, (c) paywall-free logging flow with "Free forever" caption, (d) watch logging.
5. Subtitle/keywords ASO targets: "private workout tracker", "no ads workout log", "science based strength coach", "evidence based training".
6. App Review notes: explain the free/Pro split, that no account exists, and steps to reach the paywall (onboarding → program → CTA). Attach a demo video link if review friction occurs.
7. Ensure the three IAPs are attached to the app version and submitted **with** the binary (first IAP submission must accompany an app version).

### 8.6 Legal
1. **Trademark**: file USPTO word mark "Cladiron", Class 9 (downloadable software) — TEAS Standard ~$350/class; add Class 41 (fitness training services) only if budget allows. DIY is feasible; an attorney (~$500–1000) reduces office-action risk. This is what enables copycat takedowns; file at or before launch.
2. Confirm no external code contributions were merged pre-relicense (if any exist, get contributor consent for GPLv3 or rewrite those hunks — as sole author to date this should be a non-issue, verify with `git shortlog -sne`).

### 8.7 Post-launch monitoring (weekly, 15 min)
1. ASC → Trends: installs, trial starts.
2. ASC → Subscription reports: trial conversion, active subs, churn.
3. Payments: verify first payout cycle completes (~33 days after fiscal month end).

---

## 9. Non-goals (unchanged, binding)
No ads ever. No paid UA at launch. No Android. No social feed. No accounts. No third-party SDKs.
