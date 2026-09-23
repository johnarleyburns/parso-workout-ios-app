# Cladiron navigation and weekly-surface rework plan

Date: 2026-09-23
Status: implemented; audit clean; ready to commit

## Objective

Make the next workout path obvious while preserving every existing workout
capability behind named, deliberate screens. Remove duplicate entry points from
Today, separate recommendations from user-chosen workouts, simplify This Week
into three useful top-level reports, and ensure the glass tab bar never covers
the last usable row on any scrollable page.

## Product rules

- Today has one workout entry button: `Start Workout`.
- `Quick Start` and `More ways to start…` are removed from Today.
- Recommendations and user-directed choices are visually separate.
- Recommendation actions remain the existing Strength and Cardio generators;
  this pass changes their entry surface, not their scientific selection logic.
- User-directed strength actions remain Custom, Previous, Schedule, and Log.
- User-directed cardio shows recent choices first and keeps scheduling as a
  separate explicit action.
- This Week reports only what the user needs there: Sets per Muscle Group,
  Strength, and Cardio. My History remains reachable from Progress/History but
  is removed from This Week.
- No workout, plan, coach, sync, or data feature is deleted; only duplicate
  navigation and redundant presentation are removed.
- Every asynchronous or potentially slow action remains explicit and
  recoverable. No new automatic planning or hidden scheduling is introduced.

## Current implementation points

The current code uses:

- `HomeView(surface:)` for Today and This Week;
- `SelectWorkoutView` for the current inline Today start block and the modal
  start picker;
- `WorkoutForYouModalityView` for the current recommendation modality screen;
- `WorkoutTypePicker` for the existing cardio picker sheet;
- `HomeWeekDashboardSection` for the current This Week map, Volume, Strength,
  and Cardio disclosures;
- `HomeMyHistorySection` for the This Week history card;
- `PlanAwareInsightEngine` for the Coach deficit copy;
- `RootTabView` for the glass dock and root safe-area boundary.

The implementation should reuse the existing launch closures and presenters
where possible. Route state should continue to carry IDs/value types rather
than SwiftData model objects.

## 1. Bottom clearance for every scrollable page

### Problem

The dock is installed at the root, but several nested `ScrollView` surfaces can
still scroll their final content behind the glass tab bar. The fix must cover
Today, This Week, Progress, Settings, history/planned routes, start/picker
surfaces, plan/editor surfaces, exercise/search/info/swap surfaces, Coach
surfaces, summaries, cardio/HIIT setup, and any other scrollable page presented
inside the tab-root navigation hierarchy.

### Design

1. Add one shared `CadenceTabBarClearance` view modifier/environment value in
   the app shared UI layer. It will reserve the measured dock height plus a
   small visual breathing margin, rather than repeating arbitrary bottom
   padding in individual screens.
2. Keep the root `safeAreaInset` that owns the actual dock. The new modifier is
   applied to scroll content, not to the dock, so it cannot enlarge or move the
   tab bar.
3. Apply the modifier to every vertical scroll surface reachable from the four
   root tabs. Horizontal metric/map scrollers do not need it unless they are
   themselves the page container.
4. Preserve existing bottom insets for editors, keypad sheets, summaries, and
   session controls. Where an existing `.safeAreaInset(edge: .bottom)` is a
   real action bar, compose the clearance with that bar rather than replacing
   it.
5. Add a test-only accessibility/geometry seam or static inventory test so a
   newly added root scroll page cannot omit the modifier silently.

### Acceptance

- On Today, This Week, Progress, Settings, History, Planned Workouts, Start
  Workout, Pick Workout, Cardio Picker, Workout Plan, Set Entry, live workout,
  summaries, Coach, and exercise surfaces, the final row can be scrolled fully
  above the dock.
- Dynamic Type does not clip the final action.
- Modal sheets that do not contain the root dock do not receive a needless
  second dock-sized blank area.

## 2. Today: one `Start Workout` entry point

### Today changes

