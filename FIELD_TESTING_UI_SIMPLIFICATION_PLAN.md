# Field-testing UI simplification and Today workflow plan

Status: implemented in the current working tree; audit and review commit pending

This plan addresses the latest field-testing report. The current working tree
implements the app-side changes below. Simulator execution remains deferred
while the owner reviews the anatomy mockups; the review commit is prepared
only after headless checks and the plan audit are complete.

## 1. Scope and product decisions

The goal is to keep the current workout, history, coaching, scheduling, Health,
Watch, and settings capabilities while making the primary flow quieter and
more predictable:

1. Today is the launch and review surface. It must not expose transient
   background-processing copy that shifts the layout.
2. Start Workout exposes the common choices immediately and puts less-common
   choices behind one clearly named `Show more…` disclosure.
3. A workout can be scheduled for a specific local date and time. The existing
   one-off scheduled-workout snapshot remains the source of truth; this is not
   a return to weekly coach plans.
4. Today has one `My Workouts` queue and one collapsed `My History` section.
   Planned records remain editable in the existing planned-workouts list.
5. Progress follows the same summary-first, disclosure-driven rhythm as Today.
6. Settings and Tests remain reachable without the old Today `More` screen.
7. The bottom navigation becomes a custom glass dock matching the local
   `../parso-tonearm` treatment, with Today, Progress, and Settings.

No DB++ change is recommended. The reported issues concern local presentation,
the app-owned `ScheduledWorkout` snapshot, and local navigation. The app should
keep these extensions app-only so DB++ remains a canonical exercise/plan data
source rather than becoming an execution-queue or UI-navigation dependency.

## 2. Field report mapped to current implementation

### 2.1 Remove the transient text below Today

Current code has three possible sources of launch-time copy near the Today
navigation title:

- `HomeView+Dashboard.swift` renders `home.healthSync.status` while HealthKit
  import is in progress.
- The same view renders `home.coachCompute.status` while the coach snapshot is
  recomputed.
- `RootTabView.swift` places a CloudKit restore toast in a root overlay with a
  fixed top offset intended to sit below the navigation bar.

All three can appear and disappear independently, causing the reported visual
jump. The dashboard should render none of these status labels. The background
work remains cancellable and observable through Settings > Transparency &
Control / iCloud diagnostics, where it belongs. An explicit user action such
as “Sync to Watch Now” may still produce a short action-result toast, but it
must not be used for automatic Today loading and must not insert layout space.

Implementation:

- Remove the two conditional status labels from the Today content stack.
- Stop routing automatic CloudKit restore copy through the Today-facing root
  overlay. If the existing restore state still needs a user-visible result,
  expose it in the iCloud diagnostics/transparency surfaces and keep the root
  overlay reserved for explicit actions.
- Preserve the underlying status state and signposts; this is a visibility
  change, not a synchronization change.
- Keep the supporter badge in the existing date row, right aligned, without a
  separate header row.

Acceptance:

- Launching Today with Health, coach, and CloudKit work in progress never
  creates a text row below the `Today` title/date area.
- The first interactive dashboard frame and the settled dashboard have the
  same vertical positions for Start Workout and the first content card.
- Settings still explains whether restoration/sync is in progress or failed.

### 2.2 Restore Schedule Workout in More actions, with time

`HomeView+Actions.swift` currently exposes only `Log Previous Workout` inside
the expanded `More actions` area. `WorkoutPlanEditor` already has a scheduling
sheet, but `ScheduleWorkoutSheet` is date-only and
`ScheduledWorkoutDate.normalize` intentionally converts every date to local
start-of-day. That means “later today” cannot be represented.

Implementation:

- Add `Schedule Workout` as the first secondary action under `More actions`.
- The action opens a new custom Workout Plan editor in scheduling mode. The
  user can add/edit exercises, then chooses `Schedule this Workout`; saving
  returns to Today. This reuses the existing reviewed-plan snapshot boundary
  instead of creating a second schedule format.
