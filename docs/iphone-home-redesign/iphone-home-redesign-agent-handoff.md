# iPhone Home, Free Coach, Plan Tab, Collapsible Workouts, and Field-Test Reliability

## Agentic coding handoff

**Status:** Approved design target, not implemented by this document

**Scope:** iPhone product redesign plus the narrowly required Watch launch, Watch HR relay, and shared interval-timing fixes from field testing

**Interactive references:** [mockup index](index.html), including field-fix states 09–15

**Field-test update:** 2026-08-15. The seven numbered issues in this document are release-blocking. An implementation is not complete because the new Home renders; every issue needs the automated and device evidence in the mandatory exit matrix.

**Roadmap alignment:** `docs/plans/cladiron-mvp-revised/CLADIRON_PLATFORM_SPEC.md` makes self-coaching free and reserves Pro for client management. This handoff implements that tier boundary now without inventing Trainer mode.

Open every HTML page in this directory before changing code. The mockups define information order, labels, default expansion, and route intent. SwiftUI should remain native and responsive rather than reproducing mockup pixels literally.

## Outcome

The iPhone opens to an action-first Home:

1. Start Workout
2. Log Workout
3. This Week: personalized strength and cardio progress
4. Weekly Volume: Legs, Back, Chest, Shoulders, Triceps, Biceps, Core, and Calves
5. Coach’s suggestions: one ranked suggestion by default, all suggestions after Show more…
6. What you did

Coach is standard-tier functionality. The only future Pro boundary is Trainer mode/client management; this project does not build that future UI.

Programs move to a new Plan root tab. A strength summary’s exercise rows become drill-ins to the normal workout review screen. Active and historical workout screens use collapsible exercise cards so only the relevant exercise is expanded.

This field-test round also guarantees:

1. the Watch app reaches its root or a recoverable error surface instead of immediately closing;
2. iPhone can own only one live workout at a time;
3. Apple Watch HR is explicitly started and visibly verified before an iPhone workout relies on it;
4. every strength set can be attributed to Me or a selected/new partner;
5. weight increment controls form an equal-size grid;
6. HIIT/timed-work colors scale with work-interval duration; and
7. set-entry controls respond without one-to-several-second stalls.

## Product decisions

### Root tabs

Use four iPhone tabs, in this order:

1. Home
2. Plan
3. Tests
4. Progress

Rename the current visible “Workout” tab to “Home.” Keep Tests and Progress. Plan uses the current `PlanningView` as its root content for now.

The production iPhone app target is already `TARGETED_DEVICE_FAMILY = 1`; do not add iPad-specific layouts. Watch changes are limited to launch resilience, the phone-requested HR handshake, shared interval signal behavior, and their tests. Do not redesign Watch navigation, Watch strength entry, or its general visual system.

### Home order is fixed

Do not insert Favorites, a Coach hero, a plan card, the old quick-action strip, or promotional content between these sections. Favorite routines and favorite exercises remain reachable in Plan. The resume-workout card is the one allowed exception: when a workout is in progress, place Resume above Start Workout because recovering an active session is the highest-priority action.

### “Scientific recommendations” wording

Be precise about what is personalized:

- **Strength:** completed distinct strength days versus `CoachSchedulePreferences.strengthDaysPerWeek`. Goal and experience affect the recommended training content and volume. Do not claim age changes the strength-day count unless the engine actually encodes that rule.
- **Cardio:** completed moderate-equivalent minutes versus the existing 150-minute research-informed baseline. The user’s age influences HR-zone classification through the existing `TrainingEvent.from(cardio:userAge:)` path.
- **Weekly volume:** working sets versus experience-scaled ranges, with the current training goal shown as context. Avoid calling the range a medical threshold or a precise individual optimum.

Every visible scientific claim must keep a tappable `CitationLink`. Do not expose raw citation IDs.

### Coach suggestion definition

“Coach’s suggestions” is a single ranked presentation list. It may contain:

- safety, pain, or readiness guidance;
- the current weekly strength/cardio recommendation;
- plan-aware `Insight` items;
- actionable volume or progression recommendations;
- the current fitness-test recommendation;
- lower-priority progress observations.

The list is not the same as `coachSnapshot.insights` alone, and it must not show duplicate versions of the same underlying claim.

Ordering is deterministic:

1. Safety/pain/readiness
2. Current-week strength or cardio deficit
3. Muscle-volume or recovery gap
4. Plan/test action
5. Progress observation

Within a category, preserve the engine’s existing priority/confidence/id ordering. Build this merge and de-duplication in `CadenceFeatures`, not in `HomeView`.

Home shows `suggestions.first` by default. `Show more…` reveals all remaining items in place; `Show less` collapses to one. If there are no honest outputs, omit the section—do not manufacture encouragement. Expansion is transient view state and should survive snapshot refreshes during the same Home visit.

### Coach’s Workout versus suggestions

`Coach’s Workout` is a strength start option and launches the current recommendation through the existing editable-plan path. It is not duplicated as a giant Home hero. Coach suggestions explain and recommend; the start chooser is where the person deliberately selects a workout.

### Exercise accordion

The workout page is a single-open accordion with an allowed zero-open state.

- **Active workout default:** expand the current exercise. Before any set is active, use the first unfinished planned/logged exercise. If the workout is blank, none is expanded.
- **Set-entry behavior:** opening a pending or completed set expands its owning exercise before presenting the existing full-screen set editor.
- **After save:** keep the exercise expanded while it has pending sets. After its last planned set completes, expand the next unfinished exercise. Do not auto-advance after an unplanned added set.
- **Manual header tap:** tapping a collapsed exercise opens it and closes the old one. Tapping the open exercise closes it. Manual selection remains until set activity establishes a new current exercise.
- **Review/edit default:** all exercises collapsed.
- **Summary drill-in:** expand and scroll to the tapped exercise.

Collapsed headers must show exercise name, completed/planned set count, and a concise actual summary such as top load or RPE range. They remain useful, not just decorative titles.

Do not persist accordion state to SwiftData, UserDefaults, exports, Watch sync, or CloudKit.

## Field-test findings and mandatory architecture

These are implementation constraints, not optional suggestions. Preserve existing user data and unrelated behavior while making the invalid states unrepresentable.

### FT-01 — Watch app closes immediately

Reference: `09-watch-launch-recovery.html`

Current evidence:

- `Cadence_Watch_AppApp.swift` constructs its `ModelContainer` in a stored-property closure before `WatchRootView` can render.
- Any container-open error reaches `fatalError("Failed to create ModelContainer…")`, which exactly presents to a field tester as the app opening and immediately closing.
- The iPhone has schema-version reset/retry handling; the Watch uses the same schema in a separate local-only store but has no equivalent version or recovery path. An incompatible Watch-local store after an app update is therefore the leading hypothesis, not yet a substitute for a crash log.

Before changing behavior, collect the paired Watch crash report and unified logs and record the exception, failing store URL, OS/build, app version, and whether this was an upgrade or clean install. If the stack does not terminate in model-container creation, fix the proven launch stage as well. The exit criterion is the behavior, not confirmation of the hypothesis.

Introduce a testable Watch bootstrap boundary; do not leave container creation embedded in `App.init`:

