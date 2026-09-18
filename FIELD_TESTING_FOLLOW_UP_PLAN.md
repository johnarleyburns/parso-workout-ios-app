# Field-testing follow-up plan — navigation, This Week, glass dock, and workout picker

Status: implemented and audited 2026-09-18. This document remains the
acceptance record for the committed implementation.

This plan covers the next implementation pass. It is intentionally app-only:
no DB++ schema change is needed, and the existing SwiftData/CloudKit model and
private sync boundary remain unchanged. The work must preserve the current
one-off `ScheduledWorkout` flow, Personalized Workout generation, exercise
history, weekly muscle accounting, and real-device Watch paths.

The implementation must be completed as one coherent UI/navigation pass, then
audited against this document. Do not use a yellow warning placeholder as a
fallback for a failed route: every failure must either present the intended
surface or a user-readable, retryable error state with enough diagnostics to
identify the failed route.

## 1. Field reports converted into acceptance requirements

| ID | Field report | Required outcome |
| --- | --- | --- |
| F1 | This Week's wide muscle SVG is difficult to read in portrait | Split the current SVG at its center: front/left half on the left, back/right half on the right. Put labeled muscle-group callout boxes outside the appropriate edge, with connector lines to the mapped muscle regions. Preserve aspect ratio and keep regions tappable. |
| F2 | Schedule Workout, Personalized Workout, My Workouts → Show More, and This Week → Settings show only a yellow warning icon | All four entry points must open their intended destinations. Shared routing/presentation failures must be diagnosed and fixed, not hidden. Each route needs an explicit loading/error/retry contract and a smoke assertion. |
| F3 | Today, Progress, and Settings scroll content is covered by the bottom dock | Every root surface must receive enough bottom safe-area space for the actual dock, including Dynamic Type and reduced-transparency layouts. The final row/action must remain fully visible and tappable. |
| F4 | The dock is too large compared with `../parso-tonearm` | Match the Tonearm dock dimensions and rhythm: compact outer horizontal inset, compact tab bar padding, glass shape, selected state, and 44-point minimum hit targets without unnecessary visual height. |
| F5 | This Week and My History crowd Today | Add a `This Week` primary tab immediately after `Today`. Move the complete This Week surface and My History there. Today retains the daily action/workout/review flow without those large weekly sections. |
| F6 | Cardio choices are too tall | Make compact cardio tiles square, use the smaller section-card typography, and size the icon/title for the three-column grid. Preserve accessibility and all existing cardio routes. |
| F7 | Cardio Show more is difficult to hit | Give the control the same visual/control height as Quick Start, with generous vertical hit-area margin and a stable accessibility identifier. Preserve the expanded/collapsed state behavior. |
| F8 | Personalized Workout button label is too long | Change the user-facing label to `Workout for You`; keep the existing accessibility identifier and generation behavior stable unless a label-specific test requires a separate accessibility label. |

## 2. Scope and non-goals

### Included

- `RootTabView` tab model, root routing, glass dock, and safe-area policy.
- A dedicated `ThisWeekView` root surface containing the existing This Week
  dashboard and My History.
- Home composition changes so Today no longer renders the weekly map,
  Strength/Cardio/Volume weekly disclosures, or My History.
- Anatomy-map geometry, callout labels, connector lines, tap targets, and
  weekly muscle detail presentation.
- Workout Plan navigation, Schedule Workout presentation, Personalized Workout
  generation presentation, My Workouts Show More, and This Week Settings
  destination diagnosis/fixes.
- Cardio tile geometry/typography and Show more interaction sizing.
- Updated unit/static/UI smoke contracts and accessibility identifiers.

### Explicitly not included

- No change to DB++ exercise records, muscle attribution, or the CloudKit model.
- No change to `ScheduledWorkout` payloads, schedule lifecycle, or schema.
- No change to Personalized Workout scoring, exclusions, history indexes, or
  scientific rules except for presentation/routing error handling discovered
  by the route audit.
- No removal of cardio types, GPS/indoor-outdoor behavior, Watch execution,
  HealthKit ingestion, or workout history.
- No new weekly planning or Plan tab. `This Week` is a read/review dashboard,
  not a weekly plan authoring surface.

## 3. Architecture and ownership changes

### 3.1 Root tab model

Change the root tab enum and dock order to:

1. Today
2. This Week
3. Progress
4. Settings

Use stable identifiers:

- `tab.today`
- `tab.thisWeek`
- `tab.progress`
- `tab.settings`
- `tabBar.glass`

Add `ThisWeekView` rather than leaving the weekly surface embedded in
`HomeView`. It should own a `NavigationStack` and a local path for weekly
detail routes. The weekly view may reuse the existing pure presenters and
background projection values; it must not rebuild the full history graph on the
main actor merely because the user changes tabs.