- Keep the existing Schedule Workout entry in Workout Plan for suggested and
  custom plans.
- Change the schedule picker to use a local `DatePicker` with both `.date` and
  `.hourAndMinute`. For today, default to a practical future time (the next
  rounded 15-minute slot, clamped to at least a few minutes from now). For a
  future day, default to a reasonable morning time without changing the date.
- Validate that the selected instant is not in the past. A selected time today
  must be later than `now`; a future date can use any valid local time.
- Preserve the full local instant in `ScheduledWorkout.scheduledDate` and
  continue deriving `scheduledDayKey` from the local calendar. Do not add a
  second `scheduledTime` field unless a schema constraint discovered during
  implementation makes it unavoidable; `Date` already carries the time.
- Update comments and tests that currently describe `scheduledDate` as
  start-of-day. Legacy records whose date is midnight remain valid as
  date-only/all-day records; display them without inventing a time.
- Update the planned-workout rows and list to show a time when the record has
  a meaningful time, and keep day grouping based on `scheduledDayKey`, not UTC
  date comparisons. Rescheduling uses the same date-and-time picker.
- Make the new custom scheduling route use the same save/error handling,
  snapshot version, and CloudKit behavior as existing plan scheduling.

Acceptance:

- More actions > Schedule Workout is present and accessible.
- A user can create a plan for 4:30 PM today and see it in Today and the
  planned list with the time preserved.
- A user can create a plan for a future date/time, reschedule it, start it, and
  still receive the exact saved plan snapshot.
- Existing date-only records decode and display without migration failure.

### 2.3 Merge Today’s completed and planned work into My Workouts

Today currently renders separate `HomeWorkoutsTodaySection` and
`HomePlannedWorkoutsSection` cards. The completed section links to History and
the planned section links to the planned list. This splits one actionable queue
and makes planned work look unrelated to completed work.

Implementation:

- Replace both cards with a single `My Workouts` component.
- Show completed workouts from today inline first, using the current compact
  historical row and preserving the existing summary destination.
- Show scheduled workouts for today inline after completed work, with a clear
  `PLANNED` status flag and the scheduled time where available. Keep the
  existing Start/Resume behavior.
- The card’s single `Show more…` action opens the current planned-workouts list
  and its Today/Upcoming/Past sections, where planned exercises, reschedule,
  start, and delete remain available. Use a separate small “View full history”
  action only in My History, so the My Workouts action is unambiguous.
- Remove the old duplicate card headings and old accessibility identifiers only
  after adding stable replacement identifiers (`home.myWorkouts`,
  `home.myWorkouts.planned`, and `home.myWorkouts.showMore`). Keep compatibility
  identifiers temporarily if the current smoke suite still references them,
  then update the suite in the same change.

### 2.4 Add My History at the bottom of Today

The current week activity and Today rows are spread across the dashboard. Add a
collapsed `My History` section at the bottom of Today, after Observations and
Readiness, so the immediate workflow is not dominated by historical detail.

Implementation:

- Use the existing week activity projection for all strength/cardio workouts in
  the current week, sorted newest first, and reuse the established summary
  routing for each row.
- Show a compact preview by default (a small recent subset); show the current
  week’s complete list when expanded.
- `Show more…` navigates to the full History view.
- Do not duplicate the same rows in the top My Workouts section: My Workouts is
  today-only; My History is the week-to-date review surface.
- Keep the existing This Week metrics card as the metric summary, but do not
  make it another workout-list destination.

### 2.5 Start Workout strength disclosure

`SelectWorkoutView` currently shows Quick Start, Custom Workout, and
Personalized Workout, then exposes Previous Workouts under `More strength
options`.

Implementation:

- Move `Custom Workout` into the collapsed group beside Previous Workouts.
- Rename the control to exactly `Show more…`; use the same label when expanded
  as `Show less` (no “strength options” terminology in the main flow).