```swift
enum WatchStoreBootstrapState {
    case ready(ModelContainer)
    case recovered(ModelContainer, quarantinedAt: URL)
    case degraded(ModelContainer, error: StoreBootstrapError) // in-memory UI host
}
```

The exact type may differ, but the algorithm is fixed:

1. Attempt the normal local persistent store.
2. On failure, log a privacy-safe structured error and move only `default.store`, `default.store-shm`, and `default.store-wal` into a timestamped Application Support recovery directory. Do not recursively delete Application Support and do not overwrite an older quarantine.
3. Retry a fresh persistent store and seed the starter library only after creation succeeds.
4. If retry also fails, create an in-memory container solely so SwiftUI can render the recovery view. Show Try Again and Sync from iPhone; do not present the ordinary workout UI as if persistence were healthy.
5. Never call `fatalError`, force-unwrap a container, or repeatedly delete/quarantine on every render.

Move the schema compatibility/version constant into shared store code and apply it on both platforms. Do not silently delete the quarantined files: an unsynced Watch-only workout may be inside them. Recovery copy must say only that iPhone data is unaffected. Add boot-stage `Logger` events for initial open, quarantine, retry success/failure, seeding, root visible, and recovery visible.

### FT-02 — only one live iPhone workout

Reference: `10-active-workout-conflict.html`

Current evidence:

- `ActiveWorkoutModel.startStrength` overwrites `strengthSession` without a guard even though its comment promises one active session.
- Home exposes a Resume card, but direct calls from Home, Plan, and History can still create and start a second strength session.
- Outdoor/timer cardio, intervals, and swim are held in `HomeView` presentation state and are not represented by `ActiveWorkoutModel`; checking only `strengthSession` cannot enforce a product-wide invariant.

Create one `@MainActor` live-workout coordinator/lease shared by the iPhone root. It must represent strength and every live cardio modality independently of whether its UI is presently covered, minimized, or transitioning:

```swift
enum LiveWorkoutKind: Equatable {
    case strength(sessionID: UUID)
    case outdoorCardio(id: UUID, type: CardioType)
    case timerCardio(id: UUID, type: CardioType)
    case interval(id: UUID, type: CardioType)
    case swim(id: UUID)
}

enum WorkoutStartDecision: Equatable {
    case allowed
    case conflict(active: LiveWorkoutDescriptor)
}
```

Do not infer liveness from `fullScreenCover`, `sheet`, or navigation state. The coordinator acquires a lease before sensors/timers start and releases it only after successful save/end or completed discard cleanup. Strength recovery adopts the same lease. Cardio recorders must register their lifecycle with it; a locally dismissed presentation cannot leave an invisible lease or running sensor.

All live start paths go through one `requestStart` API: Home Start, Quick Start, Coach’s Workout, Previous Workout, Plan/routine editor, History reuse, run/walk/cycle, timer cardio, swim, HIIT, boxing, add-ons, and future deep links. Guard twice:

1. At Home Start, if active, show the conflict immediately instead of opening Select Workout.
2. At the final commit boundary, atomically re-check before session creation or sensor start. This closes double-tap and sheet-dismiss races.

Never materialize a new `WorkoutSession` or start HealthKit/location/Watch HR while a conflict is unresolved. Retain a value-typed pending start intent. The conflict actions are:

- **Resume &lt;name&gt;:** clear the pending intent and present the existing workout without changing its clock, data, or sensor ownership.
- **Cancel Previous Workout…:** show a destructive confirmation naming the workout and number of logged sets. On confirm, soft-delete a strength session so it remains restorable from History, or call the modality’s idempotent stop/discard cleanup. Release the lease only when cleanup completes, then continue the pending intent once.
- **Not Now:** clear the pending intent and make no state change.

Manual historical Log Workout is not a live recorder and remains permitted. `startStrength` itself must return/refuse on conflict so a future caller cannot bypass the UI. Two concurrent requests and repeated Resume/Cancel taps must be idempotent.

### FT-03 — Apple Watch HR must be explicitly verified

References: `11-watch-hr-open.html`, `12-watch-hr-live.html`

Current evidence:

- `PreWorkoutHRView`’s Use Watch button immediately calls `onContinue(.watch)` and leaves the gate.
- `AppModel.startWatchWorkout` sets `watchActive = true` immediately after `sendMessage`, even though the Watch may not be open and no sample has arrived.
- `watchError` is not rendered by the gate.
- `HeartRateMonitor.injectExternalBPM` stores a Watch value as `.connected(UUID())`; `strapConnected` can consequently label a Watch sample as a Bluetooth strap.
- The Watch reply handler currently returns `ack: true` after dispatching the command, regardless of Health authorization/session readiness. Command receipt and live HR are different facts.

Replace the booleans with an explicit, testable connection state owned by a Watch-HR relay model:

```swift
enum WatchHRConnectionState: Equatable {
    case unavailable(reason: String)
    case actionRequired(message: String)
    case connecting(requestID: UUID, startedAt: Date)
    case waitingForSample(requestID: UUID, acknowledgedAt: Date)
    case live(requestID: UUID, bpm: Int, receivedAt: Date)
    case timedOut(message: String)
    case failed(message: String)
}
```

Selecting Apple Watch does not dismiss the gate. It shows “Open Cladiron on your Apple Watch and keep it visible,” then Check for Live HR. The command includes a request ID. The Watch returns a structured acknowledgement (`accepted` or a typed rejection); the phone remains in waiting state until a valid BPM tagged to the active request arrives. Acknowledgement alone never enables Continue.

`Continue with Apple Watch` is enabled only while the last Watch sample is fresh (10 seconds is the target window), displays the BPM and “Live from Apple Watch,” and preserves that same stream into the countdown/recorder without issuing a second start. If the sample becomes stale before the tap, return to action-required/retry. Late samples for cancelled or superseded request IDs are ignored.

Represent selected/current HR source explicitly (`bluetooth`, `appleWatch`, `none`) rather than overloading BLE connection state. Existing workout views may consume a unified BPM value, but source label, freshness, sampling eligibility, and cleanup must remain distinguishable. A sample received before the workout clock starts proves readiness but is not persisted as an in-workout sample.

On gate cancel, source switch, Continue without HR, timeout abandonment, recorder save, or recorder discard, send one idempotent stop request when a Watch Health session may be active. Always leave Bluetooth usable. Render reachability, timeout, Health permission rejection, and “Watch app not installed” separately enough to give the user a next action.

### FT-04 — choose or add the performer for every set

References: `13-set-editor-grid.html`, `14-performer-picker.html`

Current evidence:

- `InlineSetEditorView.headerContext` shows a passive “For Me/name” capsule only when `config.hasPartners` is already true.
- `InlineEditorConfig.performerID` is immutable for the lifetime of the editor, and Save writes that original value.
- `SessionView` already owns `allPeople`, `activePartnerIDs`, quick-add/manage sheets, roster rotation, attribution-aware repository calls, and the rule excluding partner sets from owner PRs/Health.

Show “Who did this set?” on every add/edit editor, including solo sessions. The control displays Me or the selected partner and opens a performer picker. Always offer Add Partner. Existing active roster members appear first; historically attributed or recent partners may follow with clear context.