Preserve safe handling for retired Plan/Handoff/deep links: a retired weekly
Plan destination still routes to Today, while a new explicit This Week deep
link routes to the This Week tab when that behavior is already supported by the
existing handoff contract.

### 3.2 Today composition

`HomeView` should retain this order:

1. Date row and floating Supporter badge.
2. Start Workout and More actions.
3. Resume/in-progress state when applicable.
4. My Workouts (completed today plus today's planned rows).
5. Observations.
6. Readiness.

Remove `HomeWeekDashboardSection` and `HomeMyHistorySection` from the Today
stack. Do not remove the underlying cached projection: This Week consumes the
same immutable weekly snapshot and My History consumes the same week entries.

The transfer of the view must preserve:

- muscle-map region detail sheets;
- direct-first, alphabetic-second exercise history ordering;
- Cardio Minutes formatting and citations;
- separate Strength/Cardio/Volume disclosures;
- This Week settings/Coach preferences destination;
- My History expand then View full history behavior.

### 3.3 Shared weekly projection

Keep the expensive work in the existing background projection. Define a
Sendable/value snapshot boundary that can be supplied to `ThisWeekView` without
passing SwiftData models into the view. If the existing Home projection is
still owned by `HomeView`, extract the reusable value into a shared
`HomeActivityProjection`/`ThisWeekSnapshot` type in `CadenceFeatures`.

The projection must contain only what the two roots need:

- Strength and cardio week entries.
- Weekly muscle status rows and total volume.
- Muscle direct/indirect history rows.
- Cardio minutes/intensity detail.
- Recent cardio types only if the Start Workout picker still needs them.

Switching Today ↔ This Week must not trigger a full SwiftData rescan on the
main actor. A refresh signature should remain the invalidation boundary.

## 4. Anatomy map redesign

### 4.1 Source geometry

Use the currently bundled Option A SVG only. Treat its intrinsic viewBox as the
source coordinate system. Split it at the exact visual midpoint into two
aspect-preserving panels:

- left panel: front half;
- right panel: back half.

Do not stretch the wide source into a portrait rectangle. The implementation
may use one of these equivalent approaches, selected after inspecting the SVG:

- two clipped renderings of the source with the original aspect ratio;
- a generated local asset derived from the source with documented crop bounds;
- a SwiftUI `Canvas`/mask that renders each half into its own measured panel.

The source attribution and license remain in the existing attribution file.
No network-loaded Wikimedia asset is permitted at runtime.

### 4.2 Portrait layout

Build a responsive map layout with three measured zones:

```text
left callouts | front image | back image | right callouts
```

On compact width, the front and back panels remain the central visual and the
callout columns use compact labels. The map must fit without horizontal
scrolling at the supported iPhone widths. On regular width, callout columns may
grow slightly but the image aspect ratio must remain fixed.

Each callout box contains:

- canonical muscle-group display name;
- compact status color/semantic status;
- set count or percentage only when it does not make the map unreadable;
- a minimum 44-point tap target.

Place front-muscle callouts on the left side of the front image and
back-muscle callouts on the right side of the back image. If a muscle is
visually shared or central, use the nearest stable edge and document the
mapping. Avoid crossing connector lines where possible.

### 4.3 Connector lines and interaction

Connector lines must be drawn from the inner edge of each label box to a stable
anchor point in the source-image coordinate system. They must move with the
image when the layout changes; do not hard-code screen pixels.

The color of the label, connector endpoint, and mapped region must come from
the existing weekly status mapping. The heart/cardio marker remains separate
from muscle regions and continues to open Cardio detail.

Tapping either the region or its callout opens the existing dismissible weekly
muscle detail surface. That surface must show:

- current weekly status and credited sets;
- every contributing exercise this week;
- direct/indirect classification;
- sets, reps, and load for each exercise;
- direct rows first, then exercise name alphabetically.

Add VoiceOver labels that identify the muscle, status, credited sets, and the
available detail action. Connector lines themselves are decorative.

### 4.4 Map tests

Add pure geometry/presentation tests for:

- front/back split bounds;
- anchor points remaining inside the correct half;
- left/right callout assignment;
- deterministic ordering of callouts;
- Dynamic Type/compact-width fallback policy;
- status color mapping;
- direct-before-indirect muscle history ordering.

Update smoke coverage to assert the map is on This Week, not Today, that both
front and back callouts exist, and that one callout opens weekly detail.

## 5. Diagnose and repair the yellow warning destinations

This is a shared failure class until proven otherwise. Implement a route audit
before changing individual views.

### 5.1 Reproduction matrix

Capture for each entry point:

| Entry point | Expected destination | Required state to preserve |
| --- | --- | --- |
| Workout Plan → Schedule this Workout | `Schedule Workout` sheet with title/date picker/save | exact reviewed plan snapshot |
| Start Workout → Workout for You | `Workout Plan` in edit mode after generation | generation state, loading/error/retry |
| My Workouts → Show more… | `Planned Workouts` list | today/upcoming/overdue rows |
| This Week → Settings | Coach/This Week settings destination, or Settings root if that is the intended product route | selected tab/path and return route |

For each case record the path before the action, the path after the action,
the presented sheet/full-screen state, and whether the yellow page appears
before or after the SwiftData/CloudKit operation.

### 5.2 Shared route hardening

Audit every `HomeRoute` destination and every `RootTabView` selection change:

- no `NavigationPath` element may contain a live SwiftData model;
- route payloads must be value snapshots with stable `Hashable` semantics;
- every enum case must have exactly one destination;
- destination construction must not force-unwrap an absent exercise,
  schedule, coach snapshot, or model context;
- sheets must be presented only after the originating sheet/path mutation has
  completed when SwiftUI would otherwise race dismissal and presentation;
- background work must publish a value result on MainActor before navigation;
- failed work must set an explicit error state rather than leave an empty
  navigation destination.

Add a small route diagnostics value for debug/UI-test builds containing route
name, source, request ID, and last failure reason. Keep it off production UI
unless the user opens the relevant Settings diagnostics surface.

### 5.3 Per-route fixes

#### Schedule Workout

- Ensure both Home More actions and Workout Plan use the same sheet boundary.
- Make the reviewed `EditablePlan` a value snapshot before opening the sheet.
- Show a real `Schedule Workout` form with title, local date/time, Save, and
  Cancel. Preserve the exact payload on save.
- On save failure, keep the form visible with a clear error and retry.
- On success, dismiss the sheet and return to the correct parent without a
  blank destination.

#### Workout for You

- Rename only the visible action to `Workout for You`.
- Keep the existing `selectWorkout.suggestWorkout` identifier for backward
  compatibility, and use an accessibility label that matches the new copy.
- Keep the calculating overlay, retryable failure alert, and direct transition
  into editable Workout Plan.
- If catalog/history preparation fails, show the existing retry state with the
  reason, never a route containing no content.

#### My Workouts → Show more…

- Ensure the action appends `HomeRoute.plannedWorkouts` only after the current
  Home interaction is complete.
- Use a value projection for planned rows and handle an empty/failed payload
  with a meaningful empty/error state.
- Preserve today, upcoming, and overdue sections plus Start, Resume,
  Reschedule, and Delete.

#### This Week → Settings

- Decide and document the intended destination: the existing Coach & Plan
  preferences route or the Settings tab's Coach section. Prefer the Settings
  tab/Coach route if the user expects global settings, while preserving an
  explicit back path to This Week.
- Replace any route that constructs a view with a missing environment or model
  context.
- Ensure the tab selection and navigation path are reset deterministically when
  entering Settings from This Week, and returning lands on This Week.

### 5.4 Route tests

Add pure route-inventory tests that enumerate these four actions and assert a
non-empty destination contract. Add UI smoke assertions for the destination
navigation bars/content identifiers and for the absence of a warning-only
surface. Add debug-only route failure logging around path mutation and sheet
presentation; do not log workout contents or private health data.

## 6. Root safe area and glass dock

### 6.1 Match the Tonearm dock

Create/reuse a Cadence `GlassDock`/`GlassTabBar` with the Tonearm dimensions:

- dock outer horizontal padding: 12 points;
- tab bar horizontal padding: 6 points;
- tab bar vertical padding: 9 points;
- tab spacing and four equal-width items;
- continuous glass shape with approximately 26-point corner radius;
- selected tint and unselected secondary tint;
- material/stroke fallback when Reduce Transparency is enabled;
- each button retains at least a 44×44 hit target.

Do not use the current larger outer capsule padding of 20 horizontal plus 8
content padding as the visual target. Measure the final rendered height and
use that same value for the root content inset.

### 6.2 Safe-area policy

Apply the dock exactly once at the root using `safeAreaInset(edge: .bottom)`.
Expose a shared `CadenceDockMetrics` value for the dock height and content
clearance. Do not add ad-hoc bottom padding independently to Today, This Week,
Progress, or Settings unless a screen has an additional fixed bottom control.

Audit these cases:

- Today last My Workouts/Readiness row;
- This Week last My History row and full-history action;
- Progress last History action;
- Settings last Supporter row;
- Workout Plan editor's Save/Cancel inset;
- live workout controls and summary covers;
- Dynamic Type and landscape/regular width.

The bottom-most interactive element must remain fully above the dock and pass
the minimum hit target requirement. A root-level full-screen workout cover must
not inherit or be visually obstructed by the dock.

## 7. Start Workout cardio layout and copy

### 7.1 Square compact tiles

Update `WorkoutHero` only for the compact Start Workout cardio picker, or add a
dedicated `CompactCardioChoice` so other WorkoutHero consumers do not change
unintentionally.

- Use a three-column grid with equal-width square tiles.
- Set the tile aspect ratio to 1:1 after the grid width is known.
- Remove the current `minHeight: 120` behavior for compact cardio tiles.
- Use the same smaller typography scale as the `Cardio` section heading (or a
  documented one-step caption/headline scale that preserves legibility).
- Keep the icon and label vertically balanced and line-limit long names such as
  `Stair Climber` without changing the canonical display name.
- Preserve `startType.*` identifiers, tile accessibility labels, recent-three
  ordering, fallback choices, and expanded additional-cardio behavior.

### 7.2 Show more control

Style the compact-cardio Show more control as a full-width action row:

- same control height as Quick Start's `cadenceActionLabel`;
- at least 12 points of vertical breathing room above and below the label;
- full-width content shape and minimum 44-point hit target;
- stable `selectWorkout.cardioChoices` identifier;
- explicit expanded/collapsed accessibility value;
- no accidental activation when tapping adjacent tiles.

Add a pure shared action-metrics constant if this avoids two controls drifting
apart again.

### 7.3 Rename Personalized Workout

Change all user-facing start-flow copy from `Personalized Workout` to exactly
`Workout for You`, including the navigation/accessibility label where it is
visible. Keep internal names, route IDs, analytics/debug IDs, and model source
values unchanged. Update smoke assertions and empty/error copy consistently.

## 8. Test and verification plan

### Pure tests

- Root tab order is Today, This Week, Progress, Settings.
- Weekly snapshot is reusable without a SwiftData model reference.
- Anatomy front/back crop bounds, label order, connector anchors, and status
  mapping are deterministic.
- Route inventory has valid destinations for the four failing entry points.
- Schedule payload round-trip remains exact.
- Cardio compact choice geometry produces three square tiles.
- Personalized action copy is `Workout for You` while its stable identifier is
  unchanged.

### iPhone smoke additions to the single existing smoke test

- Assert the four-tab order/identifiers and the smaller glass dock contract.
- Assert Today does not contain This Week or My History content.
- Tap This Week and assert the anatomy map/callouts/My History are present.
- Tap a front and/or back callout and assert weekly muscle detail opens.
- Assert the four previously broken entry points open their intended content,
  not a warning-only page.
- Assert bottom content/actions remain hittable after scrolling each root.
- Assert cardio tiles are square within a small geometry tolerance and the
  Show more control has the expected hit height.
- Assert the visible strength action says `Workout for You`.

Keep one normal iPhone smoke test and one watch smoke test. Put deterministic
logic and route/presentation coverage in SwiftPM tests; do not add extra UI
test functions.

### Static/build checks

- `swift test --package-path CadenceCore`.
- `make guardrails`.
- Generic iOS build with signing disabled.
- `git diff --check`.
- No simulator or device execution during implementation review unless the
  owner explicitly requests the release smoke gate.

### Manual field retest

After the implementation and release smoke gate are green, retest on the
attached iPhone:

1. Today → This Week → Today tab switching and bottom-most scroll positions.
2. Front/back muscle callouts, connector alignment, and weekly detail rows.
3. Schedule Workout from the plan and from More actions.
4. Workout for You generation with both successful and insufficient-data paths.
5. My Workouts → Show more with today, future, and overdue schedules.
6. This Week → Settings and return path.
7. Indoor/outdoor cardio and expanded cardio taxonomy.
8. Reduced Transparency, Dynamic Type, portrait, and landscape/regular width.
9. Active workout and summary surfaces while the glass dock is visible.

## 9. Implementation order and completion gate

1. Reproduce and instrument the four warning-only routes; add route inventory
   tests before changing layout.
2. Extract/reuse the weekly value snapshot and add `ThisWeekView`; move weekly
   content and My History off Today.
3. Add the fourth root tab and implement the Tonearm-sized glass dock plus one
   root safe-area policy.
4. Redesign the anatomy map geometry and detail interactions.
5. Repair/finalize the four route destinations and error states.
6. Make cardio tiles square, size Show more, and rename the strength action.
7. Update accessibility identifiers, pure tests, and the single iPhone smoke
   contract.
8. Run the permitted headless/static checks, audit every acceptance row in this
   document, and record remaining human field checks.

The pass is complete only when all F1–F8 have either a passing automated
assertion or a clearly documented field-only check, no route produces a
warning-only page, bottom content is not covered by the dock, and the plan
audit reports no implementation gap.