1. Replace the current inline `Workout for You` button with a single button
   titled `Start Workout`.
2. Remove the inline `Quick Start` button entirely.
3. Remove the inline `More ways to start…` disclosure entirely.
4. Keep `My Workouts`, observations, readiness, and explicit scheduled-workout
   rows unchanged except for the shared bottom clearance.
5. Update accessibility identifiers and UI smoke labels from
   `selectWorkout.suggestWorkout`/`Workout for You` to the new Start Workout
   entry contract. Preserve compatibility aliases only if an existing deep
   link or test requires them; do not leave duplicate visible buttons.

### Start Workout screen

Rename the current recommendation modality screen from `Workout for You` to
`Start Workout`. It becomes the single start hub with two named sections:

#### Workouts Created for You

- `Strength` button: invokes the current personalized strength request and
  presents the existing editable generated plan.
- `Cardio` button: invokes the current cardio suggestion request and presents
  the existing cardio suggestion preview/launch flow.
- Generation retains the current spinner, cancellation, late-result guard,
  retry, manual fallback, and no-blank-route behavior.

#### Pick Your Own Workout

- `Strength` button: navigates to the new `Pick Workout` view.
- `Cardio` button: navigates to the new standalone Cardio Picker view.

The screen title, accessibility label, mockup reference, and smoke test should
all say `Start Workout`. The generated plan itself may retain a descriptive
workout title, but no entry screen should be titled `Workout for You`.

## 3. New Pick Workout view

Create a small, explicit `PickWorkoutView` reachable only through
`Start Workout → Pick Your Own Workout → Strength`.

Actions, in this order:

1. `Custom Workout` → existing empty `WorkoutPlanEditor` in edit mode.
2. `Do a Previous Workout` → existing `PreviousWorkoutsView` / “Start from a
   previous workout…” picker.
3. `Schedule Workout` → existing empty plan editor followed by the current
   schedule sheet; preserve the future date/time guard.
4. `Log Workout` → existing manual log picker.

The view must not contain recommendation generation, Quick Start, a cardio
catalogue, or duplicate schedule controls. All callbacks should return through
the existing Home ownership boundary so sheet dismissal cannot race a route
push or create the old blank warning screen.

## 4. New Cardio Picker view and scheduling mode

Create or extract a reusable `CardioPickerView` from the current cardio choice
content. It must support two explicit modes:

```text
CardioPickerMode.start
CardioPickerMode.schedule
```

### Start mode

- Show the user’s top three recent cardio types first.
- Fill missing slots using the existing fallback order: Run, Cycle, Swim.
- Show `Show More…` with the remaining supported types, including Other,
  Elliptical, Stair Climber, HIIT, and Boxing.
- Selecting a cardio type starts the existing pre-workout flow.
- Do not show per-card `Schedule Run`, `Schedule Cycle`, or other schedule
  links in this view.
- Do not show recommendation buttons in this user-choice view.

### Schedule mode

- Use the same top-three/show-more list and the same exercise choices.
- Selecting a type opens the existing `ScheduleWorkoutSheet` (or the existing
  type-specific setup when required) with the chosen cardio type as the
  payload.
- The bottom action is a prominent `Schedule Cardio` button/section entry that
  makes the scheduling intent explicit. It must not be confused with starting
  now.
- Preserve date and time, future-time validation, local persistence, planned
  row labeling, and planned-workout launch behavior.

The normal Cardio Picker has no schedule option; only the schedule-mode entry
does. `Other Cardio` must remain reachable in both modes.

## 5. This Week redesign

### Surface structure

Replace the current single green card containing a header, map, Strength,
Cardio, and Volume disclosures with a simple vertical page:

1. Plain `This Week` heading at the top, matching Today’s heading treatment.
2. `Sets per Muscle Group` top-level section.
3. `Strength` top-level section.
4. `Cardio` top-level section.

Each section remains independently collapsible. Only one section may be
expanded if that is the established `WeeklyDetailSelection` behavior; do not
reintroduce a single “Show More” containing all reports.