Move `performerID` into the mutable editor draft. Add defaults to `nextPerson()` rotation. Edit preloads the set’s actual `performedBy`, including a person no longer in the active roster. Selecting Me stores `nil`. Save passes the draft value through the existing add/update repository functions; Cancel must not reattribute an existing set.

Add Partner reuses case-insensitive `WorkoutRepository.findOrCreatePerson`, appends the person once to `session.activePartnerIDs`, returns them to the picker, and selects them for the current draft. Adding a partner is an immediate session-roster change and remains if the set editor is later cancelled; only draft attribution is transactional. Preserve rotation semantics: the saved performer becomes the last attributed performer from which `nextPerson()` derives the next default.

Do not fork partner identity or attribution storage. Partner sets continue to be excluded from the owner’s PR and Apple Health data. Update the stable editor configuration when roster data changes without recreating/resetting weight, reps, or effort draft state.

### FT-05 — equal weight-entry grid

Reference: `13-set-editor-grid.html`

Current `LazyVGrid` uses flexible columns but applies `.frame(minHeight:)` after `.buttonStyle(.bordered)`, allowing the styled controls/labels to keep different intrinsic widths. Use four equal flexible columns with equal 8-point spacing and put `.frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)` on every Button label before button styling. `Type…` is the eighth peer cell, not a special intrinsic-width control.

At accessibility Dynamic Type sizes, switch the whole group to two equal columns rather than squeezing/truncating. All cells within the current layout must match width and height within one display point. Keep localized decimal/increment strings readable with minimum scale or two-column reflow; do not special-case only pounds.

### FT-06 — duration-aware interval colors and cues

Reference: `15-interval-timing.html`

Current `IntervalSignal.colorState` receives only remaining time and hard-codes yellow at 30 seconds. A 20-second Tabata work phase is therefore yellow for its entire duration. Both iPhone and Watch render that shared incorrect state; `IntervalCueDecider` independently hard-codes its warning cue at 30 seconds.

For each timed **work** phase with effective duration `D`, calculate:

```text
warningDuration(D) = min(D, ceil((D / 6) / 5) * 5)
```

Then:

- green/work while `remaining > warningDuration`;
- yellow/warning while `3 < remaining <= warningDuration`;
- existing imminent treatment while `remaining <= 3`;
- red/rest and neutral warm-up/cool-down unchanged.

Examples are contractual: 20 → 5 seconds, 30 → 5, 45 → 10, 60 → 10, 90 → 15, 120 → 20, 180 → 30, 300 → 50. Thus Tabata is green for its first 15 seconds, and boxing remains green for 150 then non-green for its final 30.

Put the formula in `CadenceCore.IntervalSignal`. `IntervalRunner` must expose/pass the current effective phase duration, including an extension if the product allows extending a work phase. Do not duplicate math in `IntervalView` or `WatchIntervalView`. Pass the same threshold to `IntervalCueDecider` so the one warning cue begins with yellow; final-three countdown ticks remain unchanged. Use rounded-up whole seconds consistently at tick boundaries and test epsilon values on either side.

This applies to all iPhone and Watch protocols with timed work phases: built-in/custom HIIT, Tabata, boxing, and later interval protocols. A steady-state cardio recorder has no work/rest phase and does not gain an artificial color transition. Preserve color-blind work/rest alternatives, labels/icons, Reduce Motion behavior, pause, skip, and background clock correctness.

### FT-07 — eliminate set-editor tap stalls

Reference: `13-set-editor-grid.html`

Code audit findings:

- Draft arithmetic in `ExpandedSetDraftModel` is constant-time and should not itself create multi-second stalls.
- High-frequency weight/reps/effort buttons call the parent `onActivity()` before/around haptics. That mutates `SessionView`’s `@State IdleWatchdog`, invalidating the large query-backed session view.
- The full-screen-cover closure then calls `inlineEditorConfig()` from live session/query state. That path filters sets, prepares roster data, and can call repository history lookups. Add configurations also create a fresh UUID. This makes an otherwise local draft tap capable of re-evaluating expensive parent work and destabilizing editor identity.
- Session also installs a root simultaneous tap activity gesture, and each haptic call allocates a new feedback generator. Neither is likely to explain seconds alone, but both add duplicate/high-frequency work.

Treat that as the leading code-path diagnosis and prove it with Instruments/signposts before and after. Add signposts for button action received, draft mutation committed, editor body update, editor-context build, repository lookup, and main-thread stalls.

Required remediation:

1. Build and store one stable `SetEditorContext` when the route opens. Its ID, exercise/history hints, original value, and callbacks do not regenerate on a draft tap.
2. Keep weight/reps/effort/performer changes local to a small editor draft model. No SwiftData fetch/save, coach recompute, session render-cache refresh, Watch send, or history query occurs until Save (except the explicitly documented immediate Add Partner roster mutation).
3. Move idle activity recording to a non-render-invalidating relay or throttle/coalesce it off the Session view’s observed state. It still records interaction promptly for idle correctness, but it must not rebuild the parent for every tap. Remove duplicate activity delivery.
4. Reuse and prepare haptic generators. Cache number formatting instead of compiling a regular expression during every render. These are secondary hygiene after render isolation.
5. Keep all mutations on `@MainActor`, preserve every tap in order, and make Save’s existing at-most-once guard independent from button responsiveness.

Performance exit budget on the oldest supported physical iPhone in release configuration:

- touch-up to visible committed value/selection: p95 ≤100 ms;
- no individual tested tap >250 ms;
- ten rapid `+` taps produce exactly ten increments with no lost/reordered event;
- no SwiftData fetch/save and no `SessionRenderModel` rebuild is signposted between draft taps;
- Save still persists once and dismisses once.

Do not “fix” perceived latency with optimistic display that later rolls back, disabling repeated taps, dropping events, removing haptics without measurement, or moving SwiftData model objects unsafely off actor.

## View specifications

### 1. Home

Reference: `01-home.html`

- Keep `NavigationStack`, large “Today” title, localized date, settings button, pull-to-refresh, resume card, contribution coordination, start countdown, HR gate, and existing workout routing.
- Remove `coachTopSurface`, `quickActionsRow`, `coachAmbientSurface`, `testRecommendationCard`, and `favoritesSection` from the render order. Their useful data/actions are consolidated below.
- Add a two-button action row:
  - Start Workout: filled green, `home.startWorkout`
  - Log Workout: secondary, `home.logWorkout`
- Start Workout opens the new unified picker.
- Log Workout opens the unchanged `LogWorkoutPicker`.
- Render This Week using the cached coach snapshot; do not recompute facts in view bodies.
- Render Weekly Volume for `BodyPart.allCases` in canonical order even if every value is zero.
- Display `.abs` as “Core” on this Home component only. Do not rename the persisted enum case in this project.
- Move Weekly Volume out of `TrainingProgressView`; other Progress cards remain unchanged.
- Render one Coach suggestion plus Show more… when `count > 1`.
- Keep What you did last, including View history.

Empty states:

- No history: strength `0 of target`; cardio `0 of 150 min`; all volume rows show `0 sets · below starting range`.
- Missing age: calculate cardio with existing fallback, but profile context says “Age not set”; offer a settings link in the explanatory sheet, not an alert on Home.
- Missing RPE or weight does not suppress counted working sets.
- Deleted and future-dated workouts remain excluded according to existing fact builders.

