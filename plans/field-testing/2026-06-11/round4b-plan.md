# Round 4 Part B — CrossFit + planned-workout infrastructure (implementation plan)

Parent design: `round4-plan.md` §Part B (B1–B5). This file is the **build-ready,
phased** plan. Part A is complete & merged. Scope grew during planning (user
decisions below) into a **planned-workout** round that reuses one core
(`WorkoutPlan`) for CrossFit benchmarks, strength presets, and a custom builder.

Each phase = one branch + PR, **stacked in order**, ending in a runnable, manually
testable build. Pause after each for on-device testing. Logic lands in
`CadenceCore` (`swift test`-verified) first; UI is thin on top.

---

## Decisions (recorded verbatim — 2026-06-11)

1. **WOD card (B5):** *"You are going to try and hit the network, BUT if you
   don't have internet or the site times out, you are going to pick one of the
   crossfit exercises at random from the library (one of the 'Girls' workouts for
   instance, e.g. Alice, Fran) and still give a 'Workout of the Day' but in small
   text you will note (network down, generated WOD for you)."*
2. **Rx units:** *"Display BOTH units, the crossfit unit, and ONLY IF DIFFERENT,
   the preferred unit."* → always show canonical (lb / pood etc.); append the
   user's preferred unit in parens only when it differs (e.g. `95 lb (43 kg)`;
   if the app is set to lb, just `95 lb`).
3. **Phasing / added scope:** *"Fold [movements] into one phase"* with the
   benchmark workouts. Plus:
   - **Interval summary detail:** *"in the summary (this includes history) show me
     my interval details, for instance for Boxing how many rounds, the work vs
     rest breakdown, warmup/cooldown, similar for HIIT: show the exercise type,
     warmup, sets, cooldown."*
   - **Weights start redesign:** *"for weights, don't immediately start my weight
     workout, instead like you do for boxing/hiit, give me a list of types of
     common preset weight workouts (5x5, push, pull, legs, olympic lifts, etc) or
     at the bottom let me create a custom workout picking my own exercises, sets,
     reps, weight, including 'copy from previous workout' and let me select it
     from weight workout history, AND for custom workouts let me name that workout
     optionally, and show it prominently in history so I can more easily select
     from it in the future, then just run the workout."*

---

## Where the code is today (grounding)

| Area | File(s) | Note |
|------|---------|------|
| Start types | `CadenceCore/WorkoutType.swift` | enum `weights/run/walk/cycle/hiit/boxing/other`; `isStrength`, `usesGPS`, `cardioType` |
| Type picker | `Features/Home/WorkoutTypePicker.swift` | hero grid over `WorkoutType.allCases`; `onSelect(type)`; ids `startType.<raw>` |
| Start dispatch | `Features/Home/HomeView.swift` `start(_:)` (l.232) | weights→`begin(.strength)`; hiit/boxing→`intervalType`; gps→outdoor; else timer. Countdown gate via `begin/launch`. |
| Strength session | `Features/Train/SessionView.swift` | renders `exercisesInOrder` + `plannedOnlyNames` ghost cards (`plannedCard`); hosts `WorkoutControlBar`; `finishedSummary` → `WorkoutSummaryView`. |
| Session preload | `WorkoutRepository.startSession(from:)`, `.copyWorkout`, `.reuseSession`; `session.plannedExerciseNames` (delimited string, additive) | ghost mechanism already exists. |
| Library seed | `CadenceCore/ExerciseLibrary.swift` (`seedVersion=2`), `WorkoutRepository.seedStarterLibraryIfNeeded` | idempotent, name-keyed, additive; existing stores backfill. |
| Taxonomy | `CadenceCore/ExerciseTaxonomy.swift` | `Equipment` (has `kettlebell`, `plyometric`, `bodyweight`, `barbell`…), `ExerciseCategory`, `MuscleCatalog`. |
| Interval infra | `CadenceCore/IntervalPlan.swift`, `App/IntervalRunner.swift`, `Features/Intervals/IntervalView.swift`, `IntervalCues`/sounds | `IntervalPlan{phases}`, count timing, bundled bell sounds. |
| Summary value | `CadenceCore/WorkoutSummaryData.swift` (`.from(session:)`, `.from(cardio:)`) | pure typed value; view formats it. Render in `Features/Workout/WorkoutSummaryView.swift`. |
| History | `Features/History/HistoryView.swift`, `WorkoutHistory.swift` (`unifiedHistory`), Home `HistorySummaryRoute` | strength + cardio merged; rows → summary. |
| Cardio model | `CadenceCore/Models.swift` `CardioWorkout` | boxing/hiit saved here as cardio; **no interval params persisted yet**. |
| Formatting | `Shared/Formatting.swift` (`Format.*`), `UnitEntry`/unit pref in `AppSettings` | app-side; CadenceCore stays string-free. |

