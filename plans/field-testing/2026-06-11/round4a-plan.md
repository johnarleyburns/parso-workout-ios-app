# Round 4 Part A — Workout lifecycle & summary (implementation plan)

**Scope (this plan):** A1 universal Pause/Resume + End (incl. countdown), A2 End
"Are you sure?", A3 always-show Workout Summary, A4 unified history, A5 history
row → summary. **A7 sounds are already done & merged.**

**Explicitly OUT of scope (deferred by the user, 2026-06-11):**
- **A6 Apple-Watch HR backfill** and *all* watch integration → later.
- **Part B (CrossFit)** in full → future.

Parent design: `round4-plan.md` (same dir). This file is the build-ready plan
with unit / integration / UI tests, phased one-PR-each.

---

## Where the code is today (grounding)

| Screen | File | Pause? | End? | Confirm? | Summary after? |
|--------|------|--------|------|----------|----------------|
| Countdown | `Features/Home/PreWorkoutCountdownView.swift` | ❌ (Skip/Cancel only) | n/a | n/a | n/a |
| Strength | `Features/Train/SessionView.swift` | ❌ | ✅ `session.endWorkout` | ❌ (only idle prompt) | ❌ dismiss→Home |
| Outdoor cardio | `Features/Cardio/OutdoorCardioView.swift` | ✅ `outdoor.pause` | ✅ `outdoor.end` | ❌ | ❌ dismiss |
| Indoor cardio | `Features/Cardio/RecordCardioView.swift` | ✅ `record.pause` | ✅ `record.end` | ❌ | ❌ dismiss |
| Interval | `Features/Intervals/IntervalView.swift` | ✅ `interval.pause` | ✅ `interval.end` | ❌ | ❌ dismiss |