### 2. Select Workout

Reference: `02-select-workout.html`

Replace the split Home entry points with one sheet titled **Select Workout**.

Strength section, in order:

1. Quick Start
2. Coach’s Workout
3. Start from Previous Workout

Cardio section keeps current options and behavior:

- Run
- Walk
- Cycle
- Swim
- HIIT
- Boxing
- Other Cardio

Reuse the existing downstream routes: `CardioGoalSheet`, interval setup, other-cardio details, HR gate, pre-workout countdown, outdoor/timer/swim recorders, and `WorkoutPlanEditor`.

Do not include “Start from Library” in this sheet; the library now lives in Plan.

Suggested shape:

- Replace or specialize `WorkoutTypePicker` with an iPhone `SelectWorkoutView` rather than nesting the current Weights tile and `WeightsStartView` one level deeper.
- Reuse the current quick-start, recommendation-to-editable-plan, and `PreviousWorkoutPicker` functions. Do not duplicate session creation.

### 3. Log Workout

Reference: `03-log-workout.html`

No inner-flow redesign. `LogWorkoutPicker`, `LogStrengthEntryView`, and `LogCardioView` retain their current behavior and persistence.

### 4. Plan tab

Reference: `04-plan.html`

- Add `.plan` to `RootTabView.Tab`.
- Make `PlanningView` a root tab destination rather than a Home push.
- Give the root its own `NavigationStack` and visible title “Plan.”
- Preserve Routines/Exercises segments, search, favorites, templates, presets, routine info, and editors.
- Remove the old Programs button and `.planning` Home route after all callers and tests migrate.
- Remove the Coach preview entry from Programs. Coach’s Workout lives in Select Workout; the full ranked suggestions live on Home. Coach settings/methodology may remain in Settings.

Future week planning and Trainer clients are explicitly out of scope.

### 5. Workout summary

Reference: `06-workout-summary.html`

For strength only, make each owner and partner exercise roll-up a minimum-44-pt button with a trailing chevron. A short footer says: “Tap an exercise to see every set’s weight, reps, and RPE.”

Tapping pushes/presents the existing `SessionView` with the source exercise focused. Do not expand actual set details inside `WorkoutSummaryView`, and do not create an `ExerciseActualsView` fork.

`WorkoutSummaryData.ExerciseLine` currently contains only `name`, aggregate reps/count, top load, and bodyweight state. Add stable source identity:

```swift
public let sourceExerciseID: UUID?
```

The strength builder must populate it. Keep it optional so manually constructed/cardio/test fixtures remain source-compatible while being updated. A line without source identity renders as a non-interactive roll-up.

For the just-finished strength summary, extend `FinishedSummary` with the source session ID so the root cover can resolve and present review. For history summaries, the `WorkoutSession` is already available in `HistorySummaryRoute`.

Suggested navigation value:

```swift
struct SessionReviewRoute: Hashable {
    let session: WorkoutSession
    let initiallyExpandedExerciseID: UUID?
}
```

Use repository conventions if a UUID-based resolver is cleaner. The load-bearing requirement is stable session + exercise identity, not the exact type name.

### 6. Active and review workout

References: `07-active-workout.html`, `08-review-workout.html`

Add transient expansion ownership to `SessionView`:

```swift
@State private var expandedExerciseID: UUID?
let initiallyExpandedExerciseID: UUID?
```

Extract the state transitions into a pure `SessionExerciseExpansionModel` or equivalent in `CadenceFeatures`. `SessionView` owns state and persistence actions; `ExerciseCardView` renders prepared state.

Change `ExerciseCardView` to accept:

- `isExpanded`
- `isCurrent`
- `onToggleExpansion`
- compact summary text prepared by `SessionRenderModel`

Keep the title/summary portion tappable without wrapping the existing info, menu, and edit controls inside a `Button`; nested buttons are invalid and produce unreliable accessibility behavior. Use separate sibling controls in the header.

When collapsed, omit context lines, column header, set rows, pending rows, and Add/Repeat buttons. When expanded, render current content unchanged. The existing `InlineSetEditorView` full-screen cover remains the set editor.

For a summary focus route, expand first, then use `ScrollViewReader.scrollTo(exerciseID, anchor: .top)` after the render cache exposes that card. Do not rely on a fixed delay.

### 7. Active-workout conflict

Reference: `10-active-workout-conflict.html`

- Keep the Resume card above Start/Log.
- Tapping Resume opens the existing workout directly.
- Tapping Start while any iPhone live-workout lease exists shows “Workout already in progress” with Resume, Cancel Previous Workout…, and Not Now.
- Cancel requires a second destructive confirmation and states whether the strength workout can be restored from History.
- After confirmed cleanup, continue to Select Workout if conflict began from Home Start; if the final launch guard caught a race, continue the captured specific intent.
- VoiceOver focus moves to the dialog title, and dismissal returns to the button that initiated it.

### 8. Watch launch and recovery

Reference: `09-watch-launch-recovery.html`

Normal launch has no new interstitial. Only a proven bootstrap problem shows the compact recovery surface. Provide stable Watch accessibility identifiers:

- `watch.root`
- `watch.storeRecovery`
- `watch.storeRecovery.retry`
- `watch.storeRecovery.syncPhone`

Try Again reruns one serialized bootstrap attempt and shows progress. Sync from iPhone requests application context and then retries a persistent store; it is not a promise to reconstruct an unreadable unsynced Watch workout. The app must remain foregrounded and operable in the recovery surface even if the phone is unreachable.

### 9. Pre-workout Watch HR — action required

Reference: `11-watch-hr-open.html`

The gate title and introduction describe both Bluetooth and Apple Watch, not only a chest strap. Selecting Apple Watch expands its inline status/instructions. Check for Live HR is the action; the primary button reads Connecting… or Waiting for Watch HR… and remains disabled until live. Surface a concise error beside the source card with Retry, not a detached alert.

### 10. Pre-workout Watch HR — live

Reference: `12-watch-hr-live.html`

Show the current integer BPM, LIVE badge, “from Apple Watch,” and last-received freshness. The button label is **Continue with Apple Watch**, not generic Start. Switching to Bluetooth tears down the provisional Watch stream and waits for a real strap value. Continue without heart rate remains available but confirms source `.none` and cleans up both provisional sources.

### 11. Set performer and weight grid

References: `13-set-editor-grid.html`, `14-performer-picker.html`

The performer row belongs above Weight. It is not conditional on already having a partner. The whole row is at least 44 points and announces “Who did this set, Me, button.” Add Partner is also directly visible below it for solo use.

The picker is a sheet over the full-screen editor so dismissing it returns to the untouched draft. Me is always first. Existing active partners follow in roster order; recent/attributed people may follow with context. Add Partner returns to the same sheet and selects the returned person.

Weight increment buttons preserve the existing values for pounds/kilograms and selection semantics. Only geometry changes. In the normal four-column layout the seven values plus Type… form exactly two rows.

### 12. Interval work color states

Reference: `15-interval-timing.html`

No new setup controls are required. The normal interval screen remains a whole-screen signal. At every transition, label and icon continue to convey meaning without color. The warning state’s start is derived from that work phase’s duration; pause freezes state and background/foreground recomputes from wall-clock time without replaying the warning cue.

