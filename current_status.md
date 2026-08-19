# Current Status

Updated: 2026-08-18

## Phase 5 complete — one "The science" link, all sources on one screen

Field test 2026-08-18 issue #10, decision **D9**
(`docs/field-test-ui-batch-2026-08-18/05-phase5-single-science-link.md`). Every
coaching output rendered one `CitationLink` row *per citation* — typically six or
more stacked rows below a single card. It now renders exactly one
`The science ›` row that pushes a screen listing every source.

- New `CadenceFeatures/CitationPresenter.swift` — `citations(forIds:)` (ordered,
  de-duplicated, unknown ids dropped), `unresolvedIds`, `hasScience`,
  `sourcesTitle(count:)`. The resolution rule is unit-tested, not re-derived per
  view.
- New `Coach/CoachSourcesView.swift` — a `List` of every source, one
  `CitationDetailBody` each; ids `coach.sources` / `coach.sources.<id>` /
  `coach.sources.<id>.link`.
- `CitationDetailView` factors out `CitationDetailBody(citation:context:idPrefix:)`
  so the one-source and many-source screens share markup.
- `CoachCardView` gains `CoachSourcesLink` beside the untouched `CitationLink`.
- Converted call sites: `HomeCoachRecommendationCard`
  (`home.coachRecommendation.science`), `CoachDecisionCardView` (both sites —
  `coach.card.warnings.science`, `coach.card.structure.science`; 460 → 458 LOC),
  `PlannedDayPreviewView` (`plan.day.science`), `CoachAlternativesView`
  (`coach.alternatives.<id>.science`), `CoachTestRecommendationCard`
  (`coach.test.science`), `AssessmentDetailView` (`assessment.science`),
  `IntervalSetupView` (`interval.science`).
- `CoachAlternativesView` previously showed only the *first* citation and
  silently dropped the rest; it now reaches all of them.
- `CoachTestRecommendationCard`'s dead `citations` property is removed.

### Verification (Phase 5)

- `make ci`: build + **1,367 tests passed, 0 failures** (baseline 1,360 + 7
  `CitationPresenterTests`), guardrails OK.
- `make smoke`: WatchConnectivity activation regression **passed**, iPhone smoke
  **passed** (65.2 s).
- Acceptance grep is clean: `grep -rn "ForEach" Cadence/Cadence/Features
  --include=*.swift -A3 | grep CitationLink` returns only
  `CoachMethodologyView.swift` and `CoachAboutView.swift`, the two bibliography
  screens the phase file deliberately exempts.
- Not pushed, per the batch execution protocol.

**Honest note on the smoke assertion:** the new check is
`count(label BEGINSWITH 'The science') <= 3` on Home. It passes trivially when
Home shows no coach output, and this run's log does not prove it was non-zero, so
the real coverage for this phase is the headless `CitationPresenterTests`. Left
as-is rather than grown into a coach-navigation flow, per the fixed-size
UI-suite rule.

**Two failed smoke attempts before the green one, neither a code fault:** the
first failed to *build* because `CoachCardView.swift` and `CoachSourcesView.swift`
used `CitationPresenter` without `import CadenceFeatures` (fixed; note `make ci`
builds only the SwiftPM package, so it cannot catch a missing app-target import —
only `make smoke` or an `xcodebuild` app build does). The second died with
`Test crashed with signal term` while waiting for `summary.title`, with **no app
crash report**: a watchOS 26.5 simulator had auto-booted alongside the iPhone and
was saturating the machine (load average 38-45, `Carousel`/`healthd`/`diagnosticd`
from the watch runtime at the top of `ps`). `xcrun simctl shutdown <watch-udid>`
plus a CoreSimulator restart fixed it and the same tree passed in 65 s. If the
iPhone smoke hangs, check `xcrun simctl list devices booted` for a stray watch
sim before suspecting the diff.

**Deviations from the phase file, both deliberate:**

- The phase's call-site table missed `CoachTestRecommendationCard`, which also
  rendered a `ForEach` of `CitationLink`s. Its own acceptance criterion (the grep
  above) requires that file to convert, so it did.
