# Field-Test Remediation Plan

Status: next task — not implemented  
Created: 2026-08-17  
Scope: iPhone Home, Tests, strength-session cards, coach prescriptions, and partner set planning

## Objective

Correct the incomplete field-test implementation and leave every requested behavior covered by deterministic logic tests plus targeted UI verification.

The task is complete only when:

1. Coach suggestions render as plain text inside the single outer Coach surface, with a larger illustration anchored at its upper-right.
2. Tests uses the same 16-point horizontal content margin as the other top-level views, and Strength, Strength-endurance, Cardio, and Advanced Tests each use one category-level glass surface.
3. A coach plan preserves every exercise's per-set reps and weight through workout creation.
4. Adding a partner immediately adds that performer to the pending set plan for every planned exercise.
5. Performer defaults resolve in this order: current-session same-exercise values, prior same-exercise values for that performer, the performer's general rep pattern, the exercise's planned prescription, then the ordinary fallback.
6. The same performer-specific defaults work at initial workout start and after swapping an exercise.
7. Strength exercise cards are collapsed by default, show a disclosure arrow, and reveal all controls only while expanded. The collapsed line includes sets, reps, weights, and partner names when applicable.
8. Home has a Workouts Today section that displays every completed workout dated today with a green check and every remaining coach workout with an unmistakable `PLANNED` state.
9. A partially completed two-a-day keeps the remaining workout visible as planned.
10. The app builds, focused tests pass, and simulator screenshots/inspection confirm margins, glass grouping, disclosure behavior, and state labels.

## Current audit and known defects

The working tree contains a partial implementation. Preserve useful pieces, but do not treat it as complete.

- `TestsView.swift` currently has an extra closing brace after `baselineSection`; the generic iOS build fails with `extraneous '}' at top level`.
- Tests now has a 16-point outer margin, but glass is attached to individual assessment rows rather than the requested category groups.
- `EditablePlan` already carries per-exercise `EditableSet` reps and weights, but both Home and Planning materialization discard most of that information:
  - only the first exercise's rep ladder is persisted;
  - that ladder is then used for every exercise;
  - a weight is persisted only when every exercise happens to have the same first-set weight.
- Adding a partner updates `activePartnerIDs` and now exposes a performer context, but pending set count is still computed once across all performers. Logging the owner's planned sets can therefore consume the partner's plan.
- Partner rep history is queried only for the selected exercise. There is no general partner-pattern fallback.
- `SessionRenderModel.performerContext` incorrectly obtains partner “last time” data by first querying owner sets and then filtering for the partner, so partner context history is empty.
- The inline editor can find exact exercise-specific partner weight/history, but the surrounding pending-plan model cannot represent the intended performer for each pending set.
- Collapsed strength summaries currently show only set progress and top weight. They omit reps and partners.
- Workouts Today uses `WeeklyPlan.DayOutline.isCompleted` to suppress all planned rows. That flag means the day contains a completed event; it does not prove every component of a two-a-day is complete.
- No focused tests currently lock the new Tests grouping, collapsed summary, per-performer pending plan, per-exercise prescription persistence, or partial two-a-day behavior.

## Design decisions

### Persist prescriptions per exercise and set

Add a CloudKit-safe, additive field to `WorkoutSession` for the live workout prescription. Use a defaulted encoded string, matching existing array-backed model properties, with public computed accessors over Codable value types:

```swift
PlannedExercisePrescription {
    exerciseName
    sets: [PlannedSetPrescription]
}

PlannedSetPrescription {
    targetReps
    targetWeightKg?
}
```

Requirements:

- Preserve one record per planned exercise and one element per planned set.
- Store weight canonically in kilograms.
- Keep `plannedExerciseNames`, `plannedRepLadder`, and `prescribedLoadKg` readable for backward compatibility and Watch compatibility during the transition.
- When no new prescription data exists, synthesize a legacy prescription from the old ladder/load fields.
- Include the new field in export/import round trips.
- Include enough prescription data in Watch sync for Watch and iPhone to agree about the active plan.
- Centralize EditablePlan materialization so Home and Planning cannot diverge again.

### Represent pending work per performer

Replace the context's parallel `pendingCount`/`pendingReps` concept with a performer-aware pending value, for example:

```swift
PendingSetDisplay {
    performerID?
    performerName
    setIndex
    targetReps
    targetWeightKg?
}
```

Generate pending sets for the owner and every active partner:

- Planned count for an exercise/performer is the exercise prescription's set count.
- Subtract only that performer's logged, non-warm-up sets for the exercise.
- Adding a partner invalidates the render signature and immediately produces that partner's pending entries.
- Removing a partner removes only unlogged pending entries; already attributed sets remain visible and attributable.
- Tapping a pending row opens the editor for that row's performer, not whichever performer rotation happens to return at render time.
- Normal free-form Add Set can continue using roster rotation.

### Resolve defaults per performer

Create one pure resolver used by iPhone pending rows, the inline editor, and—where applicable—the Watch flow.

For reps at a given set index:

1. Same performer + same exercise earlier in the current session.
2. Same performer + same exercise prior-session ladder.
3. Same performer's general ladder pattern across prior exercises/workouts.
4. Planned exercise/set target reps.
5. Last logged rep or the existing default of 5.

For weight:

1. Same performer + same exercise earlier in the current session.
2. Same performer + same exercise most recent prior working weight.
3. Planned exercise/set target weight.
4. Empty/bodyweight fallback as appropriate.

Do not use the owner's history for a partner. Do not let an owner's coach-wide legacy ladder override a partner's established exercise history.

Implement general rep-pattern history by grouping prior non-warm-up sets by performer, session, and exercise. Feed those ladders to `RepPattern` in chronological order so its consensus/recent fallback remains deterministic.

### Exercise swap behavior

When a planned exercise is swapped before any sets are logged:

- Keep the planned set count and rep intent unless the editor explicitly changed them.
- Resolve performer-specific weight/reps against the newly selected exercise immediately.
- Exact new-exercise history takes precedence over the transferred planned fallback.

When a logged exercise is changed:

- Continue moving owner and partner sets together as current history-edit behavior does.
- Update the prescription key/name to the replacement exercise.
- Rebuild pending sets separately for every performer from the replacement exercise's history.

### Tests layout

Use one top-level `ScrollView` with a `VStack` and 16-point horizontal padding. Render:

- Your Fitness as one glass card.
- Strength as one glass category card containing all Strength rows.
- Strength-endurance as one glass category card containing all Strength-endurance rows.
- Cardio as one glass category card containing all Cardio rows.
- Advanced Tests as one glass disclosure card.

Rows inside a category should be plain navigation rows separated by subtle dividers. Do not give every row its own glass/background. Keep the glass backdrop behind the scroll view.

### Collapsed strength summary

Move compact-summary construction into a pure presenter so it can be unit-tested. The summary should be concise but include all requested dimensions:

- Set completion/planning, including per-performer planned totals.
- Rep pattern or observed rep range.
- Weight or weight range in the selected unit; use `BW` correctly.
- Partner names when any partner is active or has attributed sets.

Examples:

- `0/3 sets · 8 reps · 135 lb`
- `3/6 sets · 8–10 reps · 95–135 lb · Sam`
- `2/4 sets · BW × 12 · Sam, Lee`

The chevron and summary remain the only exercise-specific controls/content visible while collapsed. Info, ellipsis, Edit, context/history lines, columns, sets, and action buttons appear only after expansion. An explicitly focused history route may still open one requested exercise expanded; ordinary workout entry must start fully collapsed.

### Workouts Today state

Completed rows come from persisted, non-deleted records whose workout date is today:

- Strength requires `endedAt != nil`.
- Cardio requires a persisted completed record with `end != nil`.
- Include manually logged workouts when their selected date is today.
- Use the custom cardio title where present.

Planned rows should come from the coach decision's remaining `todayPlannedRecommendations`, not from `DayOutline.isCompleted`. This is already the coach engine's representation of work still outstanding after adherence is evaluated.

Each row needs a stable, explicit state:

- Completed: green `checkmark.circle.fill` plus `COMPLETED`.
- Planned: calendar/clock treatment plus `PLANNED`; never a green completion treatment.

If one component of a two-a-day is completed, show its completed persisted row and retain the other coach component as `PLANNED`. Avoid duplicate planned/completed rows by relying on remaining recommendations or, defensively, matching source/kind when the snapshot is stale.

