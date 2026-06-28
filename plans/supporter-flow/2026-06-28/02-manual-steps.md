# Supporter Flow — Exact Manual Steps (App Store Connect + Xcode)

_Plan only. Do these once the code in `01-code-changes.md` is implemented (or in parallel —
the code ships dormant until the products exist). Paths reflect App Store Connect / Xcode as
of mid-2026; labels may shift slightly._

Team: **3264Y8YUGV** · App bundle id: **guru.parso.ios-workout-app** · Product IDs:
**guru.parso.cladiron.tip.small / .medium / .generous** (all **Consumable**).

---

## M1 — Prerequisite: Paid Applications Agreement (BLOCKER)
In-app purchases **do not load** until this is in place — `Product.products(...)` returns
empty and the Support screen shows the placeholder.

1. App Store Connect → **Business** (formerly "Agreements, Tax, and Banking").
2. Sign the **Paid Applications** agreement (Apple Developer Program account holder must do this).
3. Add **Bank account** (Payments/Banking) and complete **Tax** forms (US: W-9; plus any
   regions you'll sell in).
4. Wait until the Paid Applications agreement status is **Active**. (Can take minutes–days.)

> If you only see "Free Applications" active, IAP will silently fail. This is the most common
> "products won't load" cause.

## M2 — Confirm the App ID supports In-App Purchase
- IAP is enabled by default for every App ID; **no entitlement** is required and nothing in
  `Cadence.entitlements` changes.
- With automatic-signing this is automatic. (Cladiron uses **Manual** signing for Release —
  the existing "Parso Workout App Store" provisioning profile already covers IAP; no profile
  change needed for consumables.)
- Sanity check: Apple Developer portal → Identifiers → `guru.parso.ios-workout-app` → ensure
  **In-App Purchase** is checked (it is, by default).

## M3 — Create the three Consumable products
App Store Connect → **My Apps → Cladiron → (left sidebar) In-App Purchases → Manage** →
**+** for each product:

For **each** of the three:
1. Type: **Consumable** → Create.
2. **Reference Name** (internal): `Cladiron Small Tip` / `Cladiron Supporter Tip` / `Cladiron Patron Tip`.
3. **Product ID** (must match code exactly):
   - `guru.parso.cladiron.tip.small`
   - `guru.parso.cladiron.tip.medium`
   - `guru.parso.cladiron.tip.generous`
4. **Price**: pick the price points (≈ $1.99 / $4.99 / $9.99 — or the tiers from decision D1).
5. **Localization (English, U.S.)** — Display Name + Description (these are shown by StoreKit
   in the app):
   - small → "Buy us a coffee" / "A small thank-you that supports Cladiron's development."
   - medium → "Supporter" / "Support continued development of this free, open-source coach."
   - generous → "Patron" / "A generous contribution to keep Cladiron free, open-source, and independent."
6. **Review screenshot** (required to submit): a 640×920+ PNG of the **Support Cladiron**
   screen showing the tiers. Capture it from the simulator once the UI is built (M7).
7. **Review notes**: *"Optional one-time tip. Unlocks no features or content — the app is
   fully functional without any purchase. Used to support development of a free, open-source app."*
8. Save. Status will be **"Ready to Submit"**.

> Consumables are reviewed **together with an app version**. The first time, you attach them to
> the next app submission (M8). They go live when that version is approved.

## M4 — Copy / policy guardrails (so Review passes)
- Frame every tier as a **tip / support**, never a "donation." Apple disallows calling a
  commercial consumable a "donation" unless it routes to an Apple-approved nonprofit and meets
  Guideline 3.1.1(b). We dropped the charity angle (decision D3), so "tip"/"support" is correct.
- **Do not gate any functionality** behind the purchase (Guideline 3.1.1). The app must be
  100% usable without buying. (The proposed code only flips a cosmetic `isSupporter` flag.)
- **No external payment links** for the tip (must use StoreKit IAP). Don't link to PayPal/Ko-fi
  for this in-app flow.
- Keep the optional **"Don't ask again"** path (already in the toast) — good-faith UX Apple likes.

## M5 — App Privacy questionnaire (keep "Data Not Collected")
ASC → Cladiron → **App Privacy**.
- The tip jar does **not** change your posture: purchase processing is handled by Apple; the
  app stores only a local `everContributed` boolean in UserDefaults and transmits nothing.
- You may keep **Data Not Collected**. Do **not** check "Purchases" under data collection
  unless you start sending purchase data off-device (you don't).
- This stays consistent with the shipped `PrivacyInfo.xcprivacy` (Data Not Collected).

## M6 — Add the local StoreKit config file to the Xcode project
1. Create `Cadence/Cadence.storekit` (content table in `01-code-changes.md` §G).
2. In Xcode: **File → Add Files to "Cadence"…**, select `Cadence.storekit`, add it to the
   **Cadence** target's project (it's a debug config, not a shipped resource).
3. Fill in the three consumables with the **exact** product IDs above.

## M7 — Enable the StoreKit config in the Run scheme (for simulator testing)
1. Xcode → **Product → Scheme → Edit Scheme… → Run → Options**.
2. **StoreKit Configuration** → select `Cadence.storekit`.
3. Run on a simulator. Now Settings → **Support Cladiron** shows live tiers and purchases
   succeed locally (no ASC needed). Capture the **review screenshot** here for M3.6.
4. Test: buy each tier → "Supporter — Thank You"; verify the engagement toast no longer
   appears once `isSupporter`; verify "Don't ask again" persists across launches; with the
   StoreKit config **deselected**, verify the placeholder ("Support options aren't available
   yet").

## M8 — Sandbox testing on a real device (pre-submission)
1. ASC → **Users and Access → Sandbox → Test Accounts → +** — create a sandbox Apple Account
   (use a fresh email alias; not your real Apple ID).
2. On the test device: **Settings → Developer → Sandbox Apple Account** (or sign in when the
   purchase sheet prompts). Do **not** sign your real Apple ID into Sandbox.
3. Build a Debug/TestFlight build **with the StoreKit config OFF** (so it hits real
   sandbox StoreKit, not the local file) and confirm:
   - Products load (requires M1 Active + M3 products created).
   - A sandbox purchase completes and `isSupporter` becomes true.
   - "Restore Purchases" runs without error.
4. Consumables can be re-purchased repeatedly in sandbox.

## M9 — Submit for review
1. Implement + verify the code (`swift test`, `xcodebuild`), commit, and create the app
   version in ASC as usual.
2. In the version page, under **In-App Purchases**, **attach all three** consumables to this
   version (first submission only — afterwards they stay live).
3. In **App Review Information → Notes**, add: *"The three in-app purchases are optional tips
   that support development. They unlock no features; the app is fully functional without
   them. Screenshots of the Support screen are attached to each IAP."*
4. Submit. The IAPs are reviewed alongside the build.

## M10 — Post-approval
- Verify on the live App Store build that tiers load and purchases work for a real account.
- (Optional) mention the tip jar in the App Store "What's New" and in `README.md` /
  `current_state.md`.

---

## Quick checklist
- [ ] M1 Paid Apps agreement **Active** + banking + tax (BLOCKER)
- [ ] M3 Three consumables created with exact product IDs + localizations + review screenshot
- [ ] M4 Copy says "tip/support", no gated features, no external pay links
- [ ] M5 App Privacy still "Data Not Collected"
- [ ] M6/M7 `Cadence.storekit` added + selected in Run scheme; review screenshot captured
- [ ] M8 Sandbox tester created; on-device sandbox purchase verified
- [ ] M9 IAPs attached to the app version + review notes; submitted
- [ ] M10 Live verification

## Gotchas
- **Products empty?** 99% of the time it's M1 (Paid Apps agreement not Active) or a
  product-ID typo vs `ContributionStore.productIDs`.
- **`.storekit` file selected in scheme** ⇒ you're testing the *local* config, not sandbox.
  Turn it **off** for true sandbox testing (M8).
- Don't sign your **real** Apple ID into Sandbox — it can lock the account out of sandbox.
- Consumables won't appear in `Transaction.currentEntitlements` after `finish()`; the local
  `everContributed` bool is the source of truth for supporter state (by design).