- Keep Personalized Workout and Quick Start visible.
- Preserve existing deep-link behavior and accessibility identifiers, updating
  the smoke test to expand the group before selecting Custom Workout.

### 2.6 Start Workout cardio redesign

The current `SelectWorkoutView.cardioCard` is collapsed, uses a two-column
grid, includes a chevron control, displays GPS in `WorkoutHero`, and has no
elliptical or stair-climber options. `CardioType`, `WorkoutType`, manual cardio
editing, and the unified plan model do not currently share one complete
taxonomy: manual editing and unified plans already know about elliptical/stairs,
while the picker-facing enums do not.

Implementation:

- Make the Cardio card expanded by default and remove its collapse arrow/button.
- Use a three-column grid for the compact cardio choices.
- Remove the `GPS` label from `WorkoutHero`. Indoor/outdoor is a pre-workout
  setting and controls route tracking; the tile should describe only the
  activity.
- Add canonical `.elliptical` and `.stairs`/`.stairClimber` values consistently
  to the picker-facing app models. Choose one public spelling (`stairClimber`
  is preferred for UI/API clarity), provide Codable raw-value compatibility for
  existing records, and map HealthKit activities that lack a distinct local
  representation without corrupting existing history. This is an app-side
  taxonomy completion; no DB++ schema change is needed.
- Include Run, Cycle, and Swim as deterministic fallback choices. Build a pure
  presenter that takes recent completed cardio history, removes duplicate types,
  keeps the user’s last three distinct types in recency order, then fills any
  missing slots from Run → Cycle → Swim. Examples:
  - no history: Run, Cycle, Swim;
  - only Rowing: Rowing, Run, Cycle;
  - recent Run, Run, Swim, Cycle: Run, Swim, Cycle.
- The recency source should be the local completed cardio records, not a
  nearest-first exercise query and not HealthKit’s raw activity ordering. Keep
  this projection cheap and cached with the Home activity snapshot.
- Show those three choices in one row. Put a `Show more…` row beneath them;
  expanding it reveals the remaining cardio types plus Other. The expanded
  list still uses the three-column grid.
- Keep indoor/outdoor and GPS permission/settings in the pre-workout flow for
  distance-capable types. Do not remove route tracking behavior itself.
- Verify the generic `WorkoutTypePicker` used by other entry points continues
  to work; the compact default behavior is specifically for the Home Start
  Workout surface.

Acceptance:

- Cardio is visibly expanded on first entry, with no arrow button.
- Exactly three recent/fallback activities appear initially in a single row.
- Elliptical and Stair Climber appear after Show more and launch the correct
  cardio recorder.
- No cardio tile contains the string `GPS`.
- The indoor/outdoor choice still determines whether GPS/map collection starts.

### 2.7 Splash subtitle

Change `SplashView` from `Your strength coach` to exactly `Your Fitness, Your
Way`, and update its combined accessibility label. The app supports strength,
cardio, tests, history, and coaching, so the old subtitle is now misleading.

### 2.8 Fix literal Cardio Minutes interpolation

`HomeWeekDashboardSection.cardioMinutes` currently contains literal strings such
as `(Int(dashboard.cardioDetail.loggedMinutes.rounded())) min` instead of Swift
interpolation. This explains the field report exactly.

Implementation:

- Replace every literal interpolation with evaluated values for actual minutes,
  unclassified minutes, and per-zone minutes.
- Keep the existing moderate-equivalent calculation and citation.
- Add a view-level/UI smoke assertion that the rendered Cardio Minutes subtree
  never contains `dashboard.cardioDetail`, `Int(`, or other source-code tokens.
- Add presenter/formatting unit coverage for zero, fractional, and non-zero
  minute values so this cannot regress through string interpolation edits.

### 2.8a Split This Week into independent disclosures