---

## Cross-cutting design — one `WorkoutPlan` core (new, pure values)

All four planned-workout features (CrossFit benchmarks, strength presets, the
custom builder, the WOD fallback) launch the **same** preloaded strength-style
session. The plan is a **pure value type** (no SwiftData `@Model`, no migration);
built-in catalogs live in code (single source of truth). A session remembers
which plan launched it via **one additive optional field**.

```swift
// Sources/CadenceCore/WorkoutPlan.swift  (new)
public enum PlanSource: String, Codable, Sendable { case crossfit, strengthPreset, user }

public enum WorkoutScheme: Equatable, Sendable, Codable {
    case forTime(rounds: [Int]?, timeCapSec: Int?)   // rounds=[21,15,9] rep-ladder; nil = single pass (items carry reps)
    case amrap(minutes: Int)
    case emom(minutes: Int)
    case roundsForTime(count: Int, restSec: Int?)    // "5 rounds, 3 min rest"
    case strength                                    // plain preset / custom (B-2)
}

public struct PlanItem: Equatable, Sendable, Codable, Identifiable {
    public let id: Int            // stable order
    public let movement: String   // matches an ExerciseLibrary name
    public let reps: Int?         // prescribed reps per round/pass
    public let distanceM: Double? // 400 m run, 1000 m row
    public let loadLb: Double?    // canonical Rx load (male), lb
    public let loadLbFemale: Double?
    public let targetSets: Int?   // strength presets/custom
    public let note: String?      // "1.5/1 pood", "20/14 ball"
}

public struct WorkoutPlan: Equatable, Sendable, Identifiable {
    public let id: String         // stable key: "fran", "preset-5x5"
    public let name: String
    public let source: PlanSource
    public let scheme: WorkoutScheme
    public let items: [PlanItem]
    public let notes: String?
    public var movementNames: [String] { items.map(\.movement) }
    public var schemeSummary: String { /* "21-15-9 for time", "AMRAP 20 min" */ }
}

public enum BenchmarkWorkouts { public static let girls: [WorkoutPlan] = [ … 15 … ] }
public enum StrengthPresets   { public static let all: [WorkoutPlan]   = [ … ] }   // B-2

public enum PlanCatalog {       // resolve a key back to its plan (any source)
    public static func plan(forKey key: String) -> WorkoutPlan?
}
```

**Scheme coverage check (all 15 Girls):** Fran/Elizabeth/Diane =
`forTime(rounds:[21,15,9])`; Annie = `forTime(rounds:[50,40,30,20,10])`;
Angie/Grace/Isabel/Jackie/Karen = `forTime(rounds:nil)` (items carry reps);
Cindy/Mary = `amrap(20)`; Chelsea = `emom(30)`; Barbara = `roundsForTime(5,180)`;
Helen = `roundsForTime(3,nil)`; Nancy = `roundsForTime(5,nil)`.

**Session carries the plan (additive, CloudKit-safe):** add to `WorkoutSession`
```swift
public var planKey: String?   // resolves via PlanCatalog; nil for ad-hoc/legacy
```
`SessionView` resolves `PlanCatalog.plan(forKey:)` to render a **scheme banner**
(top) + **prescription** on each ghost card. Preload still uses
`plannedExerciseNames = plan.movementNames`. New launcher:
```swift
WorkoutRepository.startSession(from plan: WorkoutPlan, in:) -> WorkoutSession
// title = plan.name, planKey = plan.id, plannedExerciseNames = movementNames,
// findOrCreateExercise for each movement, save.
```

