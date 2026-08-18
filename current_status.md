# Current Status

Updated: 2026-08-18

## Phase 2 complete — Home's vertical rhythm on the workout surfaces

Field test 2026-08-18 issue #5. Workout Plan, Start Workout and Workout now read
their vertical rhythm from `LayoutMetrics` instead of three hand-tuned stacks:
**20** between sections, **16** page and card padding, **12** between rows in a
card, **10** between a card heading and its first row.

What changed:

- `WorkoutPlanEditor` is no longer a `List` (decision **D14**) — it is a
  `ScrollView` + `VStack(spacing: sectionSpacing)` of glass cards, so it can
  actually honour the rhythm. Split for the 400-LOC budget into
  `WorkoutPlanEditor.swift` (213), `WorkoutPlanPartnerSection.swift` (174) and
  `WorkoutPlanExerciseSection.swift` (91). `workoutPlanCard()` applies Home's
  card treatment.
- Leaving `List` costs swipe-to-delete, so each set row gains an explicit
  destructive `minus.circle.fill` button (`editor.removeSet.<name>.<index>`),
  disabled at one remaining set. Set rows are bound by set **id**, not index, so
  a delete can never leave a row bound to a stale slot.
- `Add Exercise` and `Show workout settings…` become secondary
  `CadenceActionButton`s; `Start Workout` loses its ad-hoc insets and takes the
  page padding like every other child.
- The dead reorder handle (`line.3.horizontal`, never wired to `.onMove`) is
  gone rather than shipped as a dead affordance.
- `SelectWorkoutView` groups Strength and Cardio into Home-style glass cards;
  outer spacing 22 → 20, group spacing 10 → 12, `.padding()` → `pagePadding`.
- `SessionView` outer spacing 16 → 20, `.padding()` → `pagePadding`, and the
  ad-hoc `.padding(.top, 16/8/4)` on its top-level children are gone.
- `CompactExerciseRow` no longer wraps itself in a `Section` (it had no `List`
  left to be in); the caller applies the card.

Verified visually against Home: the new cards use the same tint and saturation
Home's `Workouts Today` / `This Week` cards already use.

### Verification (Phase 2)

- `make ci`: build + **1,330 tests passed, 0 failures** (the new
  `testWorkoutSurfacesShareHomeSectionSpacing`), guardrails OK.
- `make smoke`: WatchConnectivity activation regression **passed**, iPhone smoke
  **passed**, including the new `editor.partners` card assertion and the Phase 1
  height assertions.
- Ratchet lowered in `scripts/check-test-pyramid.sh`: `SessionView.swift`
  1089 → **1085**.
- Not pushed, per the batch execution protocol.

<details>
<summary>Phase 1 — uniform full-width action buttons (shipped, bdc7a83)</summary>