The current `HomeWeekDashboardSection` has one `volumeExpanded` state and one
`Show more…` control. Expanding it reveals Strength workout rows, Cardio
workout rows, Cardio Minutes, Activity Dose, the full muscle-volume list, and
Total Volume all at once. That is the opposite of the summary-first behavior
requested for the rest of the app.

Implementation:

- Replace the single `volumeExpanded` state with independent disclosure state
  for `strength`, `cardio`, and `volume` (or a small reusable keyed disclosure
  state if that produces less SwiftUI invalidation).
- Keep the three compact progress rows visible in the closed state: Strength,
  Cardio, and Volume. Each row gets its own `Show more…` affordance or a
  disclosure treatment directly attached to the row.
- Strength expansion shows only the current-week strength workout list and its
  compact details.
- Cardio expansion shows only the current-week cardio workout list, Cardio
  Minutes, and related intensity detail. Activity Dose belongs here only if it
  is derived from cardio/weekly activity and remains short; otherwise give it a
  separate compact disclosure below the three primary rows rather than hiding
  it inside Volume.
- The muscle-map visualization appears first inside This Week as the compact
  visual summary, before the Strength, Cardio, and Volume detail rows. It is
  visible by default but is not itself an expanded list: muscle-group values,
  set percentages, citations, and Total Volume remain behind the independent
  Volume `Show more…` control. It must not also open Strength or Cardio
  content.
- Permit multiple sections to be open when the user explicitly opens them, but
  default all three closed to keep Today compact. Do not use one global
  animation or one combined accessibility value for all sections.
- Keep the map and per-muscle set values in the Volume disclosure, not in the
  closed progress row. The map itself is the exception: it is the compact
  first element of This Week, while its detailed legend/list remains closed.
  This gives users the visual upgrade without making the launch screen a long
  text dump.
- Replace `home.week.showMore/showLess` with stable identifiers such as
  `home.week.strength.showMore`, `home.week.cardio.showMore`, and
  `home.week.volume.showMore` (plus matching show-less identifiers).

Acceptance:

- Opening Strength does not reveal Cardio or Volume details.
- Opening Cardio does not reveal Strength or Volume details.
- Opening Volume reveals the muscle map and volume details only.
- The default This Week card shows three short summary rows and no long
  all-sections dump; the map is shown first and the detail lists are hidden.
- Accessibility exposes each disclosure independently with its own expanded or
  collapsed state.

### 2.8b Anatomy asset options and cardio marker

Three Wikimedia Commons candidates were reviewed for the mockup and eventual
bundle:

- [`Muscles front and back.svg`](https://commons.wikimedia.org/wiki/File:Muscles_front_and_back.svg)
  — front/back SVG, CC BY-SA 4.0, best for crisp scaling and overlay hit areas.
- [`1105 Anterior and Posterior Views of Muscles.jpg`](https://commons.wikimedia.org/wiki/File:1105_Anterior_and_Posterior_Views_of_Muscles.jpg)
  — OpenStax medical-class diagram, CC BY 4.0, highly legible but raster and
  label-dense.
- [`Skeletal muscles homo sapiens.JPG`](https://commons.wikimedia.org/wiki/File:Skeletal_muscles_homo_sapiens.JPG)
  — public-domain schematic, simplest redistribution terms but less suitable
  for precise modern touch-region mapping.

Use the SVG as the recommended production base, with the OpenStax and
public-domain variants retained as design fallbacks. Bundle the selected
revision locally, record author/source/license in the app attribution file,
and do not make the app depend on a live Wikimedia request.

The map should include a small heart callout connected to the anterior heart
region. The callout reports weekly cardio minutes (and, when available, the
moderate-equivalent total); it is a cardio summary marker, not an anatomical
muscle-volume region. Tapping the heart opens the Cardio detail disclosure.

### 2.9 Progress summary-first simplification

`TrainingProgressView` currently renders the science banner, strength chart,
PR timeline, consistency heatmap, intensity, effort/frequency, test results,
and history as one expanded scroll. This is correct information but poor scan
order on a small screen.

Implementation:

- Keep one `Progress` navigation root and introduce independent disclosure
  sections using the same compact title/subtitle/show-more pattern already used
  on Home.
- Use this order:
  1. Overview/science banner (compact, non-expanding explanation).
  2. Strength over time (open by default because it is the primary progress
     answer).
  3. Test results with a `Perform a Test…` action.
  4. Consistency and PR timeline.
  5. Load intensity.
  6. Effort and Frequency.
  7. History.
- Default all detail sections except Strength over time closed. Preserve every
  existing chart, metric, citation, and navigation destination behind its
  disclosure; this is not a data-removal change.
- Make the controls VoiceOver-readable with stable identifiers and explicit
  expanded/collapsed values.

### 2.10 Remove Today More and relocate its capabilities

The current `MoreView` is a route with Review, Customize, Learn, and App
sections. Removing it is safe only after every destination has a deliberate
home.

Destination map:

| Existing More item | New location |
| --- | --- |
| Workout History | My History on Today and Progress > History |
| Planned Workouts | My Workouts > Show more… |
| Tests | Progress > `Perform a Test…` |
| Saved Workouts | Settings > Workouts/Library section |
| Exercises | Settings > Exercises section |
| Coach Preferences | Settings > Coach section |
| Coach Insights | Today > Observations and Settings > Coach section |
| Coach Methodology | Settings > Coach section |
| Coach Research Updates | Settings > Coach section |
| About the Coach | Settings > Coach/About section |
| App Settings | Settings tab |

The current Settings screen already contains Health, Watch, Cardio, Coach
Research Updates, Coach Methodology, Coach & Plan, Custom Exercises, Excluded
Exercises, data, transparency, sync, About, and Supporter. Before deleting
`MoreView`, add or verify Settings rows for Saved Workouts, Coach Insights, and
About the Coach, and make the Exercises section the authoritative place for
the exercise library/custom/excluded workflows. Do not leave a dead route or a
feature reachable only by an undocumented deep link.

Implementation:

- Add a `settings` tab after Progress in `RootTabView` and render
  `SettingsView()` directly.
- Remove the Today toolbar ellipsis and the `HomeRoute.more` route/view.
- Remove obsolete HomeRoute cases only after searching all call sites.
- Add `Perform a Test…` next to Test Results in Progress; it opens the existing
  `TestsView`.
- Preserve deep links that can still be meaningful by routing them to the
  replacement surface, or explicitly discard only the retired More URL.

### 2.11 Glass bottom tab bar

The adjacent `../parso-tonearm` implementation uses a custom `GlassDock` with a
small horizontal inset, a reusable `adaptiveGlass` modifier, accessibility
labels, and a material fallback. Cadence already has the corresponding
`CadenceGlassSupport`/adaptive-glass primitives, so the correct integration is
to adapt that pattern, not to force a UIKit `UITabBarAppearance` to look like a
floating glass dock.

Implementation:

- Replace the native `TabView` chrome in `RootTabView` with a root ZStack that
  switches among Today, Progress, and Settings, then adds a bottom
  `safeAreaInset`/dock overlay.
- Build a Cadence `GlassDock`/`GlassTabBar` with three equal-width buttons:
  Today, Progress, Settings. Use the same horizontal inset, rounded glass
  background, stroke, shadow, and reduced-transparency fallback as
  `parso-tonearm`.
- Keep each selected screen in its own NavigationStack, preserving paths while
  switching tabs if the current architecture supports it; otherwise reset only
  the selected tab’s path deliberately and test that behavior.
- Remove the `UITabBarAppearance` setup once no native tab bar is used.
- Preserve minimum hit targets, selected-state VoiceOver traits, and UI-test
  identifiers (`tab.home`, `tab.progress`, plus `tab.settings`).
- Verify the dock does not obscure a live workout or bottom action: all roots
  must receive the safe-area inset, and the active workout surface remains the
  existing root-level cover.

## 3. Performance guardrails

The field report also describes prior Today/Plan jerkiness. This change must not
reintroduce work into the render path:

- Keep HealthKit import, coach recomputation, and history projections off the
  main UI render path as they are now.
- Do not decode every scheduled payload repeatedly while rendering. Build one
  lightweight planned-row projection per query refresh and pass it into My
  Workouts and the planned list.
- Compute recent cardio distinct types once in the Home activity snapshot.
- Keep all disclosure content lazy where practical; collapsed Progress sections
  must not construct expensive Charts or history summaries until expanded.
- Add signposts around Home projection and Progress data preparation, then
  compare first-frame and interaction latency before release.

## 4. Test plan to implement with the change

### Pure/unit tests

- Scheduled date/time preservation, same-day past rejection, future-day
  defaulting, day-key stability across time zones, and decoding of legacy
  midnight records.
- Recent-cardio-three presenter: empty history, one type, duplicates, fallback
  ordering, and more than three distinct types.
- Cardio type Codable compatibility and mapping for elliptical/stair climber.
- Cardio minute formatting for logged, unclassified, and zone values.
- Route inventory test or compile-time search guard that no retired More route
  remains referenced.

### iPhone smoke tests

- Launch Today while automatic loading is active: no health/coach/CloudKit
  loading text appears under Today and the first card does not move.
- Supporter badge remains on the date row and does not add a separate header.
- More actions contains Schedule Workout; create a later-today schedule and
  verify its time in My Workouts and Planned Workouts.
- My Workouts contains completed and planned rows, marks planned rows, and its
  Show more opens the planned list.
- My History is at the bottom, collapses/expands, and opens full History.
- Start Workout: Custom Workout is hidden until Show more; Cardio is expanded,
  three-column, three-choice default, with Show more and Elliptical/Stair
  Climber present; no GPS tile text.
- Splash subtitle is `Your Fitness, Your Way`.
- This Week Cardio Minutes shows numbers and never source-code interpolation.
- This Week starts with independent Strength, Cardio, and Volume disclosures;
  the muscle map appears first, opening one does not open the other two, and
  Volume reveals the detailed muscle set list.
- Progress starts summary-first, exposes `Perform a Test…`, and can expand
  each retained detail section.
- Today has no ellipsis/More button; Settings is a tab; Exercises, Saved
  Workouts, Coach items, and Supporter remain reachable in Settings.
- Glass dock has the three tabs, correct selected state, usable hit targets,
  and does not cover bottom content or active workouts.

### Field verification

After the code is reviewed and the tests are green, perform one real-device
check for:

- a scheduled workout later today and one on a future date;
- indoor and outdoor distance cardio, confirming no GPS session indoors;
- a user with no cardio history and a user with only Rowing history;
- a CloudKit restore/sync in progress while Today is visible;
- reduced-transparency and Dynamic Type settings;
- switching Today/Progress/Settings during an active workout.

## 5. Implementation order and completion gate

Implement in one coherent change set in this order:

1. Add/update app-side schedule time semantics and tests.
2. Add the recent-cardio presenter and canonical cardio taxonomy compatibility.
3. Build My Workouts/My History and wire Schedule Workout.
4. Simplify Start Workout and fix Cardio Minutes interpolation.
5. Simplify Progress and move Tests entry.
6. Inventory Settings, remove More, add Settings tab.
7. Adapt the Tonearm glass dock and remove native tab-bar appearance code.
8. Update/add smoke tests and accessibility identifiers.
9. Audit every item in this document, run the permitted unit/static checks, and
   only then prepare the implementation for review/commit.

The plan is complete when every acceptance item above has either a passing
automated assertion or an explicitly listed real-device field check. No
functionality should be removed merely because its old More shortcut was
removed.