## Free Coach migration

This is a capability-boundary change, not merely a hidden paywall button.

### Remove standard-tier gates

Audit and update these current paths:

- `HomeView.handleInsightAction`: remove the `store.entitlement.isPro` guard; standard-tier users may stage and confirm changes.
- `HomeView.coachSurfaceState`, `coachShowsUnlockCTA`, `showPaywall`, trial banner, preview/ambient branching: remove from Home.
- `OnboardingView`: completing onboarding saves the selected program and finishes directly. Do not present `PaywallView` before completion.
- `CoachPreviewView` and `CoachPreviewScreen`: no reachable locked/redacted prescription is allowed. Replace callers with functional Coach destinations or retire these views if no caller remains.
- `HomeCoachModel.upsellCTAVisible`, `CoachUpsellPolicy`, and entitlement-driven `CoachSurfacePresenter`: remove when no longer used; delete their obsolete tests rather than preserving a dead standard-tier gate.
- `SettingsView`: remove “Hide Coach offers.” Preserve Coach Methodology, Coach & Plan, and research updates. A general “Hide suggestions” preference is not part of this design.
- `PlanningView`: remove the Coach preview/upsell entry.

### Preserve StoreKit infrastructure carefully

Do not delete product IDs, transaction resolution, purchase restoration, or entitlement persistence merely because no current standard-tier surface uses them. Trainer mode will use Pro later. Until Trainer UI is specified, there should be no misleading “Unlock your Coach” entry point. If `PaywallView` remains in source, update future-facing copy only when a real Trainer entry exists; unreachable dead copy is lower risk than inventing a product users cannot access.

The following must be true under forced `.free` entitlement:

- Coach’s Workout is visible and launchable.
- All Coach suggestions and citations are readable.
- Suggestion actions execute.
- Plan generation/editing paths execute.
- Onboarding completes without purchase UI.

## Presenter and data work

Add a pure `HomeDashboardPresenter` in `CadenceFeatures` (split files if needed to remain under the repository’s 400-LOC rule). It should prepare:

```swift
struct HomeDashboardState {
    let profileContext: ProfileContext
    let strength: WeeklyTargetProgress
    let cardio: WeeklyTargetProgress
    let volumeRows: [VolumeRow]       // always 8, BodyPart.allCases order
    let suggestions: [HomeSuggestion] // ranked, deduplicated, cited
}
```

Inputs should be plain snapshot values already available from `CoachSnapshot`, schedule preferences, settings, and the current test recommendation. Do not pass SwiftUI colors or views into `CadenceFeatures`.

For weekly volume, reuse the same source of truth currently used by Progress:

- `TrainingFacts.weeklySetsByPart`
- `VolumeLandmarks.bands(for:experience:)`
- `VolumeLandmarks.zone(sets:for:experience:)`
- `CitationRegistry.volumeDoseResponse`

The repository marks `VolumeLandmarks` as deprecated in favor of `VolumeGuidance`. Do not silently redesign the science model inside this UI project. Either:

1. move the existing behavior exactly and file a follow-up for `VolumeGuidance`, or
2. migrate Home and its tests to `VolumeGuidance` in a separate, explicitly reviewed phase.

Do not mix the two models on Home and Progress.

## Likely files

### App shell and Home

- `Cadence/Cadence/App/RootTabView.swift`
- `Cadence/Cadence/Features/Home/HomeView.swift`
- `Cadence/Cadence/Features/Home/HomeRouting.swift`
- `Cadence/Cadence/Features/Home/WorkoutTypePicker.swift`
- `Cadence/Cadence/Features/Home/WeightsStartView.swift`
- `Cadence/Cadence/Features/Home/PlanningView.swift`
- new small Home section views as needed

### Coach/free tier

- `Cadence/Cadence/Features/Onboarding/OnboardingView.swift`
- `Cadence/Cadence/Features/Settings/SettingsView.swift`
- `Cadence/Cadence/Features/Coach/CoachPreviewView.swift`
- `Cadence/Cadence/Features/Coach/CoachPreviewScreen.swift`
- `CadenceCore/Sources/CadenceFeatures/HomeCoachModel.swift`
- `CadenceCore/Sources/CadenceCore/CoachSurfacePresenter.swift`
- `CadenceCore/Sources/CadenceCore/CoachUpsellPolicy.swift`

### Week dashboard

- `Cadence/Cadence/Features/Progress/ProgressView.swift`
- `Cadence/Cadence/Features/Progress/VolumeLandmarkBar.swift` (move to Shared or introduce a Home-specific wrapper; do not duplicate logic)
- `CadenceCore/Sources/CadenceFeatures/WeekVolumePresenter.swift`
- new `HomeDashboardPresenter` file(s) in `CadenceCore/Sources/CadenceFeatures/`

### Summary and accordion

- `Cadence/Cadence/Features/Workout/WorkoutSummaryView.swift`
- `CadenceCore/Sources/CadenceCore/WorkoutSummaryData.swift`
- `CadenceCore/Sources/CadenceFeatures/WorkoutSummaryPresenter.swift`
- `Cadence/Cadence/Features/Train/SessionView.swift`
- `Cadence/Cadence/Features/Train/ExerciseCardView.swift`
- `CadenceCore/Sources/CadenceFeatures/SessionRenderModel.swift`
- `CadenceCore/Sources/CadenceFeatures/ActiveWorkoutModel.swift`
- `Cadence/Cadence/Features/History/HistoryView.swift`

### Field-test reliability

- `Cadence/Cadence Watch App Watch App/Cadence_Watch_AppApp.swift`
- new Watch bootstrap/recovery view and pure bootstrap policy files
- `CadenceCore/Sources/CadenceCore/Store.swift`
- `Cadence/Cadence/App/RootTabView.swift`
- `CadenceCore/Sources/CadenceFeatures/ActiveWorkoutModel.swift` or a new shared iPhone live-workout coordinator
- `Cadence/Cadence/Features/Home/HomeView.swift`
- `Cadence/Cadence/Features/History/HistoryView.swift`
- `Cadence/Cadence/Features/Home/PlanningView.swift`
- all iPhone cardio recorder lifecycle views: `RecordCardioView.swift`, `OutdoorCardioView.swift`, `SwimRecordView.swift`, and `IntervalView.swift`
- `Cadence/Cadence/Features/Shared/PreWorkoutHRView.swift`
- `Cadence/Cadence/App/AppModel.swift`
- `Cadence/Cadence/Services/HeartRateMonitor.swift`
- `Cadence/Cadence Watch App Watch App/WatchWorkoutManagerSync.swift`
- `Cadence/Cadence/Features/Train/InlineSetEditorView.swift`
- `Cadence/Cadence/Features/Train/SessionView.swift`
- `Cadence/Cadence/Features/Train/SessionView+Partners.swift`
- `CadenceCore/Sources/CadenceFeatures/ExpandedSetDraftModel.swift`
- `CadenceCore/Sources/CadenceCore/IntervalPlan.swift`
- `CadenceCore/Sources/CadenceFeatures/IntervalRunner.swift`
- `CadenceCore/Sources/CadenceFeatures/IntervalCueDecider.swift`
- `Cadence/Cadence Watch App Watch App/WatchIntervalView.swift`

