# Field-Testing Round 4 + CrossFit — 2026-06-11

Two parts: **A) workout lifecycle & summary** (implement now — the user
emphasised *summary at end + history of all workouts*), and **B) CrossFit**
(WOD-of-the-day, movements, a "Crossfit" workout type with benchmark workouts +
a real workout-plan model — designed here, built next).

---

## Part A — Workout lifecycle, summary, and fixes

### A1. Universal Pause/Resume + End (every workout type), incl. during countdown
**Today:** pause/resume exists on cardio & intervals but not strength; the
countdown has Skip/Cancel but no Pause; controls differ per screen.
**Plan:** a shared bottom control bar used by every in-workout screen
(`OutdoorCardioView`, `IntervalView`, `RecordCardioView`, the strength
`SessionView`, and `PreWorkoutCountdownView`):

```
┌──────────────────────────────┐
│            …workout…          │
│  ┌───────────┐ ┌───────────┐ │
│  │  ⏸ PAUSE  │ │  ⏹ END    │ │  ← big, always visible (incl. on countdown)
│  └───────────┘ └───────────┘ │
└──────────────────────────────┘
```
- Countdown gains a **Pause** (freezes the count) alongside Skip/Cancel.
- Strength gains Pause (pauses the idle watchdog + a session clock) + End.
- Pause/End are ≥56pt, high-contrast (low-vision).

### A2. End → "Are you sure?" confirmation
Every **End** shows a confirmation dialog ("End workout? / Keep going") before
finalizing — prevents accidental stops. (Strength already auto-saves; this just
gates the explicit End.)

### A3. Always show a **Workout Summary** at the end
On finalize, push a **`WorkoutSummaryView`** before returning Home:
```
┌──────────────────────────────┐
│  ✓ Walk · 32:10               │
│  Distance  2.4 km             │
│  Pace      13:24 /km          │
│  Avg HR    112   Max 131      │  ← HR section (see A6)
│  Calories  180 kcal           │
│  ┌──────── route map ───────┐ │  (cardio)
│  └──────────────────────────┘ │
│  Exercises / sets (strength)  │
│  [ Done ]   [ Save to Health ]│
└──────────────────────────────┘
```
- One view drives both kinds (a `WorkoutSummary` value built from a
  `CardioWorkout` or a `WorkoutSession`).

### A4. Unified workout history (the walk should appear)
**Cause:** a walk saves as a `CardioWorkout`; "Recent workouts" only listed
strength `WorkoutSession`s. (Round-3 Home already surfaces cardio under "Recent
cardio", so the walk now shows there — but history should be **one unified
list**.)
**Plan:** a combined History that merges strength + cardio by date, each row →
the summary (A5). Home's two recent sections stay; the "See all" history screen
becomes unified.

### A5. History → tap → Summary
Tapping any history row (strength or cardio) opens `WorkoutSummaryView` (A3),
not a bare editor.

### A6. Apple Watch heart rate on an iPhone-recorded workout
**Why it was empty:** by design the iPhone *cannot stream the Watch's live HR*
(that needs an `HKWorkoutSession` on watchOS — the watch app is deferred). The
chest strap streams to the phone; the watch does not.
**Plan (works without the watch app):** the Apple Watch continuously writes HR
samples to HealthKit. On finalize, **query HealthKit for HR samples in the
workout's time window** and attach them to the `CardioWorkout` (avg/max + curve)
when no live strap HR was captured. Add `HealthDataProviding.heartRate(in:)`.
This backfills watch HR into the summary + history.

### A7. Boxing / interval sounds from bundled files
Replace the system-sound beeps with the provided MP3s:
- **opening bell** (work start) → `opening-closing-bell.mp3`
- **closing bell** (rest/round end) → `opening-closing-bell.mp3` (same)
- **30-second warning** → `warning-bell.mp3`
Add the two files (already in repo root) to the app bundle; `IntervalCues`
plays them via `AVAudioPlayer` (preloaded), keeping the haptics. The warning
fires once when a work phase crosses 30s remaining.

---

## Part B — CrossFit (designed here, built next)

### B1. Data model — a real "workout plan" (concrete, unlike the old templates)
The old templates only stored exercise *names*. CrossFit needs **prescribed
work**: scheme + movements + reps + load. New `CadenceCore` types:

```
WorkoutPlan        id, name, source(builtin|crossfit|user), scheme, notes, timeCapSec?
  scheme: forTime | amrap(minutes) | emom(minutes) | rounds(n, restSec) | load(reps...)
PlanItem           order, movement, reps?, distanceM?, weightKgM?/weightKgF?, note
```
- A plan launches into the existing strength `SessionView` pre-loaded (like
  "use previous", but with target reps/weights shown as ghosts to log against),
  with the scheme/time-cap displayed up top. (AMRAP/EMOM/rounds shown as a
  banner + a simple timer; rep logging stays the strength flow.)