### Sets per Muscle Group

- Rename the visible `Muscle Map` title to `Sets per Muscle Group`.
- Keep the faithful front/back selector, tracked-group filtering, callout
  lines, per-muscle detail sheet, direct/indirect history, partner selector,
  colors, and cardio heart indicator.
- Remove the old separate `Volume` disclosure, its duplicate legend/total
  presentation, and its duplicate “Volume” title.
- The muscle map and set rows become the content of the new top-level Sets per
  Muscle Group section.
- Continue showing only tracked DB++ muscle groups, including Adductors,
  Abductors, and Lower Back when present in the canonical tracked set.
- Preserve the warning icon behavior and clearable warning sheet.

### Strength

- Move the existing Strength disclosure content into its own top-level section.
- Preserve workout rows, partner filtering, progress, and detail navigation.

### Cardio

- Move the existing Cardio disclosure content into its own top-level section.
- Keep workout rows, HR/intensity detail, and scientific explanation.
- Change the collapsed summary from `40 min` to a credit-guideline format such
  as `40/150 min credit` (using the actual computed values, not hard-coded
  text). The expanded content may retain the detailed moderate-equivalent and
  public-guideline explanation where appropriate.

### Remove from This Week

- Remove `HomeMyHistorySection` from This Week completely.
- Do not delete `HistoryView`, Progress → History, or workout summary routes.
- Remove This Week-specific settings/volume affordances only if they are
  duplicates; retain any explicit Coach preferences route that is still
  required by the product.

## 6. Coach deficit copy

Update the partially resolved volume insight generated by
`PlanAwareInsightEngine`:

- Keep the title `Some volume still needs attention`.
- Replace `Added to tonight: … Still short: …` with exactly the user-facing
  structure:

  `Sets per muscle group in deficit: Chest 3 sets, Lower Back 2 sets.`

- List only the projected deficits that remain after safe planning, sorted by
  deficit descending and then canonical muscle-group order.
- Do not list resolved groups, “added to tonight,” or imply that the user must
  accept an automatic plan change.
- Keep the existing detailed rationale, citations, severity, and reversible
  action behavior.
- Apply the same wording contract to any equivalent unresolved-volume insight
  so the UI does not alternate between two concepts.

## 7. Mockups and documentation

Update the lifecycle mockup atlas with reachable states for:

- Today with one Start Workout button;
- Start Workout with Workouts Created for You and Pick Your Own Workout;
- Pick Workout with all four strength actions;
- Cardio Picker start mode and schedule mode;
- This Week with Sets per Muscle Group, Strength, and Cardio as separate
  top-level sections;
- Cardio’s `40/150 min credit` collapsed summary;
- the revised Coach deficit insight;
- a final-row/dock-clearance state for representative scrollable pages.

Every new mockup control must have a matching screen or documented state, and
the route validator must report zero missing or orphaned routes.

## 8. Implementation sequence

1. Add the bottom-clearance primitive and apply it to the current root-tab and
   nested scrollable surfaces; add its guard/test seam.
2. Extract/rework the current start content into `StartWorkoutView`,
   `PickWorkoutView`, and reusable `CardioPickerView` without changing launch
   callbacks.
3. Replace Today’s inline start content with one Start Workout button and
   remove Quick Start/More ways from the visible Today tree.
4. Wire start and schedule Cardio Picker modes, then remove per-card schedule
   actions from normal Cardio Picker mode.
5. Refactor This Week’s composition and labels, remove My History, and update
   the credit summary presenter.
6. Update Coach insight copy and its tests.
7. Update accessibility identifiers, UI smoke flows, unit tests, and mockups.
8. Run route validation, `git diff --check`, package tests, test-pyramid
   guardrails, and a generic iOS build. Do not run a simulator/device unless
   separately requested.
9. Audit the implementation against this document and the mockup route graph;
   only after the audit is clean should the work be committed.

## 9. Test matrix

### Navigation/UI smoke

