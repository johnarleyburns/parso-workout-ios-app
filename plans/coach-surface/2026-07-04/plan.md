# Coach Surface — full implementation plan (coach-surface-design.md)

Implements the full design in `coach-surface-design.md` **as amended** (2026-07-03:
insights are continuous; only the "Unlock the Coach" CTA is rate-limited). The
5-state machine (§2) is retained but honored under the amendment — insights are
never suppressed, and the introducing/CTA cadence is what's paced.

## Already shipped (prior commits this cycle)
- `CoachUpsellPolicy` (CadenceCore, pure) — paces the prominent CTA (min 14 days).
- `AppSettings.lastCoachUpsellShown`.
- `CoachPreviewView` rewritten: continuous top insight + single-lock prescription
  panel (redacted action) + real citation titles + rate-limited CTA. (PR-A + the
  amendment's free surface.)
- Free `.coach` route shows the live insights list.

## This phase — the presence system (PR-B/C/D, amended)

### 1. CadenceCore (pure, unit-tested)
- `CoachSurfaceState`: `introducing | ambient | insight | hidden | trial | pro`.
- `CoachSurfacePresenter.state(entitlement:hidden:introImpressions:hasInsight:
  protocolPackPending:)` — pure resolver:
  - pro/trial entitlement overrides everything → `.pro` / `.trial`.
  - else hidden → `.hidden`.
  - else protocolPackPending OR introImpressions < 3 → `.introducing`.
  - else hasInsight ? `.insight` : `.ambient`.
- Reuse `CoachUpsellPolicy` for the CTA within the preview.

### 2. AppSettings
- `coachHidden: Bool` (persisted; UI-test reset).
- `coachIntroImpressions: Int` (persisted; UI-test reset).

### 3. UI
- `CoachRow` (compact ambient/insight surface, ~56pt, single chevron, tinted leaf
  icon). Ambient = "Coach — builds and adjusts your program". Insight form = two
  lines with the live observation. Tap → CoachPreviewScreen. Long-press →
  "Hide Coach offers" / "Learn more". IDs: `coach.row`, `coach.row.insight`.
- `CoachPreviewScreen` (pushed full pitch; tap target of introducing card + row):
  header + promise, capability rows (single Pro pill), THE SCIENCE (real titles),
  "What the Coach noticed" (live insight) + locked "What it would change"
  (redacted prescription), rate-limited "Unlock the Coach" CTA, "Hide Coach
  offers" footer. IDs: `coach.previewScreen`, reuses `coach.preview.unlock`.
- `HomeView` per §6:
  - `pro`/`trial`: full `CoachDecisionCardView` at top (unchanged).
  - `introducing`: `CoachPreviewView` card at top; increments impressions on appear.
  - `ambient`/`insight`: `CoachRow` placed AFTER quick actions + Planned, BEFORE
    What You Did.
  - `hidden`: no Home coach presence.
- `SettingsView`: "Hide Coach offers" toggle (non-Pro only) in the Coach section;
  re-enabling returns to `introducing`.
- `PlanningView` (Programs tab): always-present coach entry row → CoachPreviewScreen
  (reachable in every state, incl. hidden). ID `programs.coachEntry`.

### 4. Tests
- Unit (CadenceCore): `CoachSurfacePresenterTests` — every transition
  (introducing→ambient after 3, hidden, re-enable, entitlement override for
  trial/pro, protocol-pack re-trigger, insight vs ambient). Plus existing
  `CoachUpsellPolicyTests`.
- Integration/e2e (XCUITest, `CoachSurfaceUITests`):
  - free fresh launch → `coach.preview` (introducing) at top; `coach.preview.unlock`
    opens paywall (regression w/ existing MonetizationUITests).
  - Programs tab always has `programs.coachEntry`.
  - Settings has `settings.coach.hideOffers`; toggling hides Home coach presence.
  - pro (`-proUnlocked`) → `coach.card`, no preview.
  - free full log→history loop with zero paywall interruptions (regression).

## Rollout
Single stacked change on main (engine + UI + tests), verified with `swift test`
(reliable gate) and `xcodebuild` UI suite; iterate until CI is green.