- The two new integrity tests were added to `CitationPresenterTests`
  (**CadenceFeaturesTests**) rather than to `CitationIntegrityTests`
  (CadenceCoreTests) as the phase file suggested: `CadenceCoreTests` depends only
  on `CadenceCore` and therefore cannot see `CitationPresenter` at all. The
  registry-level equivalents already exist in `CitationIntegrityTests`
  (`testEveryCoachSessionCandidateHasCitationIdsUnlessRestOrEmptyLaunch`,
  `testEveryDecisionReasonAndWarningCitationIdResolves`); the new ones assert the
  same rule through the presenter the UI actually calls.

---

<details>
<summary>Phase 4 — read-only exercise detail in summaries (shipped, b9474b6)</summary>

## Phase 4 complete — read-only exercise detail in workout summaries

Field test 2026-08-18 issue #1 (*"I should be able to expand/collapse the
exercise to see details 'view only' WITHOUT having to edit the workout first…
one row per partner, 'Me' first"*).

- `WorkoutSummaryData.ExerciseLine` gains `performers: [PerformerLine]` (one
  additive, defaulted property; new `SetLine`/`PerformerLine` value types). It is
  built only for the owner's lines — `Me` first, then each partner in
  first-appearance order, warm-ups excluded, empty performers dropped. No
  persistence or schema change.