## Accessibility contract

Use stable identifiers:

- `tab.home`
- `tab.plan`
- `tab.tests`
- `tab.progress`
- `home.startWorkout`
- `home.logWorkout`
- `home.week.strength`
- `home.week.cardio`
- `home.volume`
- `home.volume.<bodyPartRawValue>`
- `home.suggestions`
- `home.suggestions.showMore`
- `home.suggestions.showLess`
- `home.suggestion.<suggestionID>`
- `selectWorkout.quickStart`
- `selectWorkout.coach`
- `selectWorkout.previous`
- keep existing cardio type IDs where practical
- `summary.exercise.<exerciseID>`
- `exercise.toggle.<exerciseID>`
- `exercise.expanded.<exerciseID>`
- `workoutConflict.dialog`
- `workoutConflict.resume`
- `workoutConflict.cancelPrevious`
- `workoutConflict.keepCurrent`
- `workoutConflict.confirmCancel`
- `prehr.source.bluetooth`
- `prehr.source.watch`
- `prehr.watch.instructions`
- `prehr.watch.check`
- `prehr.watch.waiting`
- `prehr.watch.liveBPM`
- `prehr.watch.continue`
- `prehr.continueWithoutHR`
- `setEditor.performer`
- `setEditor.performer.me`
- `setEditor.performer.<personID>`
- `setEditor.performer.add`
- keep existing `setEditor.weight.increment.<value>` and `setEditor.weight.type`
- `interval.phaseLabel`, `interval.countdown`, and existing Watch equivalents remain stable
- Watch launch identifiers are listed in View 8

Requirements:

- All action and accordion targets are at least 44 × 44 pt.
- VoiceOver reads collapsed headers as “Machine Fly, 3 sets, top 100 pounds, collapsed, button.”
- Expanded/collapsed state is exposed without relying on the chevron.
- Volume bars combine textual set count and range status; color is redundant.
- Dynamic Type may stack the Home action buttons vertically and may wrap workout compact summaries. Never truncate a numeric set value.
- Reduce Motion replaces accordion animation with an immediate state change.
- VoiceOver focus moves to the expanded exercise heading after a summary drill-in.
- The conflict dialog announces the active workout name and logged-set count before its actions.
- HR status never relies on a LIVE color alone; announce source, BPM, and freshness.
- Performer rows announce selected state and use names, not initials alone.
- Interval phase label/icon remain the non-color representation of work/warning/rest.

## Unit tests

Add or update headless tests for:

### Home dashboard

- Eight volume rows always render in `BodyPart.allCases` order, including zeros.
- `.abs` produces Home display copy “Core.”
- Strength progress counts distinct completed days and uses the schedule target.
- Cardio progress uses moderate-equivalent minutes and the age-aware facts already supplied.
- Missing age is represented honestly.
- Deleted/future workouts do not affect values.
- Suggestion merge has stable category/engine ordering.
- Equivalent weekly-deficit/volume claims de-duplicate.
- Suggestions keep valid citation IDs.
- No-output state is empty rather than fabricated.

### Free tier

- Forced `.free` produces the same actionable Coach recommendation data as `.pro`.
- Standard-tier staged insight actions are not redirected to a paywall.
- Onboarding completion does not require an entitlement.
- Delete obsolete `CoachUpsellPolicyTests`/`CoachSurfacePresenterTests` only when their production types are removed.

### Summary identity

- Strength summary lines carry source exercise IDs.
- Owner, warm-up-only, and partner line behavior remains correct.
- Summary line equality includes source identity.
- Cardio summaries remain unaffected.

### Accordion state machine

- Active start selects the first unfinished exercise.
- Opening a set selects its owner.
- Header tap toggles open/closed and enforces at most one open.
- Saving a non-final planned set stays on the exercise.
- Saving the final planned set advances to the next unfinished exercise.
- Saving an unplanned added set does not unexpectedly advance.
- Review defaults to none expanded.
- Initial summary focus selects the requested exercise.
- A missing/deleted focus ID falls back to none without crashing.

### FT-01 Watch bootstrap policy

- Normal persistent creation succeeds without quarantine.
- First open fails, exact store sidecars are moved to a unique recovery directory, second persistent creation succeeds, and state is `.recovered`.
- Both persistent attempts fail, in-memory creation succeeds, and state is `.degraded` rather than terminating.
- An existing quarantine is never overwritten.
- Starter seeding runs once against the selected usable container, never the failing one.
- A schema-version transition is applied to Watch as well as iPhone and does not repeat after success.
- Inject deterministic factory/file-system doubles; unit tests must not damage the developer’s real Application Support store.

### FT-02 live-workout coordinator

- With no lease, request returns allowed and acquisition succeeds once.
- While strength is active, requests for strength, outdoor, timer, interval, and swim all return the same conflict and do not invoke their creation/start closures.
- While each cardio modality is active, every other live request conflicts.
- Two same-runloop requests cannot both acquire a lease.
- Resume clears the pending intent without acquiring a second lease.
- Not Now clears pending state and leaves active state unchanged.
- Confirmed strength cancel soft-deletes exactly the active session, releases once, and starts the pending intent once.
- Failed/cancelled cardio cleanup retains the lease and reports an error rather than starting a replacement on top of live sensors.
- Crash-recovered strength adopts the lease and cannot be overwritten by `startStrength`.
- Manual historical logging does not acquire/conflict with a live lease.

### FT-03 Watch HR relay state machine

- Unreachable Watch produces action-required instructions and sends no false active state.
- Accepted command moves connecting → waiting; acknowledgement alone does not become live.
- First valid BPM for the active request moves to live and records source `.appleWatch`.
- BPM from an old/cancelled request is ignored.
- Sample at exactly/inside the freshness window enables Continue; stale sample disables it.
- Timeout and typed Watch rejection produce actionable states.
- Switching to Bluetooth, cancelling, continuing without HR, and finishing/discarding each issue at most one needed stop.
- Continuing live preserves the existing request/stream and does not issue a second start.
- Bluetooth samples remain labeled Bluetooth and Watch injection cannot make `strapConnected` true.
- Pre-clock samples are readiness-only; post-clock samples are eligible for workout persistence.

### FT-04 set performer draft

- Solo add defaults to Me (`performerID == nil`) and still offers Add Partner.
- An active existing partner can be selected and is persisted on Save.
- Editing a partner-attributed set preloads that exact partner even if removed from the active roster.
- Selecting Me on edit writes nil through `WorkoutRepository.updateSet` without duplicating the set.
- Cancelling after a draft selection leaves stored attribution unchanged.
- Add Partner reuses an existing case-insensitive Person, scopes the ID only once, selects it, and leaves the roster member scoped if the set is cancelled.
- Saving a selected partner preserves current partner exclusion from owner PR/Health calculations.
- The next default performer follows existing roster rotation after the newly attributed set.

### FT-06 interval signal and cue timing