Key model facts:
- `WorkoutClock` (CadenceCore) already does pause/resume/end from wall-clock dates
  — reuse it everywhere (cardio + interval already do; strength & countdown don't).
- `WorkoutSession` has `endedAt`, `duration`, `totalVolume`, `exercisesInOrder`,
  `orderedSets`. `CardioWorkout` has `duration`, `distance`, `activeEnergy`,
  `avgHeartRate`, `maxHeartRate`, `orderedHRSamples`, `orderedRouteSamples`.
- Cardio is finalized via `recorder.end() -> CardioWorkoutSummary` then
  `WorkoutRepository.saveRecordedCardio(...)`. Strength finalizes via
  `active.endStrength()` + `context.save()`.
- Recording screens are presented from `HomeView` as `.fullScreenCover` / `.sheet`;
  strength `SessionView` is **pushed** on Home's `NavigationPath`.
- Formatting helpers (`Format.distance/duration/heartRate`, `CardioMath.formatPace`)
  live in the **app** (`Shared/Formatting.swift`), not CadenceCore.
- UI-test seeds live in `App/UITestSeed.swift` (`-seed history` = 5 strength
  sessions w/ Bench Press + Back Squat; **no cardio**). `-preCountdown N` sets the
  countdown seconds (0 by default in tests).

---

## Cross-cutting design decisions (made; don't re-litigate)

1. **`WorkoutClock` is the one timer.** Strength and the countdown adopt it for
   pause. The 1 Hz UI timer is display-only.
2. **A reusable SwiftUI `WorkoutControlBar`** (new, `Features/Shared/`) renders the
   big Pause/Resume + End pair (≥56 pt, high-contrast) and **owns the A2 confirm
   dialog**. Signature:
   ```swift
   WorkoutControlBar(isPaused: Bool,
                     onPauseToggle: () -> Void,
                     onEnd: () -> Void,           // called only AFTER confirm
                     endRole: .destructive,
                     confirmTitle: String = "End workout?")
   ```
   Every in-workout screen swaps its bespoke HStack for this. End always routes
   through the confirm (`confirmationDialog`: "End workout" / "Keep going").
3. **Summary is a pure value built in CadenceCore**, formatted in the view.
   New `WorkoutSummaryData` (raw typed fields, no String formatting) + a builder
   from either model. Keeps it `swift test`-able; the view owns `Format.*`.
4. **Unified history = a typed enum + repo query in CadenceCore**, rendered by a
   single list. Strength keeps its `train.newWorkout` + `session.row` ids so the
   existing FR1/FR4/FR6 suites keep navigating. Cardio rows get new ids.
5. **History row opens the read-only Summary**, not an editor. Resuming an
   *in-progress* workout still happens from the Home resume card (unchanged).
   The set **editor** (`SessionView`) is reachable from the summary via an
   "Edit" affordance for strength (so nothing is lost).
6. **Countdown Pause freezes the count** (does not start the workout); Skip/Cancel
   stay. While paused the tick is ignored.

---

## Data-model deltas (additive only, CloudKit-safe)

No `@Model` schema changes. Two **pure value types** + one repo query, all in
CadenceCore (no SwiftData migration):

```swift
// Sources/CadenceCore/WorkoutSummaryData.swift  (new)
public struct WorkoutSummaryData: Equatable, Sendable {
    public enum Kind: String, Sendable { case strength, cardio }
    public struct ExerciseLine: Equatable, Sendable {
        public let name: String
        public let setCount: Int
        public let topSetWeightKg: Double?   // owner, non-warmup
        public let reps: [Int]
    }
    public let kind: Kind
    public let title: String
    public let date: Date
    public let durationSec: TimeInterval
    public let distanceM: Double?
    public let paceSecPerKm: Double?
    public let calories: Double?
    public let avgHR: Double?
    public let maxHR: Double?
    public let totalVolumeKg: Double?        // strength
    public let setCount: Int                 // strength
    public let exercises: [ExerciseLine]     // strength
    public let hr: [(t: TimeInterval, bpm: Double)]   // cardio chart
    public let route: [(lat: Double, lon: Double)]    // cardio map

    public static func from(session: WorkoutSession) -> WorkoutSummaryData { … }
    public static func from(cardio: CardioWorkout) -> WorkoutSummaryData { … }
}

// Sources/CadenceCore/WorkoutHistory.swift  (new)
public enum WorkoutHistoryEntry: Identifiable, Sendable {
    case strength(WorkoutSession)
    case cardio(CardioWorkout)
    public var id: UUID { … }
    public var date: Date { … }   // session.date / cardio.start
}
extension WorkoutRepository {
    /// All strength + cardio, merged and sorted newest-first.
    public static func unifiedHistory(_ context: ModelContext) throws -> [WorkoutHistoryEntry]
}
```
`paceSecPerKm` for cardio uses `CardioMath.paceSecPerKm` (already in core). For a
strength session `distanceM/pace/avg/max/route/hr` are nil; for cardio
`totalVolumeKg/exercises` are nil. `hr`/`route` tuples avoid leaking `@Model` rows
into the value type.

---

## Phase plan (one branch + PR each, stacked in order)

Each phase: branch → implement (logic in CadenceCore first) → `swift test` →
`xcodebuild` UI suite on a fresh sim → commit w/ spec id + Co-Authored-By → PR →
ff-merge to `main`. Stack 4A-2…4A-4 on their predecessor (they depend on it).

### Phase 4A-1 — CadenceCore: summary + unified-history values
**Branch:** `feat/ft4a-core-summary` (off `main`).
- Add `WorkoutSummaryData` (+ `from(session:)`, `from(cardio:)`).
- Add `WorkoutHistoryEntry` + `WorkoutRepository.unifiedHistory`.
- **Unit tests** (`CadenceCoreTests/WorkoutSummaryDataTests.swift`,
  `WorkoutHistoryTests.swift`):
  - strength session → `.strength`, `totalVolumeKg` == sum of owner working sets,
    `exercises` names/order match `exercisesInOrder`, `setCount` correct,
    cardio fields nil.
  - partner sets excluded from `totalVolumeKg` (reuse §04 invariant).
  - cardio walk → `.cardio`, `distanceM`/`paceSecPerKm`/`avgHR` populated,
    `totalVolumeKg`/`exercises` empty/nil; `durationSec == end-start`.
  - `unifiedHistory` merges a session + a cardio and sorts newest-first by
    `date`/`start`; empty store → [].
- **Gate:** `cd CadenceCore && swift test` green (currently 95 → ~100+).
- No app changes → no UI suite needed, but build the app once to be safe.

### Phase 4A-2 — Universal Pause/Resume + End + confirm (A1, A2)
**Branch:** `feat/ft4a-controlbar` (stacked on 4A-1).
- New `Features/Shared/WorkoutControlBar.swift` (decision #2). ids:
  `workout.pause` (Pause/Resume), `workout.end` (End), and the confirm dialog's
  destructive button `workout.endConfirm`, cancel `workout.endCancel`.
- **Countdown** (`PreWorkoutCountdownView`): add a `@State paused`; gate the tick
  on `!paused`; add the control bar (Pause/Resume + End→Cancel maps to `onCancel`).
  Keep `countdown.skip` (Start now) + `countdown.cancel`. New `countdown.pause`.
- **Strength** (`SessionView`): adopt `WorkoutClock` for the session via
  `ActiveWorkoutModel` (add `pause()/resume()` + `isPaused` to the model, backed by
  its existing `clock`). Replace the bespoke "End Workout" button with the control
  bar. Pause also freezes the idle watchdog (skip `checkIdle` while paused).
- **Cardio/Interval**: swap their bespoke HStacks for the control bar; behavior
  identical but End now confirms. Keep existing ids by setting the bar's ids per
  screen OR migrate tests to `workout.pause`/`workout.end` (see test note).
- **Tests:**
  - *Unit:* extend `ActiveWorkoutModel` pause/resume (move logic to a tiny testable
    helper or assert via `WorkoutClock` directly — already covered, add a
    pause-freezes-elapsed case if missing).
  - *UI (new `FR7LifecycleUITests.swift`):*
    - `testCountdownPause`: launch with `-preCountdown 30`; Start a strength
      workout; on countdown tap `countdown.pause`, wait 2 s, assert
      `countdown.remaining` unchanged; Resume; Skip → session opens.
    - `testStrengthPauseAndConfirmEnd`: start workout, log a set, tap
      `workout.pause` (label flips to Resume), Resume, tap `workout.end` →
      assert confirm dialog, tap `workout.endCancel` (still on session), tap
      `workout.end` again → `workout.endConfirm` → summary appears (4A-3 will
      assert the summary; here just assert we left the session / dialog worked).
    - *Existing-suite updates:* `outdoor.pause/end`, `record.pause/end`,
      `interval.pause/end`, `session.endWorkout` ids change. **Plan: keep the old
      accessibility ids on the control-bar instances per-screen** (pass an `idPrefix`
      so e.g. outdoor → `outdoor.pause`) to avoid editing FR2 tests; only the End
      flow gains the confirm, so add a `workout.endConfirm` tap to FR2 cardio/
      interval end paths. Audit: `FR2CardioUITests` (end run), `FR2IntervalsUITests`.

### Phase 4A-3 — Always show Workout Summary (A3)
**Branch:** `feat/ft4a-summary` (stacked on 4A-2).
- New `Features/Workout/WorkoutSummaryView.swift` rendering `WorkoutSummaryData`:
  title + date + duration; cardio metrics (distance/pace/cal/avgHR/maxHR) + HR
  chart + route map (reuse `RouteMap` from `CardioDetailView`); strength exercises
  + set lines + total volume. Buttons: `summary.done` (→ dismiss to Home),
  `summary.saveHealth` (strength: calls existing `saveStrengthWorkout`; cardio is
  already saved on end so show a ✓/"Saved"). ids: `summary.title`,
  `summary.duration`, `summary.metric.<name>`, `summary.exercise.<name>`,
  `summary.done`, `summary.saveHealth`.
- **Wire-up per screen (decision #3 flow):**
  - *Cardio (cover/sheet):* after `saveRecordedCardio`, set
    `@State finishedSummary = .from(cardio:)` and show `WorkoutSummaryView` in
    place of the live view inside the same cover; `summary.done` dismisses the cover.
    (Build the `CardioWorkout` to pass, or rebuild `WorkoutSummaryData` from the
    `CardioWorkoutSummary` — prefer fetching the saved `CardioWorkout` by id so the
    HR/route relationships are present.)
  - *Interval:* same pattern in `IntervalView.finish()`.
  - *Strength:* on confirmed End, `active.endStrength()` + save, then present
    `WorkoutSummaryView(.from(session:))` as a `.fullScreenCover` over `SessionView`;
    `summary.done` dismisses the cover **and** pops `SessionView` (set a binding /
    call `dismiss()` after the cover closes, or drive both from Home's path).
- **Tests:**
  - *UI (extend `FR7LifecycleUITests`):*
    - `testCardioEndShowsSummary`: start an indoor cardio (e.g. boxing), End →
      confirm → assert `summary.duration` + `summary.done`; Done → back Home.
    - `testStrengthEndShowsSummary`: log a set, End → confirm → assert
      `summary.exercise.Bench Press` + total-volume metric; Done → Home.
    - `testOutdoorRunSummaryHasRoute` (uses fake GPS): End an outdoor run → assert
      `summary.metric.distance` present.
  - *Integration:* the cardio summary must show HR/route when present — assert the
    HR chart id (`summary.hrChart`) appears for a recorded run with fake HR.

### Phase 4A-4 — Unified history + row → summary (A4, A5)
**Branch:** `feat/ft4a-history` (stacked on 4A-3).
- New `Features/History/HistoryView.swift` (replaces `HomeRoute.history → TrainView`).
  - Keeps **`train.newWorkout`** (New Workout) at top and the strength
    **`session.row`** ids; adds cardio rows id `history.cardioRow.<type>`.
  - Rows come from `WorkoutRepository.unifiedHistory`; each row → push
    `WorkoutSummaryData` onto Home's path (`.navigationDestination(for:
    WorkoutSummaryData.self)` → `WorkoutSummaryView`). Strength summary offers an
    "Edit" button → pushes `SessionView` (decision #5).
  - Preserve reuse/delete swipe actions for strength; delete for cardio.
- `HomeView`: register `.navigationDestination(for: WorkoutSummaryData.self)`;
  point `HomeRoute.history` at `HistoryView`. Make `WorkoutSummaryData: Hashable`
  (add `Hashable` — drop the tuple fields from `Hashable` by giving it a stable
  `id: UUID` and hashing that) **or** push a lightweight `HistoryRoute` enum
  instead of the value (simpler/safer — prefer a `case summary(entryID: UUID)`).
  → **Decision:** push `WorkoutHistoryEntry`'s id via a small `Hashable` route and
  rebuild the summary in the destination. Avoids making the big struct Hashable.
- Retire `TrainView` (or leave file unused) once `HistoryView` owns its ids.
- Home "Recent cardio" / "Recent workouts" sections stay; their **rows now also
  open the summary** (cardio row already pushed `CardioWorkout` → change to push
  the summary route; strength row likewise).
- **New UI seed:** add `-seed historyMixed` to `UITestSeed.swift` = the `history`
  strength data **plus** one finished `CardioWorkout` walk (with end, distance,
  avgHR) so the unified list has both kinds.
- **Tests:**
  - *Unit:* (covered in 4A-1 `unifiedHistory`) — add a case asserting a cardio
    inserted between two sessions sorts by date.
  - *UI (extend `FR7LifecycleUITests`):*
    - `testUnifiedHistoryShowsCardioAndStrength`: `-seed historyMixed`; open See-all
      history; assert both a `session.row` (strength) and
      `history.cardioRow.walk` exist.
    - `testHistoryRowOpensSummary`: tap the walk row → `summary.duration` appears
      (not the editor). Tap a strength row → `summary.exercise.*` + an `Edit`
      button (`summary.edit`).
    - *Regression:* re-confirm `goToTab("Train")` → `train.newWorkout` still works
      (FR1/FR4/FR6 navigate through `home.train`).

---

## Test inventory (what "green" means for Part A)

- **CadenceCore (`swift test`):** existing 95 + new `WorkoutSummaryDataTests`,
  `WorkoutHistoryTests` (target ~100+), all green. This is the reliable gate.
- **UI (`xcodebuild … -only-testing:CadenceUITests`):** existing 27 stay green
  (with the control-bar id/confirm updates) **+** the new `FR7LifecycleUITests`
  (≈8 tests). Run non-parallel on a freshly restarted sim
  (id `FC7B2F90-A27B-4BD5-9313-7B267636E165`); watch for Mach -308 → restart
  CoreSimulator and re-run; report real-vs-flaky honestly.
- **Per phase:** never merge a phase whose `swift test` is red or whose UI suite
  regresses an existing FR test.

## Open questions for the user (decision sheet — answer before/at 4A-4)
1. **Strength history row default action:** open read-only Summary with an "Edit"
   button (this plan's choice), or open the editor directly? *(Default chosen:
   Summary + Edit.)*
2. **Cancel vs End semantics on cardio:** today cardio has both `Cancel`
   (discard) and `End` (save+summary). Keep Cancel as a discard (no summary)?
   *(Default: yes — Cancel discards, End saves + shows summary.)*
3. **Countdown End button:** should the countdown's End = cancel back Home
   (discard, nothing started)? *(Default: yes.)*

These have sensible defaults baked in above; flag only if you disagree.

---

## Sequencing recap
4A-1 (core values) → 4A-2 (control bar + pause + confirm) → 4A-3 (summary view +
wire-up) → 4A-4 (unified history + row→summary). Then Part A is complete;
**A6 watch-HR + Part B CrossFit remain deferred.**