### B2. "Crossfit" workout type → pick a benchmark "Girls" workout
Add `WorkoutType.crossfit`. Selecting it lists the benchmark workouts
(researched, Rx loads for ♂/♀):

| Name | Scheme | Work |
|------|--------|------|
| **Fran** | 21-15-9 for time | Thruster (95/65 lb), Pull-Up |
| **Grace** | for time | 30 Clean & Jerk (135/95) |
| **Isabel** | for time | 30 Snatch (135/95) |
| **Cindy** | AMRAP 20 min | 5 Pull-Up, 10 Push-Up, 15 Air Squat |
| **Annie** | 50-40-30-20-10 for time | Double-Under, Sit-Up |
| **Barbara** | 5 rounds, 3 min rest | 20 Pull-Up, 30 Push-Up, 40 Sit-Up, 50 Air Squat |
| **Chelsea** | EMOM 30 min | 5 Pull-Up, 10 Push-Up, 15 Air Squat |
| **Diane** | 21-15-9 for time | Deadlift (225/155), Handstand Push-Up |
| **Elizabeth** | 21-15-9 for time | Clean (135/95), Ring Dip |
| **Helen** | 3 rounds for time | 400 m run, 21 KB Swing (1.5/1 pood), 12 Pull-Up |
| **Jackie** | for time | 1000 m row, 50 Thruster (45 lb), 30 Pull-Up |
| **Karen** | for time | 150 Wall-Ball (20/14) |
| **Nancy** | 5 rounds for time | 400 m run, 15 Overhead Squat (95/65) |
| **Angie** | for time | 100 Pull-Up, 100 Push-Up, 100 Sit-Up, 100 Squat |
| **Mary** | AMRAP 20 min | 5 HSPU, 10 Pistol, 15 Pull-Up |

Seeded as `WorkoutPlan`s in `CadenceCore`.

```
┌──────────────────────────────┐
│  CrossFit                  ✕  │
│  ┌──────────────────────────┐│
│  │ Fran   21-15-9 · ~5 min  ││  → tap → preview → START → session
│  │ Cindy  AMRAP 20 min      ││
│  │ Grace  30 C&J for time   ││
│  │ …                        ││
│  └──────────────────────────┘│
│  ↗ CrossFit movement guide    │  ← opens crossfit.com/crossfit-movements
└──────────────────────────────┘
```

### B3. CrossFit movements in the exercise library
Add a **Crossfit** equipment/category facet + seed the named movements
(Thruster, Clean & Jerk, Snatch, Wall-Ball, KB Swing, Double-Under, HSPU,
Pistol, Ring Dip, Overhead Squat, Box Jump, Burpee, Toes-to-Bar, Muscle-Up, …)
into the §03 library so they're searchable + usable in custom workouts. The
exercise picker shows a **"Movement guide ↗"** link opening
`https://www.crossfit.com/crossfit-movements` in Safari.

### B4. CrossFit "Workout of the Day" home section (top)
A card at the **top of Home**:
```
┌──────────────────────────────┐
│  CROSSFIT.COM · WOD           │
│  ┌──────── image ───────────┐ │
│  │  (og:image from the page) │ │
│  └──────────────────────────┘ │
│  "260611"                     │
│  3 rounds for time: …         │  ← scraped title/description
│  ↗ Open on crossfit.com        │
└──────────────────────────────┘
```
- Fetch `https://www.crossfit.com/<YYMMDD>` (today), parse the workout
  title/description + `og:image`. **Privacy/NFR-3:** network only for this card,
  cached per day, off if offline; the rest of the app stays on-device. A simple
  `CrossFitWODService` (URLSession) with a 1-day cache; failures hide the card.
- Tap → open the URL in the browser (`https://www.crossfit.com/260611`).

### B5. Build order for Part B
1. Core: `WorkoutPlan`/`PlanItem` + the 15 benchmark seeds + tests.
2. CrossFit movements into the §03 library.
3. `WorkoutType.crossfit` + benchmark picker → launch a planned session.
4. Movement-guide link in the picker.
5. `CrossFitWODService` + the Home WOD card (network, cached, optional).

---

## Sequencing
- **Now:** Part A (lifecycle, summary, unified history, watch-HR backfill, sounds).
- **Next PR:** Part B (CrossFit), starting with the `WorkoutPlan` model + seeds.

Sources (CrossFit benchmarks):
- https://wodprep.com/blog/crossfit-benchmark-workouts-girls-best-times/
- https://library.crossfit.com/free/pdf/13_03_Benchmark_Workouts.pdf
- https://www.crossfit.com/crossfit-movements