- `warningDuration` returns the contractual table for 20, 30, 45, 60, 90, 120, 180, and 300 seconds.
- At `threshold + epsilon` state is work; at threshold state is warning; at 3 seconds it is imminent.
- A 20-second plan is work for the first 15 seconds and warning/imminent for the final 5.
- A 180-second boxing plan retains its existing 30-second warning window.
- Rest, warm-up, cooldown, pause, skip, and completion states are unchanged.
- Extended effective phase duration drives the recalculated threshold.
- `IntervalCueDecider` emits one warning at the computed boundary, never once per tick, and final-three ticks remain one each.
- Phone and Watch callers consume the same runner state; no platform-specific threshold constant remains.

### FT-07 editor isolation and event ordering

- Ten draft increment calls synchronously produce the exact tenth value.
- Activity relay coalescing/throttling does not lose idle activity and does not publish a Session render invalidation per tap.
- Stable editor-context identity does not change across weight, reps, effort, or performer draft mutations.
- Injected history/config-build counters remain zero during draft mutations and increment only on open/explicit refresh.
- Save remains at-most-once after a burst of taps and persists the final value.
- Cancel after a burst performs no set write.

Geometry and human-perceived latency require UI/performance coverage below; unit tests alone cannot sign off FT-05 or FT-07.

## iPhone smoke test changes

Keep the UI suite within the repository cap; modify the existing smoke path rather than adding a large new class.

1. Launch and assert `home.startWorkout`, `home.logWorkout`, and `tab.plan`.
2. Assert old `home.startCardio` and `home.planning` quick actions are absent.
3. Open Plan and assert the planning root.
4. Return Home, open Select Workout, and assert Quick Start, Coach’s Workout, Previous, and one cardio option.
5. Under forced free entitlement, open Coach’s Workout without seeing a paywall.
6. Start strength and assert exactly one exercise exposes `exercise.expanded.*`.
7. Toggle a second exercise and assert the first collapses.
8. Finish the workout, reach Summary, tap Machine Fly (seeded fixture), and assert the review screen opens with its actual set row visible.
9. Tap an actual set and assert the existing full-screen set editor opens with stored weight/reps/RPE.
10. Return Home and assert What you did remains reachable below suggestions.
11. Start strength, minimize to Home, tap Start Workout, and assert the conflict dialog appears. Assert no second session exists. Tap Resume and verify the original session/set count.
12. Repeat the conflict, choose Cancel Previous Workout…, cancel the destructive confirmation once, then confirm it. Assert only after confirmation that Select Workout opens and the old session is recoverable in deleted History.
13. Open a solo set editor, assert `setEditor.performer` and Add Partner exist, add/select a seeded partner, save, reopen, and assert that partner remains attributed. Edit back to Me and assert no duplicate set.
14. At normal Dynamic Type, collect frames for all seven increment buttons and Type…; assert equal width/height within 1 point and a 4 × 2 arrangement. Repeat at accessibility Dynamic Type and assert equal 2-column cells without clipping.
15. In a deterministic UI-test interval clock, assert a 20-second Tabata work screen is green at 14 seconds remaining, warning at 5, and imminent at 3; assert boxing is green at 31 and warning at 30. Do not test color only: assert the exposed signal state/label identifier.
16. Use simulated Watch-HR states to assert action-required instructions, disabled waiting action, live Apple Watch BPM/source, and stale-sample fallback. Simulator coverage is in addition to the physical-pair test.
17. Run the set-editor burst scenario: select 5 lb, tap plus ten times, and assert the displayed total includes every tap and Save persists it once. Capture the signposted latency metric described below.

Update screenshot tests that currently tap `home.planning`; they should tap `tab.plan`. Update helper mappings that treat `home.startWorkout` as the old Strength shortcut.

### Watch smoke tests

Watch completion requires its own target/device evidence:

1. Cold-launch a clean install and assert `watch.root` remains visible for at least 10 seconds.
2. Launch, background, and relaunch five times; no termination or blank screen.
3. Install the prior shipping/internal build, create local Watch data, upgrade in place, and assert root or the designed recovery surface—not a close.
4. With a test-injected first store-open failure, assert recovery succeeds and root becomes visible.
5. With two injected persistent failures, assert `watch.storeRecovery`; Retry remains operable.
6. On a real paired Watch with the Watch app initially closed, start iPhone cardio, follow Open Cladiron, receive a changing Watch BPM on iPhone, continue, and verify it continues through the recorder. Cancel once and verify no Watch workout remains running.
7. Run a 20-second interval on Watch and assert the same 15-second green / final-5-second warning-imminent boundary.

Simulator-only WatchConnectivity is not acceptable evidence for step 6.

### Performance test evidence

Add an XCTest performance path or a small dedicated UI performance test around the existing set-editor smoke flow; do not bloat every smoke run. Measure a release build on the oldest supported physical iPhone with signposts bracketing action receipt and rendered state commit. Record median, p95, maximum, device, OS, build configuration, and run count in the implementation PR/handoff evidence.

The automated burst must fail on lost taps or a total interaction over the agreed budget. Instruments Time Profiler/Main Thread Checker traces must also show no SwiftData fetch/save or `SessionRenderModel` build between draft taps. A simulator pass is useful for regression but does not replace the physical-device latency result.

## Manual acceptance

- Test on the smallest supported iPhone and a current large iPhone in portrait.
- Test landscape because the app currently declares iPhone landscape support.
- Test standard tier, existing Pro purchase, and trial transaction states; Coach behavior must be identical in all three.
- Complete onboarding from a clean install without a paywall.
- Start each cardio type and verify its existing setup/recording flow.
- Log both a past strength and cardio workout.
- Verify Home shows all eight volume groups before and after any strength history exists.
- Verify 0, fractional, in-range, near-high, and above-high volume states.
- Expand/collapse suggestions and refresh Home; verify content re-ranks without a scroll jump.
- Use Summary to open the first, middle, and last exercise.
- Verify summary drill-in for warm-up-only and partner workouts.
- Review and edit an existing Machine Fly set; confirm no duplicate set is created.
- Exercise the accordion with VoiceOver, largest Dynamic Type, Reduce Motion, Increase Contrast, light mode, and dark mode.
- Repeat one-workout conflict handling from every visible live start route, including Plan and History reuse; no route may bypass it.
- While conflict is visible, background/foreground and double-tap Resume/Cancel; active and pending identity remain correct.
- Test Watch launch on clean install and upgrade with a real paired Watch; attach crash-free logs and any quarantine-path log.
- Test Watch HR with the Watch app closed, open-but-not-authorized, live, stale, phone temporarily unreachable, and user cancellation. Confirm source labels never call Watch a strap.
- In a solo strength workout, attribute consecutive sets to Me and two partners; edit each attribution and verify owner/partner summary roll-ups and PR/Health exclusions.
- Inspect pound and kilogram grids on the smallest and largest supported iPhone, portrait/landscape, standard and accessibility Dynamic Type.
- Run Tabata, a 45-second custom work phase, and three-minute boxing on both iPhone and Watch. Observe the exact green/yellow/imminent boundaries and one warning cue.
- Execute the physical-device set-entry performance procedure with haptics enabled and attach before/after signpost measurements.

## Phased implementation

### Phase 0 — Reproduce and establish baselines

- Capture the Watch crash report/boot logs before changing its bootstrap.
- Capture set-editor tap signposts/Time Profiler on the affected physical iPhone and record baseline median/p95/max.
- Add failing pure tests for exclusivity, Watch-HR readiness, performer draft, and interval thresholds.
- Add deterministic UI-test seeds/launch arguments for active conflict, Watch-HR states, grid geometry, and interval clock position.