- Today contains one `Start Workout` entry and no Quick Start or More ways
  controls.
- Start Workout shows both sections and both recommendation buttons.
- Created-for-you Strength opens the generated editable strength plan.
- Created-for-you Cardio opens the existing cardio suggestion preview.
- Pick Your Own Strength reaches Pick Workout, then Custom, Previous, Schedule,
  and Log each reach their existing destinations.
- Pick Your Own Cardio shows three recent/fallback choices, expands with Show
  More, and starts a selected type.
- Schedule Cardio opens the same picker in scheduling mode and persists type,
  date, and time; normal Cardio Picker has no schedule buttons.
- Every tested scrollable page can reveal its final action above the glass dock.

### This Week

- Top-level labels are exactly `Sets per Muscle Group`, `Strength`, and
  `Cardio`.
- `Muscle Map`, `Volume`, and `My History` are absent from the This Week
  surface, while History remains reachable elsewhere.
- Sets per Muscle Group preserves front/back maps, all tracked groups, callouts,
  detail sheets, and partner selection.
- Cardio collapsed text renders `completed/150 min credit` with actual values.
- Sections remain independently collapsible and do not duplicate their title
  inside expanded content.

### Coach and regression

- Partial deficit copy starts with `Sets per muscle group in deficit:` and
  includes only projected remaining deficits.
- Existing generator, history, schedule, partner-volume, Watch, sync, and
  route-recovery tests remain green.
- No blank warning route is introduced by any new navigation boundary.

## Definition of done

- The implementation and mockup route graph agree with this plan.
- All requested visible labels and entry points are present exactly once.
- All removed visible controls are absent from Today/This Week while their
  capabilities remain reachable through the new named routes.
- Scrollable pages have verified dock clearance.
- Unit/UI contract tests and generic iOS build pass.
- A final audit reports no plan gaps, and changes are ready for a separate
  commit/review step.

## Implementation record

- Added `StartWorkoutView`, `PickWorkoutView`, and the shared start/schedule
  `CardioPickerView`; Today now exposes one `Start Workout` route and clears
  the navigation path before launching a sheet or active workout.
- Removed visible Quick Start/More ways controls from Today, moved the four
  strength actions into Pick Workout, and made cardio scheduling a distinct
  `Schedule Cardio` action that opens the shared picker in schedule mode.
- Applied root dock clearance through `CadenceTabBarClearance` and split the
  Home dashboard overlay extension so the test-pyramid file-size guard remains
  green.
- Refactored This Week into independent Sets per Muscle Group, Strength, and
  Cardio cards; removed This Week My History and the old gear affordance; kept
  Progress → History as the canonical history route.
- Updated the cardio collapsed label to actual `completed/target min credit`
  values and changed Coach deficit copy to list only remaining deficits.
- Updated iPhone smoke contracts for the new routes, explicit schedule-cardio
  flow, retired identifiers, This Week sections, partner selection, and the
  absence of duplicate volume/history surfaces.
- Updated the lifecycle mockup atlas in
  `~/Downloads/cladiron-workout-lifecycle-mockups.html` with the new Start,
  Pick Workout, Cardio Picker, and Schedule Cardio states.

## Audit record

Verification completed before commit:

- `git diff --check` passed.
- `scripts/check-test-pyramid.sh` passed with one iPhone smoke and one Watch
  smoke target; no additional simulator smoke target was introduced.
- Selected CadenceCore tests passed (34 tests), including dashboard volume,
  cardio-choice, muscle-map, weekly disclosure, and Coach insight contracts.
- Generic iOS Debug build passed with
  `CODE_SIGNING_ALLOWED=NO` and `generic/platform=iOS`; no simulator or device
  was launched.
- Full CadenceCore package suite passed: 1,836 tests with 0 failures.
- Generic iOS Debug build-for-testing passed; no simulator or device was
  launched.
- Route graph, diff check, test-pyramid guardrail, and source line-count audit
  passed.
- Audit result: clean; ready to commit and push.