## Implementation phases

### Phase 0 — restore a buildable baseline

1. Remove the extra brace in `TestsView.baselineSection` and normalize indentation.
2. Run `git diff --check`.
3. Run a generic iOS build with signing disabled.
4. Do not continue structural work until the source tree compiles.

Acceptance:

- No Swift syntax/type-check errors.
- Generic iOS build passes, or any unrelated infrastructure failure is isolated with proof that the app target compiled.

### Phase 1 — prescription model and one materializer

Likely files:

- `CadenceCore/Sources/CadenceCore/Models.swift`
- `CadenceCore/Sources/CadenceCore/DataExport.swift`
- `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift`
- `CadenceCore/Sources/CadenceFeatures/EditablePlan.swift`
- `Cadence/Cadence/Features/Home/HomeView.swift`
- `Cadence/Cadence/Features/Home/PlanningView.swift`
- Watch sync/flow files that currently read `plannedRepLadder` or `prescribedLoadKg`

Steps:

1. Add Codable prescription value types and additive encoded session storage.
2. Add legacy fallback accessors.
3. Add one tested materializer/apply operation for EditablePlan.
4. Route Home and Planning starts through it.
5. Update prescription display and inline-editor lookup to select the current exercise and set index.
6. Extend export/import and Watch sync without breaking legacy payloads.

Acceptance:

- A coach plan with Bench 3×8 @ 60 kg and Squat 4×5 @ 100 kg reaches the live session unchanged.
- Different rep ladders on two exercises remain different.
- Legacy sessions still render and log normally.
- Export/import round trip preserves the full prescription.

### Phase 2 — partner-aware set planning and defaults

Likely files:

- `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift`
- `CadenceCore/Sources/CadenceFeatures/SessionRenderModel.swift`
- `CadenceCore/Sources/CadenceFeatures/SessionViewModel.swift`
- `Cadence/Cadence/Features/Train/SessionView.swift`
- `Cadence/Cadence/Features/Train/ExerciseCardView.swift`
- `Cadence/Cadence/Features/Train/SessionView+Partners.swift`

Steps:

1. Fix partner performer-context history to query the actual `Person`.
2. Add general performer rep-ladder history.
3. Introduce the pure default resolver with documented precedence.
4. Replace aggregate pending fields with performer-aware pending entries.
5. Bind pending-row taps to an explicit performer.
6. Recompute when partners are added, removed, or reordered.
7. Ensure planned and logged exercise swaps rebuild defaults for the replacement exercise.

Acceptance:

- A 3-set exercise with one partner plans six pending working sets before logging.
- Logging three owner sets leaves all three partner sets pending.
- A returning partner gets their exact prior exercise weight and ladder.
- A returning partner with no history for the exercise gets their usual general rep pattern and the planned weight fallback.
- A brand-new partner gets the planned exercise reps/weight.
- Swapping to an exercise the partner has done immediately uses that exercise's history.

### Phase 3 — strength disclosure and summary

Steps:

1. Keep the current chevron/default-collapse/control gating that already matches the prompt.
2. Add a pure compact-summary presenter over exercise context, prescription, roster, and units.
3. Include reps, weight/bodyweight, and partner names.
4. Verify expansion remains independently controllable and focused history routing still works.

Acceptance:

- Normal strength entry shows every exercise collapsed.
- Collapsed rows contain no info/menu/Edit or set/action controls.
- Summary text includes sets, reps, weight, and partners when present.
- Expanding reveals the existing editing/logging UI without losing state.

### Phase 4 — Tests category glass and margins

Steps:

1. Build a category-card helper to avoid three divergent layouts.
2. Move glass from assessment rows to category containers.
3. Keep 16-point horizontal outer padding.
4. Preserve navigation, trends, latest values, accessibility identifiers, and Advanced disclosure behavior.

Acceptance:

- Strength, Strength-endurance, Cardio, and Advanced each have one glass boundary.
- Individual rows do not look like separate glass cards.
- Left/right edges align with Home and Progress top-level sections on the same simulator.

### Phase 5 — Coach surface and Workouts Today

Steps:

1. Retain the already-correct plain suggestion treatment and larger upper-right illustration.
2. Add a small regression assertion that suggestions have no individual card background/outline.
3. Replace Workouts Today's planned source with remaining coach recommendations.
4. Require completed cardio `end != nil`, use custom titles, and retain same-day manual logs.
5. Handle stale snapshot duplicate defense and partial two-a-days.

Acceptance:

- Suggestion items are text, not nested boxes.
- Coach illustration is visibly larger and upper-right.
- Same-day logged strength/cardio appears completed immediately after save.
- Planned coach work is labeled `PLANNED` and never green-checked.
- Completing one of two planned workouts produces one completed row and one planned row.

## Test plan

### CadenceCore/CadenceFeatures unit tests

Add or extend tests for:

- Prescription encoding/decoding and legacy fallback.
- EditablePlan materialization with different exercises, set counts, ladders, and weights.
- Export/import and Watch payload compatibility.
- `SessionRenderModel` pending sets per performer.
- Partner add/remove cache-signature invalidation.
- Same-exercise versus general partner rep-pattern precedence.
- Exact exercise weight precedence over planned weight.
- New-partner planned fallback.
- Swap resolution for owner and partner.
- Compact summary solo, partnered, bodyweight, empty, and mixed-weight cases.
- Workouts Today presenter: empty, manual same-day, historical-date exclusion, complete, planned, and partial two-a-day.

### UI/smoke coverage

Extend the existing iPhone smoke path rather than creating a broad new suite:

1. Open Tests and assert category headings/cards and row navigation.
2. Start a coach strength workout with a weighted prescription.
3. Assert the initial exercise card is collapsed and the summary contains prescription data.
4. Expand and assert info/menu/Edit appear.
5. Add a seeded returning partner and assert partner pending rows/defaults.
6. Swap an exercise and assert the replacement history is used.
7. Log a same-day prior workout and assert Workouts Today shows `COMPLETED`.
8. Seed a two-a-day with one completed component and assert the other remains `PLANNED`.

### Manual visual verification

Capture or inspect on the primary iPhone simulator:

- Home Coach surface at default and expanded suggestion states.
- Tests at top and through all categories.
- Strength workout collapsed, expanded, solo, and partnered.
- Workouts Today empty, completed-only, planned-only, and mixed states.

Check Dynamic Type at one larger accessibility size and VoiceOver labels for disclosure state and planned/completed status.

## Verification commands

Run in this order:

```sh
git diff --check
swift test --package-path CadenceCore
xcodebuild -project Cadence/Cadence.xcodeproj \
  -scheme Cadence \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  -derivedDataPath Cadence/build \
  CODE_SIGNING_ALLOWED=NO build
make smoke
make pre-commit
```

If the simulator build still encounters the Watch AppIcon asset issue, use the generic iOS build as the source-compilation gate and document the asset failure separately; do not report the field-test task complete without a successful app-target compile and visual simulator pass.

## Final completion checklist

- [ ] Source compiles; no extra brace or type-check errors.
- [ ] Coach suggestions are plain text; illustration is larger and upper-right.
- [ ] Tests margins match other top-level views.
- [ ] Tests glass wraps categories, not individual rows.
- [ ] Per-exercise/per-set reps and weights survive workout materialization.
- [ ] Partner addition creates pending sets for that partner.
- [ ] Exact partner exercise history prefills reps and weight.
- [ ] General partner rep pattern is used when exact exercise history is absent.
- [ ] New partner uses the planned prescription fallback.
- [ ] Initial and swapped exercises follow the same default precedence.
- [ ] Strength cards default collapsed with a chevron.
- [ ] Collapsed summary includes sets, reps, weight, and partner names.
- [ ] Info/menu/Edit and set controls are visible only when expanded.
- [ ] Workouts Today includes same-day completed strength and cardio.
- [ ] Remaining coach work is visibly `PLANNED`.
- [ ] Partial two-a-day retains its remaining planned component.
- [ ] Unit, smoke, build, guardrail, and visual checks pass.

## Handoff note

Begin with Phase 0. The current working tree contains the partial field-test edits described above; work forward from them, preserving useful behavior, rather than reverting unrelated user changes. Do not mark this task complete based only on package tests—the app currently has a known source compilation failure and several behavioral gaps that require UI-level verification.