### Phase 1 — Pure presentation and reliability models

- Add Home dashboard/suggestion presenters and tests.
- Remove Coach standard-tier gating and onboarding paywall path.
- Add the live-workout coordinator/start decision, Watch-HR state machine, duration-aware interval signal/cue policy, performer draft, stable editor context/activity relay, and Watch bootstrap policy with headless tests.
- Keep the visible Home layout unchanged until the new presenter is green.

### Phase 2 — Root IA and entry flows

- Add Home/Plan/Tests/Progress tabs.
- Promote `PlanningView`.
- Build Select Workout and retain Log Workout behavior.
- Wire every iPhone live start/recorder lifecycle through the coordinator and add the conflict/confirm UI before exposing the new Start button.
- Migrate existing smoke/screenshot selectors.

### Phase 3 — Home layout

- Install the fixed section order.
- Move Weekly Volume from Progress and show all eight groups.
- Add collapsed/expanded Coach suggestions.
- Remove old Coach/quick-action/favorites surfaces from Home.

### Phase 4 — Summary drill-in and exercise accordion

- Add stable summary exercise identity and finished-session identity.
- Add the pure expansion state model.
- Make Session exercise cards collapsible in active and review modes.
- Route summary rows to focused review.
- Add performer selection/Add Partner to the full-screen editor, correct the equal weight grid, and isolate high-frequency draft rendering.

### Phase 5 — Watch and interval integration

- Replace the Watch `fatalError` bootstrap with normal/recovered/degraded states and recovery UI.
- Wire the request-ID Watch-HR acknowledgement/sample handshake across phone and Watch.
- Make iPhone and Watch interval renderers/cue players consume the shared duration-aware state.
- Run targeted Watch and iPhone tests before broad cleanup so failures remain attributable.

### Phase 6 — Verification and cleanup

- Remove unreachable preview/upsell code and obsolete tests.
- Run `swift test` in `CadenceCore`.
- Run iPhone and Watch builds, the amended iPhone smoke suite, Watch smoke suite, and physical paired-device HR scenario.
- Run and attach the physical-iPhone set-editor performance evidence; compare it with Phase 0.
- Audit accessibility identifiers and screenshot coverage.
- Update `CLAUDE.md`, `README.md`, and `current_state.md` only when implementation actually ships.

## Acceptance criteria

The feature is complete only when all are true:

- Home has no Coach hero and no Strength/Cardio/Log/Programs quick-action line.
- Start Workout and Log Workout are the top normal actions.
- Select Workout contains the three requested Strength paths and every current cardio choice.
- Coach’s Workout and all Coach suggestion actions work for standard-tier users.
- No onboarding or Home action shows an “Unlock Coach” paywall.
- Plan is a root tab and exposes current programs/routines.
- Home compares weekly strength and cardio activity with clearly explained targets.
- Weekly Volume is removed from Progress and shown on Home with all eight groups, including zero-value groups.
- Home shows only the highest-priority Coach suggestion until Show more… is tapped.
- What you did remains the final Home section.
- Strength summary exercise rows drill into the normal workout screen.
- Active workout has at most one expanded exercise and defaults to the current exercise.
- Review/edit defaults collapsed unless it receives a summary exercise focus.
- Expanded review exposes actual weight, reps, and RPE and uses the existing editor.
- Watch cold launch and upgrade launch remain open on root or the designed recovery state; no model-container failure terminates the app and quarantined files are preserved.
- Every iPhone live start path is blocked by the same active lease; the conflict offers Resume, confirmed Cancel Previous Workout, and Not Now, and a second live workout cannot be persisted or started.
- Apple Watch HR cannot be selected as ready until a fresh, source-labeled BPM arrives; the UI tells the person to open Cladiron on Watch and provides retry/without-HR paths.
- Every set editor exposes Me, existing partners, and Add Partner; Save persists the draft performer and Cancel never changes stored attribution.
- All weight increment/Type cells have equal geometry in 4 × 2 normal and equal 2-column accessibility layouts.
- Every timed work phase uses the last-one-sixth-rounded-up-to-five formula on iPhone and Watch; Tabata and boxing match the contractual boundaries and cues.
- Set-editor input meets the physical-device p95/max budgets, loses no burst taps, and performs no persistence/history/render-cache work between draft taps.
- Swift 6 strict-concurrency build remains warning-free and tests pass.

## Mandatory exit evidence matrix

No row may be waived because another row passed. “Complete” requires a link/path to each automated result plus the stated device evidence in the coding agent’s final handoff.

| Gate | Required headless/unit proof | Required UI/integration proof | Required device/manual proof |
|---|---|---|---|
| FT-01 Watch launch | Bootstrap normal, fail-first/recover, fail-twice/degraded, quarantine/version tests | Watch clean launch, injected failure, relaunch, upgrade smoke | Prior-build upgrade on paired Watch; root/recovery visible ≥10 s; crash report disposition recorded |
| FT-02 one workout | Coordinator conflict matrix, atomic double request, resume/cancel/idempotency tests | iPhone minimize → Start conflict; Resume retains session; confirmed Cancel precedes next start | Exercise every visible strength/cardio route and background/double-tap race |
| FT-03 Watch HR | Request-ID state, ack-vs-sample, freshness, stale/late sample, source and cleanup tests | Simulated action-required → waiting → live → stale UI smoke | Paired Watch initially closed; open app, observe changing BPM through cardio; cancel leaves no Watch workout |
| FT-04 performer | Add/edit/cancel attribution, add/reuse partner, rotation and PR/Health exclusion tests | Solo editor add/select partner, save/reopen, edit to Me, no duplicate set | Me + two partners across consecutive sets and summary roll-ups |
| FT-05 equal grid | Layout-policy tests for 4/2 column choice where practical | Frame assertions within 1 pt at normal/accessibility Dynamic Type | Pounds/kilograms, smallest/large iPhone, portrait/landscape, no clipping |
| FT-06 interval colors | Formula table, epsilon boundaries, cue-once, extensions, unchanged non-work states | Deterministic Tabata/boxing state smoke on iPhone and Watch | Run Tabata, 45-second custom, and boxing; visually/time-confirm boundaries and cues |
| FT-07 set latency | Draft ordering, context stability, activity relay, at-most-once Save tests | Ten-tap burst exact value + signpost performance test | Release build on oldest supported iPhone: p95 ≤100 ms, max ≤250 ms; before/after trace attached |

If real-device connectivity or performance infrastructure is unavailable, the row is **blocked**, not passed. Report it explicitly; do not substitute simulator results.

## Out of scope

- Trainer mode, client roster, invitations, client programming, or Trainer paywall UX
- Full weekly planner/calendar beyond promoting current Programs to Plan
- New scientific recommendation rules or changed citations
- Watch workout accordion or Watch navigation changes
- Recovering/merging data from a quarantined corrupt Watch store beyond preserving the files and restoring app availability
- iPad/Mac layouts
- Data-model migrations for visual expansion state
- Replacing the existing full-screen set editor (this round extends and isolates it; it does not introduce another editor)