Shipped `feat: single full-width action button geometry` (field test 2026-08-18
issue #3). `LayoutMetrics` (CadenceFeatures, Foundation-only) is now the single
source of truth for action-button height/corner/spacing and Home's page rhythm;
`CadenceActionButton` + `cadenceActionLabel()` apply it.

What changed:

- New `CadenceCore/Sources/CadenceFeatures/LayoutMetrics.swift` — action button
  height 56, corner 16, stack spacing 12; section 20 / page 16 / card row 12 /
  card heading 10 / card padding 16.
- New `Cadence/Cadence/Shared/CadenceActionButton.swift` — the one full-width
  action control, plus `cadenceActionLabel()` for `NavigationLink` labels that
  keep their gradient/glass fill, and `CadenceActionShape`.
- Call sites normalized to 56 pt / `.headline`: Home `Start Workout` +
  `Log Previous Workout`, Start Workout sheet `Quick Start` / `Custom Workout` /
  `Coach's Workout`, `WeightsStartView` `Coach's Workout` / `Quick Start`,
  plan editor `Start Workout`, `Do Coach's Workout`, SessionView
  `Use Previous Workout` / `Add Exercise` / `Done`, and the pre-workout HR
  `Continue` action. All accessibility identifiers are unchanged.

**Deviation from the phase file (deliberate, verified by the smoke test):**
`CadenceActionButton` draws its own fill instead of using
`.borderedProminent`/`.bordered`. Those styles add ~7 pt of their own vertical
padding *on top of* a `minHeight`, so a bordered button rendered 70 pt while a
gradient hero label with the same declared height rendered 56 pt — the smoke
test's new height assertion caught exactly that. Owning the fill makes
`LayoutMetrics.actionButtonHeight` the real rendered height everywhere and
delivers the 16 pt corner radius the phase design specifies.

**Out of scope, left alone (not in the phase's call-site table):** full-width
buttons in `RoutineDetailView`, `TimerCardioSetupView`, `IntervalView`,
`WeightKeypadSheet`, `InlineSetEditorView`, `SwimRecordView`, and the summary
`Save to Apple Health` inset still carry their own heights. `WorkoutControlBar`
is explicitly exempt.

### Verification (Phase 1)

- `make ci`: build + **1,329 tests passed, 0 failures** (baseline 1,324 + the 5
  new `LayoutMetricsTests`; the "1,318" figure recorded earlier was stale),
  test-pyramid and no-network guardrails OK.
- `make smoke`: WatchConnectivity activation regression **passed** and the single
  iPhone smoke test **passed**, including the new assertions that Quick Start,
  Custom Workout, Coach's Workout and the plan editor's Start Workout are all the
  same height.
- Ratchets lowered in `scripts/check-test-pyramid.sh`: `HomeView.swift`
  1115 → **1110**, `SessionView.swift` 1102 → **1089**.
- Not pushed, per the batch execution protocol.

</details>

## Next task — field-test UI batch, Phase 3

Execute `docs/field-test-ui-batch-2026-08-18/03-phase3-coach-load-fix.md`
(coach-planned exercises carry real loads instead of `BW x 12`; load resolution
order per decision **D5**, `BW` semantics per **D4**).
Read `00-overview.md` and `decisions.md` first.

| Phase | Scope | State |
|---|---|---|
| 1 | Uniform full-width action buttons (`LayoutMetrics` + `CadenceActionButton`) | **done** |
| 2 | Home's vertical rhythm on Workout Plan / Start Workout / Workout | **done** |
| 3 | Coach plans carry real loads instead of `BW x 12` | not started |
| 4 | Read-only exercise detail in summaries, one row per performer | not started |
| 5 | One "The science" link, all sources on one screen | not started |
| 6 | Coach's Suggestions: floating icon, trimmed copy, CTA below the card | not started |
| 7 | Workouts Today: tappable detail, `COACH'S PLAN`, start a planned workout | not started |
| 8 | This Week gear deep-links to Coach & Plan | not started |
| 9 | Partner-aware Workout Plan (coach fills each partner's plan) | not started |

**Execution protocol for this batch (user instruction, overrides the CLAUDE.md
post-task checklist steps 6-8):** do ONE phase, run `make ci` and `make smoke`,
update this file, `git commit` on `main`, **do not push**, report the SHA, and
stop for review. The pre-commit hook **is** installed and re-runs the guardrails,
`swift test`, and both smoke tests, so `git commit` takes >10 minutes — run it in
the background with `git commit -F <message file>`.

The previous batch ([docs/field-test-remediation-plan.md](docs/field-test-remediation-plan.md))
is complete and shipped as `f809818 Complete field-test workout remediation`.

## Field-testing follow-up

This follow-up addresses the remaining UI issues found after the Home field test:

- Watch sync feedback is inset below the safe area so the startup toast is fully visible.
- Home Start Workout and Log Previous Workout use the same 20-point section spacing as the surrounding Home sections.
- Start Workout now labels the just-in-time editing route `Custom Workout`.
- Workout Plan puts its full-width `Start Workout` control above the list as a standalone action.
- Productive Coach volume suggestions whose insight says `volume is on track` use the green positive treatment; low/high volume remains warning-colored.

Focused presenter and iPhone smoke coverage verify the productive-volume tone and custom-workout label. The CI smoke job covers the complete navigation surface.

## Home field-testing checklist

The Home View field test identified these issues, which are the acceptance criteria for this batch:

1. Rename the Coach suggestion workout to `Suggested Workout` and use the subtitle `Coach created a Workout created to close gaps for this week`.
2. Make `This Week` expand in place. On expansion, hide the `Weekly Volume` heading, start with `Legs`, and put `Show less` at the bottom. Capitalize `Coach’s Suggestions`; keep each suggestion collapsed by default, independently expandable, and color-coded green for positive, yellow for warning, and white for neutral.
3. Apply the same green/yellow state color coding to Weekly Volume body-part rows.
4. Remove the separate `What you did` section. Put this week’s Strength and Cardio workout details inside expanded `This Week`, add `View more…` for complete history, then show weekly volume and `Show less`.
5. Make Strength `Quick Start` enter warm-up/the workout directly without the plan or settings surface.
6. Make Home `Start Workout` full width and put `Log Previous Workout` below it; use Progress View’s Full History for complete history.

## Implementation status — complete

- Home now uses one expandable This Week card for workout details, history navigation, and weekly volume.
- Coach suggestions use the requested copy, independent expansion, and semantic positive/warning/neutral colors.
- Quick Start bypasses plan/settings UI and enters the configured warm-up or active strength session.
- Home actions have the requested layout; duplicate Home Workout History remains removed because Progress View owns Full History.
- Presenter unit coverage now verifies weekly grouping and suggestion/body-part state mapping.
- The iPhone smoke test verifies Home expansion, plan navigation, direct Quick Start, no settings surface, workout completion, and summary return.

## Final audit

- [x] Suggested Workout copy and the requested gap-closing subtitle are present.
- [x] This Week expands in place; Show more is replaced by Show less, the expanded volume starts with Legs, and there is no Weekly Volume heading in the Home composition.
- [x] Coach’s Suggestions is capitalized; suggestions are independently expandable, collapsed by default, and tone-coded.
- [x] Weekly Volume rows use green for productive range and yellow for below/above range.
- [x] What you did is no longer a Home section; expanded This Week contains Strength and Cardio, complete-history navigation, volume, total volume, and Show less.
- [x] Strength Quick Start bypasses plan/settings UI and enters warm-up or the active workout.
- [x] Start Workout is full width, Log Previous Workout is below it, and Home does not duplicate Progress View’s Full History.

## Verification

- `swift test --package-path CadenceCore`: 1,318 tests passed.
- `make ci`: build, 1,318 tests, test-pyramid guardrails, and no-network guardrail passed.
- `make smoke`: WatchConnectivity regression and iPhone Home/Quick Start smoke passed.
- `git diff --check`: passed.
- Commit `ab68140` (`Implement Home field testing fixes`) is pushed to `main`.
- [GitHub Actions run 31962467272](https://github.com/johnarleyburns/parso-workout-ios-app/actions/runs/31962467272) passed `core-tests`, archive warning checks, IPA export, and TestFlight upload.
