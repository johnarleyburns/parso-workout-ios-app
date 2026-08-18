# Field-test UI batch — 2026-08-18 — Overview

Source: field-testing session on 2026-08-18. Eleven defects/requests, grouped
into **nine sequential phases**. This plan is written so an agent can execute it
**without further research or clarification**: every phase names the exact files,
the exact symbols, the exact acceptance criteria, and the exact commands.

> **Execution rule (from the user): do ONE phase, then STOP.**
> After each phase: verify → update `current_status.md` → `git commit` →
> **do not push** → report the SHA and pause for review. Do not start the next
> phase until the user says to continue.

---

## 1. Raw field-test issues → phase map

| # | Field-test issue (verbatim intent) | Phase |
|---|---|---|
| 1 | Strength summary/history: expand/collapse an exercise **view-only** (no Edit first); with partners, one row per performer, **Me first**, abbreviated `180lb x 12, 190lb x 10, 200lb x 8` | **P4** |
| 2 | Coach's suggested workout shows wrong weights — Workout Plan always says `BW×12` even for loaded lifts (e.g. Standing Dumbbell Upright Row) | **P3** |
| 3 | Home, Workout Plan, Start Workout must use the **same height, full-width** buttons (Quick Start / Custom Workout / Coach's Workout / Start Workout differ today) | **P1** |
| 4 | Coach's Workout Plan view must let me **add training partners**, and default-fill each partner's plan from *their* history (my exercises only, their weights/reps as implied preferences) | **P9** |
| 5 | Workout Plan / Start Workout / Workout views must use the **exact same vertical spacing** as Home | **P2** |
| 6 | Home "Workouts Today": tap a workout for detail (same shape as This Week), same for planned cardio, allow starting it; say **COACH'S PLAN** not **PLANNED** | **P7** |
| 7 | Gear icon top-right of the **This Week** card deep-linking to Coach & Plan settings; Back returns to **Home**, not Settings | **P8** |
| 8 | Coach's Suggestions: coach icon pinned top-right, **floating** (overlay, zero layout space) | **P6** |
| 9 | Remove the `Coach's Suggestions` divider above Suggested Workout, and remove the `Suggested Workout` + subtitle blurb | **P6** |
| 10 | Never render multiple `The science ›` rows — render **one**, and list all sources vertically on the Source screen | **P5** |
| 11 | Move the suggested workout to the **bottom**, and put a full-width **Do Coach's Workout** button *below* the Coach's Suggestions card, matching Home's Start Workout exactly | **P6** |

## 2. Phase order and dependencies

```
P1 Layout tokens + uniform buttons        (no deps)
P2 Vertical rhythm on the 3 workout views (depends: P1 tokens)
P3 Coach plan load resolution (BW bug)    (no deps — pure CadenceCore)
P4 Summary/history view-only expansion    (no deps)
P5 One "The science ›" + Sources list     (no deps)
P6 Coach's Suggestions card restructure   (depends: P1 button metrics, P5 link component)
P7 Workouts Today detail + COACH'S PLAN   (depends: P1, P6 — HomeView LOC headroom)
P8 This Week gear deep link               (depends: P7 — HomeWeekDashboardSection wiring)
P9 Partner-aware Workout Plan             (depends: P2 editor layout, P3 loads)
```

Do them in that numeric order. Each is a self-contained commit.

## 3. Hard constraints that apply to EVERY phase

These are repository rules, not suggestions. Violating any of them fails the gate.

1. **Swift 6, strict concurrency, zero new warnings.** No `@unchecked`, no
   `nonisolated(unsafe)`, no warning suppression.
2. **Logic lives in `CadenceFeatures` / `CadenceCore`, never in a `View`.**
   `CadenceFeatures` may import only Foundation, SwiftData and Observation — it
   must never import SwiftUI/UIKit/HealthKit/StoreKit/CoreBluetooth/CoreLocation.
   If an extraction wants a `Color` or a `View`, return a semantic enum and let
   the view map it.
3. **The XCUITest suite does not grow.** `Cadence/CadenceUITests/SmokeLaunchTests.swift`
   must keep **exactly one** `func test…`. New assertions go *inside* that one
   test. All other new coverage is `swift test`.
4. **400-LOC budget per file under `Cadence/Cadence/Features/`**, with a
   shrink-only ratchet in `scripts/check-test-pyramid.sh`:
   - `Train/SessionView.swift` ≤ 1102
   - `Home/HomeView.swift` ≤ **1115 (currently exactly 1115 — it CANNOT grow)**
   - `Coach/CoachDecisionCardView.swift` ≤ 570
   - `Train/ExercisePickerView.swift` ≤ 532
   - `Plan/RecordAssessmentView.swift` ≤ 439
   - `Coach/YourWeekView.swift` ≤ 406
   `Home/WorkoutPlanEditor.swift` is **399 LOC** — one line from the hard cap.
   Every phase that touches HomeView or WorkoutPlanEditor **must extract into a
   new file**, and when a ratcheted file shrinks, **lower its recorded ceiling**
   in `scripts/check-test-pyramid.sh` to the new LOC.
5. **Every coaching output must cite science.** Resolve ids with
   `CitationRegistry.citation(forId:)`, render with `CitationLink` (or, after P5,
   `CoachSourcesLink`). Never show a raw citation id. `CitationRegistry.all` and
   `docs/CITATIONS.md` stay in sync.
6. **The coach suggests, it does not proscribe (NFR-8).** Never remove an escape
   hatch (alternatives, full cardio picker, strength-anyway, Edit).
7. **Schema changes are additive only** — optional or defaulted, CloudKit-safe
   (no `@Attribute(.unique)`, optional relationships), and round-tripped through
   `DataExport`.
8. **Accessibility is mandatory**: VoiceOver label + Dynamic Type on every new
   control; keep existing `accessibilityIdentifier`s stable (the smoke test and
   several unit tests key off them).

## 4. Verification commands (run for every phase)

```bash
# 1. headless gate — MUST be green before committing
make ci                    # = swift build + swift test + test-pyramid + no-network guards

# 2. simulator gate — run when the phase touched any View
make smoke                 # iPhone smoke + WatchConnectivity regression

# 3. only when the phase touched Cadence Watch App sources
make watch-smoke
```

Git hooks **are installed** here (`scripts/install-git-hooks.sh` has been run).
`pre-commit` runs the guardrails, `swift test`, the iPhone smoke test **and** the
watch smoke test, so a commit takes **>10 minutes** — run it in the background
with a message file (`git commit -F <file>`), never inline with a short timeout.
Run the gates explicitly first anyway, so a failure is diagnosed before the hook
spends ten minutes rediscovering it.

If the simulator degrades (launch balloons to ~45 s, `no debugger version` in the
log), run `killall -9 com.apple.CoreSimulator.CoreSimulatorService` and re-run.
Report honestly which failures are real and which are environment flake.

## 5. Per-phase closing checklist (identical every time)

1. Re-read the phase file and tick **every** acceptance criterion against the
   shipped code. Fix discrepancies before committing.
2. `make ci` green. `make smoke` green (if any View changed).
3. Update **`current_status.md`**: replace the "Next task" section with
   - what this phase shipped,
   - the new `swift test` count,
   - verification results (exact numbers),
   - remaining phases and the immediate next task.
4. `git add -A && git commit` on **`main`** with a conventional-commit subject and
   the trailer:
   ```
   Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
   ```
5. **Do NOT push.** Do not open a PR.
6. Report to the user: commit SHA, test counts, what changed, what is next.
7. **Stop.** Wait for review.

## 6. Root-cause findings established during planning (do not re-derive)

- **`BW×12` bug (issue 2)** has two independent causes, both in
  `CadenceCore/Sources/CadenceCore/CoachPlanOptimizer.swift`:
  1. `suggestedLoadKg(for:trainingFacts:)` (line ~1123) only reads
     `TrainingFacts.liftSnapshots`, and `TrainingFacts.make` builds
     `liftSnapshots` **from the trailing week only**
     (`CadenceCore/Sources/CadenceCore/TrainingFacts.swift` ~line 258, `weekSets`).
     Any lift last trained >7 days ago therefore resolves to `loadKg == nil`.
  2. `varietyAlternative(for:…)` (line ~723) hard-codes `loadKg: nil` and
     `rotatedForVariety` never receives `trainingFacts`, so *every* anti-repeat
     rotation strips the load. "Standing Dumbbell Upright Row" is exactly the
     kind of isolation movement that rotation substitutes in.
  `EditablePlan.from(coach:)` copies `ex.loadKg` straight into
  `EditableSet.targetWeight`, and `CompactExerciseRow.compactSetLine` renders a
  nil weight as literal `"BW"` — hence `BW×12` on the Workout Plan screen.
- **Partner set planning already exists at runtime**:
  `CadenceCore/Sources/CadenceFeatures/SessionRenderModel.swift` builds
  per-performer `PendingSetDisplay`s from
  `WorkoutRepository.firstWorkingSetWeight(for:performedBy:excluding:)` and
  `WorkoutRepository.repLadderHistory(for:performedBy:excluding:)`. P9 lifts the
  same resolution **forward** into the plan editor; it does not invent it.
- **`HomeRoute.coachPreferences` already exists** and already pushes
  `CoachSchedulePreferencesView()` inside Home's own `NavigationStack`, so P8's
  "Back goes to Home, not Settings" is satisfied purely by using that route.

## 7. Files this batch will touch (inventory)

**CadenceCore (pure):**
`CoachPlanOptimizer.swift`, `CoachSession.swift`, `RecommendationRule.swift`,
`TrainingFacts.swift` (read-only reference), `WorkoutSummaryData.swift`,
`Models.swift`, `DataExport.swift`.

**CadenceFeatures (pure, testable):**
`EditablePlan.swift`, `WorkoutSummaryPresenter.swift`, `SessionRenderModel.swift`,
`TodayActivityPresenter.swift`, plus **new**: `LayoutMetrics.swift`,
`CitationPresenter.swift`, `HomeCoachSectionPresenter.swift`,
`WorkoutsTodayPresenter.swift`, `PartnerPlanResolver.swift`.

**App views:**
`Shared/CadenceActionButton.swift` (new), `Home/HomeView.swift`,
`Home/HomeCoachRecommendationCard.swift`, `Home/HomeCoachSuggestionsSection.swift`
(new), `Home/HomeWorkoutsTodaySection.swift` (new),
`Home/HomeWeekDashboardSection.swift`, `Home/WorkoutPlanEditor.swift`,
`Home/WorkoutPlanPartnerSection.swift` (new), `Home/CompactExerciseRow.swift`,
`Home/WorkoutTypePicker.swift`, `Home/WeightsStartView.swift`,
`Workout/WorkoutSummaryView.swift`, `Workout/WorkoutSummaryExerciseRow.swift`
(new), `Coach/CoachCardView.swift`, `Coach/CitationDetailView.swift`,
`Coach/CoachSourcesView.swift` (new), `Coach/CoachDecisionCardView.swift`,
`Coach/PlannedDayPreviewView.swift`, `Coach/CoachAlternativesView.swift`,
`Train/SessionView.swift`.

**Tests:** `CadenceCoreTests/*`, `CadenceFeaturesTests/*`,
`CadenceUITests/SmokeLaunchTests.swift` (the one test only).

## 8. Phase files

- `01-phase1-layout-tokens.md` — uniform full-width action buttons
- `02-phase2-vertical-rhythm.md` — Home's spacing on Plan/Start/Workout
- `03-phase3-coach-load-fix.md` — the `BW×12` prescription bug
- `04-phase4-summary-expansion.md` — view-only exercise detail + partner rows
- `05-phase5-single-science-link.md` — one science row, multi-source screen
- `06-phase6-coach-suggestions-card.md` — floating icon, trimmed copy, bottom CTA
- `07-phase7-workouts-today.md` — tappable detail + COACH'S PLAN
- `08-phase8-week-gear-deeplink.md` — This Week → Coach & Plan
- `09-phase9-partner-plans.md` — partner-filled coach plans
- `decisions.md` — decisions taken while planning (do not re-litigate)