- `WorkoutSummaryPresenter` gains `setLine`, `performerSetsText`,
  `orderedPerformers` and `expandedAccessibilityValue` — all pure, all tested.
  The set format is decision **D8**'s lowercase `x`: `180 lb x 12, 190 lb x 10,
  200 lb x 8`, with `BW x 12` / `BW + 10 kg x 12` for bodyweight.
- New `WorkoutSummaryExerciseRow` (96 LOC): the whole card is one plain `Button`
  with `.contentShape(Rectangle())` (a card with a `Spacer` is otherwise
  untappable in its gap) and `.accessibilityElement(children: .contain)` **before**
  its identifier (otherwise the styled card swallows the per-performer ids).
  Card identifiers are unchanged, so existing tests keep resolving them.
- `WorkoutSummaryView` (307 LOC) tracks `expandedExerciseIDs: Set<String>`, so
  several exercises can be open at once, and **drops `partnersSection`**
  (decision **D6** — those numbers now live in the rows). The hint reads *"Tap an
  exercise to see every set. Use Edit to change them."*
- The `onExercise` closure is gone from `WorkoutSummaryView` and all **three**
  call sites (the phase file listed two — `RootTabView`'s post-workout summary
  was the third). Tapping an exercise no longer originates
  `HistorySummaryRoute.strengthFocused`; the route itself stays, because
  Progress's exercise-trend navigation still uses it.

**Deviation from the phase file (deliberate):** `RootTabView`'s post-workout
summary had *no* `Edit` button — `onExercise` was its only way back into the
session. Removing it outright would have left the just-finished workout
uneditable until the user navigated Home → history, so that summary now passes
`onEdit`, reopening the session (NFR-8's escape hatch, decision **D7**'s
"editing stays reachable through Edit"). `reviewExerciseID` and the
`initiallyExpandedExerciseID:` argument it fed are deleted as now-dead state.

### Verification (Phase 4)

- `make ci`: build + **1,360 tests passed, 0 failures** (baseline 1,344 + 8
  `WorkoutSummaryDataTests` + 8 `WorkoutSummaryPresenterTests`), guardrails OK.
- `make smoke`: WatchConnectivity activation regression **passed**, iPhone smoke
  **passed** (63.7 s).
- **Honest note on the smoke assertion:** the new `summary.exercise` expansion
  check is guarded by `if exerciseRow.exists`, and in this run it did **not**
  fire — the smoke flow's Quick Start workout logs no sets, so the summary has no
  exercise rows. Real coverage for this phase is headless; the guarded assertion
  only earns its keep if the smoke flow ever starts logging a set. Left in place
  rather than grown into a multi-step logging flow, per the fixed-size UI-suite
  rule.
- No ratchet change needed: both summary files are under the 400-LOC budget.
- Not pushed, per the batch execution protocol.

</details>

<details>
<summary>Phase 3 — coach plans carry real loads (shipped, abf1746)</summary>

## Phase 3 complete — coach plans carry real loads instead of `BW x 12`

Field test 2026-08-18 issue #2 (*"always BWx12 even for non-bodyweight exercises
like Standing Dumbbell Upright Row"*). Three independent causes, all fixed:

- **The load lookup only saw the last 7 days.** `TrainingFacts.liftSnapshots` is
  built from the trailing week, so any lift last trained 8+ days ago resolved to
  `nil`. `CoachPlanOptimizer.suggestedLoadKg` now falls back to a new
  `CoachSession.recentTopSet(forExerciseNamed:facts:)`, which finds the newest
  logged top set across **all** history by canonical name (decision **D5**
  resolution order: explicit load → trailing-week snapshot → all-history top set
  → nothing).
- **Anti-repeat rotation stripped the load.** `varietyAlternative` hard-coded
  `loadKg: nil` and `rotatedForVariety` never forwarded `trainingFacts`. The
  replacement is now built first (so the load is priced at the *replacement's*
  rep target, not the original's) and then resolved through the same lookup.
- **The renderer conflated "no load" with "bodyweight".** `BW` is now a statement
  about the movement, never about missing data (decision **D4**): a loaded lift
  with no resolvable history renders `—`. Applied in `CompactExerciseRow`,
  `WorkoutPlanExerciseSection` and `HomeCoachRecommendationCard`, all reading the
  new public `ExerciseLoading.isBodyweight(named:)` façade — the app does not
  re-implement keyword matching anywhere.

A bodyweight movement still resolves to no external load, by guard, before any
history lookup runs — the coach never invents a number for a push-up.

### Verification (Phase 3)

- `make ci`: build + **1,344 tests passed, 0 failures** (baseline 1,330 + 3
  `ExerciseLoadingTests`, 4 `CoachSessionRecentTopSetTests`, 5
  `CoachPlanOptimizerTests`, 2 `EditablePlanTests`), guardrails OK.
- `make smoke`: WatchConnectivity activation regression **passed**, iPhone smoke
  **passed** (83.6 s).
- No coach test regressed — `CoachExerciseVarietyTests`,
  `CoachBodyweightPrescriptionTests`, `RecommendationPrescriptionTests`,
  `WeightSuggestionTests` and `SameDayLoadRegressionTests` are all green.
- Also removed a duplicated `editor.partners` assertion left in the smoke test by
  Phase 2.
- Not pushed, per the batch execution protocol.

**One retracted diagnosis, recorded so it isn't re-derived:** an intermediate
smoke run failed at 136 s and a stash-bisect appeared to implicate
`CoachPlanOptimizer`. It does not — with the change restored the same test passes
in 72 s against a 71 s bisect baseline, and again at 83.6 s under `make smoke`.
The failure was a degraded simulator (machine load 14-17), not the optimizer.
`recentTopSet` is an O(events) scan per planned exercise; at realistic history
sizes that is a few tens of milliseconds and was left un-indexed rather than
optimized against a phantom.

</details>

<details>
<summary>Phase 2 — Home's vertical rhythm on the workout surfaces (shipped, 7e18583)</summary>

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

</details>

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

## Next task — field-test UI batch, Phase 6

Phase 6: **Coach's Suggestions — floating icon, trimmed copy, CTA below the
card** (`docs/field-test-ui-batch-2026-08-18/06-phase6-coach-suggestions-card.md`).
Read `00-overview.md` and `decisions.md` first.

| Phase | Scope | State |
|---|---|---|
| 1 | Uniform full-width action buttons (`LayoutMetrics` + `CadenceActionButton`) | **done** |
| 2 | Home's vertical rhythm on Workout Plan / Start Workout / Workout | **done** |
| 3 | Coach plans carry real loads instead of `BW x 12` | **done** |
| 4 | Read-only exercise detail in summaries, one row per performer | **done** |
| 5 | One "The science" link, all sources on one screen | **done** |
| 6 | Coach's Suggestions: floating icon, trimmed copy, CTA below the card | **next** |
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