**Rx formatting (app side, decision #2):** `Format.rxLoad(lb:, pref:)` →
`"95 lb"` if pref==lb else `"95 lb (43 kg)"`. Lives in `Shared/Formatting.swift`.

---

## Phase plan (one branch + PR each; pause after each)

### Phase B-1 — CrossFit: movements + 15 benchmarks + planned session  ⭐ flagship
**Branch:** `feat/ft4b-crossfit` (off `main`).
Folds the old B1+B2+B3 (movements, plan model, benchmark picker) per decision #3.

- **Core:**
  - New `WorkoutPlan.swift` (types above) + `BenchmarkWorkouts.girls` (15 seeds,
    Rx loads in lb / pood) + `PlanCatalog`.
  - `WorkoutType.crossfit` (+ `displayName "CrossFit"`, `symbol`
    `figure.cross.training` or `figure.strengthtraining.functional`, `isStrength`
    semantics: logs as a session; `cardioType` nil). Add hero gradient color.
  - `WorkoutSession.planKey: String?` (additive). `WorkoutRepository
    .startSession(from plan:)`.
  - ~22 CrossFit movements into `ExerciseLibrary` (Thruster, Clean & Jerk, Snatch,
    Power Clean, Wall-Ball, KB Swing, Double-Under, Handstand Push-Up, Pistol,
    Ring Dip, Overhead Squat, Box Jump, Burpee, Toes-to-Bar, Muscle-Up, Air Squat,
    Sit-Up, Clean, Row (erg), Run (already?), Deadlift (exists), Push-Up/Pull-Up
    (exist)). Bump `seedVersion` → 3. Equipment uses existing facets
    (barbell/kettlebell/bodyweight/plyometric/machine).
- **App:**
  - `WorkoutTypePicker` auto-includes `.crossfit` (iterates `allCases`).
  - `start(.crossfit)` → present new `CrossFitPickerView` (sheet): lists
    `BenchmarkWorkouts.girls` (name + `schemeSummary`); tap → preview (scheme,
    time cap, per-item Rx dual-unit) → **Start** → countdown gate → launch
    `startSession(from:)` → push `SessionView`. Footer link **"Movement guide ↗"**
    → `https://www.crossfit.com/crossfit-movements` (Safari).
  - `SessionView`: when `session.planKey != nil`, show a **scheme banner**
    (`session.planBanner` id) at top (scheme + time cap), and enrich `plannedCard`
    with a prescription subtitle (reps ladder + Rx dual-unit) resolved from the
    plan. Logging/sets unchanged (count-up clock; **no AMRAP/EMOM auto-timer yet —
    B-3**). For-time and rounds are fully usable now.
  - Also add the **"Movement guide ↗"** link to `ExercisePickerView` footer (B3
    of parent).
- **Tests:**
  - *Unit (`WorkoutPlanTests`):* all 15 `schemeSummary` strings; `movementNames`
    match the table; rep-ladder totals (Fran Thruster total = 45); every movement
    name exists in `ExerciseLibrary.starter` (guards typos). `startSession(from:)`
    sets `planKey`, `plannedExerciseNames`, creates exercises.
  - *Unit:* `seedStarterLibraryIfNeeded` adds the new movements to an old store
    (count delta) and is idempotent on a fresh one.
  - *UI (`FR8CrossFitUITests`):* `startType.crossfit` → picker lists `Fran`;
    tap → preview shows Rx; Start → `session.planBanner` "21-15-9"; ghost card
    `Thruster` shows reps; log a set; End → summary. (Seed `-preCountdown 0`.)
- **Gate:** `swift test` green; UI suite green. **Pause → manual test.**

### Phase B-2 — Weights start redesign (presets + custom + naming + copy-previous)
**Branch:** `feat/ft4b-weights-start` (stacked on B-1; reuses its plan infra).
- **Core:** `StrengthPresets.all` as `WorkoutPlan`s (`source: .strengthPreset`,
  `scheme: .strength`): **5×5** (Squat/Bench/Row 5×5), **Push**, **Pull**,
  **Legs**, **Upper**, **Lower**, **Full Body**, **Olympic Lifts** (Snatch / Clean
  & Jerk / Front Squat / Overhead Squat). Items carry `targetSets`/`reps`, no load.
  `PlanCatalog` resolves these too.
- **App:** new `WeightsStartView` (replaces the immediate `begin(.strength)`):
  - Section **Presets** — `StrengthPresets.all` cards → preview → Start (countdown
    gate) → `startSession(from:)` (ghost cards show target sets×reps; no Rx).
  - Row **"Copy from previous"** → existing `PreviousWorkoutPicker`/`copyWorkout`
    over weight history (select a past named workout) → start.
  - Section **Custom** — `CustomWorkoutBuilderView`: add exercises (reuse
    `ExercisePickerView`), set target sets/reps (and optional starting weight),
    an **optional name** field → creates a session (`title = name` or "Workout")
    and starts it. (Persist as an ad-hoc plan? No — just a named session.)
  - `start(.weights)` → present `WeightsStartView` instead of `begin(.strength)`.
- **History prominence:** named sessions already store `title`; in `HistoryView`
  + Home recent rows, render a **named** session with a bold title + a small
  "name" badge so it stands out and is easy to re-pick (and it's reusable via
  Copy-from-previous). Add `history.namedRow.<name>` id hook for tests.
- **Tests:** *Unit:* `StrengthPresets` movement names exist in library; preset
  `startSession` preloads correct movements + target sets. *UI:* `startType.weights`
  → `WeightsStartView` (no longer jumps straight to a session); tap **5×5** →
  preview → Start → session with Squat/Bench/Row ghosts; Custom → name "Leg Day"
  → add Squat → Start → session titled "Leg Day"; finish → appears bold in history.
- **Gate + pause.**

### Phase B-3 — Scheme-aware live timer (AMRAP / EMOM / rounds)
**Branch:** `feat/ft4b-scheme-timer` (stacked on B-1).
- **Core:** a small `PlanTimer` deriving display state from `WorkoutScheme` +
  elapsed (reusing `WorkoutClock`): `forTime` = count-up; `amrap` = countdown from
  cap, `isComplete` at 0; `emom` = current-minute index + seconds-to-next-minute;
  `roundsForTime` = round counter (+ rest windows). Pure, unit-tested.
- **App:** the `SessionView` scheme banner becomes **live** for crossfit sessions:
  shows the count-up/down, AMRAP auto-suggests End at cap (haptic + bell from the
  bundled sounds), EMOM beeps each minute (reuse `IntervalCues`). Pause/Resume via
  the existing `WorkoutControlBar` freezes it.
- **Tests:** *Unit (`PlanTimerTests`):* AMRAP remaining + completion; EMOM minute
  rollover; rounds counter. *UI:* AMRAP `Cindy` banner counts down; EMOM `Chelsea`
  shows minute marker. (Use a seeded fast cap if needed for test speed.)
- **Gate + pause.**

### Phase B-4 — Interval / Boxing / HIIT detail in summary + history
**Branch:** `feat/ft4b-interval-summary` (off `main`; independent of B-1/2/3).
- **Core:** persist interval params on the saved workout. Add additive optionals
  to `CardioWorkout`: `intervalRounds: Int?`, `intervalWorkSec: Int?`,
  `intervalRestSec: Int?`, `intervalWarmupSec: Int?`, `intervalCooldownSec: Int?`
  (or a single Codable `intervalSummaryData: String?`). `IntervalView.finish()`
  captures these from its `IntervalPlan` when saving via `saveRecordedCardio`.
  Extend `WorkoutSummaryData` with an optional `interval: IntervalBreakdown?`
  (rounds, work, rest, warmup, cooldown, type) built in `.from(cardio:)`.
- **App:** `WorkoutSummaryView` renders an **"Intervals"** section for boxing/hiit:
  "12 rounds · 3:00 work / 1:00 rest · warmup 0:00 · cooldown 0:00" (boxing);
  HIIT shows type + warmup + sets + cooldown. Same data shows when opened from
  history (it flows through the summary). ids `summary.interval.*`.
- **Tests:** *Unit:* `.from(cardio:)` builds the breakdown from stored params;
  nil for plain cardio (walk). *UI:* finish a Boxing interval → summary shows
  `summary.interval.rounds`; open it from history → same.
- **Gate + pause.**

### Phase B-5 — CrossFit Workout-of-the-Day home card (network + local fallback)
**Branch:** `feat/ft4b-wod-card` (stacked on B-1; needs the benchmark catalog).
- **Service:** `CrossFitWODService` (app `Services/`, URLSession): GET
  `https://www.crossfit.com/<YYMMDD>`, parse `<title>`/workout description +
  `og:image`; **1-day cache** (UserDefaults/file). **On timeout/offline/parse
  fail → fallback** (decision #1): pick a **random** `BenchmarkWorkouts.girls`
  plan (seeded RNG by date so it's stable per day), present its name +
  `schemeSummary` + item list as the WOD, with small caption
  **"(network down — generated a WOD for you)"**. Network used **only** here
  (NFR-3); failures never block.
- **App:** `CrossFitWODCard` at the **top of Home** `VStack` (above `statRow`).
  Real WOD → tap opens the crossfit.com URL in Safari. Generated WOD → tap →
  CrossFit preview/Start (launch that benchmark via B-1). Card hidden until
  loaded; offline shows the generated card (never empty, per decision #1).
- **Tests:** *Unit:* fallback picker is deterministic per date + returns a valid
  plan; cache returns same-day result without refetch. (Parsing tested against a
  saved HTML fixture; **no live network in tests**.) *UI:* with a stubbed
  service (`-stubWOD generated`), Home shows `home.wodCard` + the
  "generated" caption.
- **Gate + pause.**

---

## Data-model deltas (all additive, CloudKit-safe)

- `WorkoutSession.planKey: String?` (B-1).
- `CardioWorkout` interval optionals (B-4).
- New **pure value types** (no schema): `WorkoutPlan`/`PlanItem`/`WorkoutScheme`/
  `PlanSource`, `BenchmarkWorkouts`, `StrengthPresets`, `PlanCatalog`, `PlanTimer`,
  `IntervalBreakdown`. New library entries + `seedVersion` bump (B-1).
- No destructive migration; existing sessions have `planKey == nil` and render
  exactly as today.

## Rollout table

| Phase | Branch | Stacked on | Delivers (manual test) | Schema delta |
|-------|--------|-----------|------------------------|--------------|
| B-1 | `feat/ft4b-crossfit` | main | Pick Fran/Cindy → preview Rx → log a CrossFit session; new movements searchable; guide link | `planKey`, lib seed |
| B-2 | `feat/ft4b-weights-start` | B-1 | Weights → preset (5×5/Push/…) or custom (named) or copy-previous; named workouts bold in history | none (value types) |
| B-3 | `feat/ft4b-scheme-timer` | B-1 | AMRAP counts down + auto-end; EMOM minute beeps | none |
| B-4 | `feat/ft4b-interval-summary` | main | Boxing/HIIT summary + history show rounds/work-rest/warmup/cooldown | `CardioWorkout` optionals |
| B-5 | `feat/ft4b-wod-card` | B-1 | Home WOD card (live, or generated-when-offline) | none |

Sequencing: **B-1 first** (builds the plan core). B-2, B-3, B-5 stack on B-1;
B-4 is independent (can interleave). Pause for manual on-device testing after
every phase.

Sources: parent `round4-plan.md`; benchmarks
https://library.crossfit.com/free/pdf/13_03_Benchmark_Workouts.pdf ,
https://www.crossfit.com/crossfit-movements .
