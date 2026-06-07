# §06 — Interval Engine (HIIT + Boxing) with high-visibility color/flash

> Addresses field note **#3 (HIIT and Boxing)**: HIIT with protocol presets
> (Tabata, Norwegian 4×4) where the app runs the timer; boxing round timer (2 or
> 3 min rounds, 1 min / 30 s rest); and a **very prominent full-screen color
> indicator** readable from across the room for low-vision users — whole screen
> **green during work**, **yellow in the last 30 s**, **flashing in the last 3 s**,
> **red during rest** — applied to **both** boxing and HIIT.

Decisions applied: #20 (color system, both modes, color-blind-adjustable), #21
(Tabata + Norwegian 4×4 + custom builder), #22 (boxing 3/1, 2/0.5, + custom), #23
(audio + haptics + optional spoken cues), #24 (summary `HKWorkout`). Depends on
§02 (engine).

---

## Problem (from the field test)

The flagship requirement: a timer that **runs the protocol for you** and a
**whole-screen color state** legible at a distance. Today `CardioType` already has
`.hiit` and `.boxing`, but `RecordCardioView` shows them as a **plain stopwatch**
with numeric tiles — no rounds, no protocol, no color, no cues. There is no
interval structure anywhere in the code.

## What the code does today

- `CardioType.boxing` / `.hiit` exist (`Models.swift`) with symbols; not GPS.
- `CardioRecorder` records elapsed/HR/calories generically; **no rounds/phases**.
- `Haptics.swift` exists (set logged / PR / rest complete patterns) — reusable for
  transition haptics.
- No audio cue infrastructure, no interval model.

## Research — protocols (so the presets are correct)

- **Tabata:** 20 s work / 10 s rest × 8 = 4 min core. Tester's framing: 5 min
  warmup + 8×(20/10) + 5 min cooldown.
- **Norwegian 4×4:** warmup 5–10 min (~50–60% HRmax) → **4 min hard
  (90–95% HRmax) + 3 min active recovery (60–70%)**, repeated **×4** → 5 min
  cooldown. ~38 min total. (Tester said "4 min effort for nordic 4×4" — matches.)
- **Boxing:** rounds of 2–3 min work with 30–60 s rest, repeated for N rounds —
  classic gym round timer.

These map cleanly to one **phase-list** abstraction.

Sources:
- https://peakvo2trainer.com/blog/norwegian-4x4-protocol/
- https://www.myworkout.com/en/4x4-intervals
- (Tabata is the canonical 20/10×8.)

---

## Design

### A. One interval model drives everything (core, pure, testable)

```
public enum IntervalPhaseKind { case warmup, work, rest, cooldown }

public struct IntervalPhase: {
    let kind: IntervalPhaseKind
    let duration: TimeInterval
    let label: String          // "Round 3", "Work", "Recover"
}

public struct IntervalPlan: {
    let name: String           // "Tabata", "Norwegian 4×4", "Boxing 3×1"
    let phases: [IntervalPhase]   // fully expanded sequence
    var totalDuration: TimeInterval { phases.reduce(0){ $0 + $1.duration } }

    static func tabata(warmup:..., rounds:Int=8, work:20, rest:10, cooldown:...) -> IntervalPlan
    static func norwegian4x4(...) -> IntervalPlan          // 4×(4min/3min)
    static func boxing(rounds:Int, round:TimeInterval, rest:TimeInterval) -> IntervalPlan
    static func custom(...) -> IntervalPlan
}
```

An **`IntervalRunner`** (`@Observable`, app layer) walks the phase list against the
**`WorkoutClock`** (§02 — wall-clock, so it survives backgrounding/calls):

```
current phase, index, phaseRemaining(now:), overallRemaining(now:),
isWorkPhase, transition events (phaseDidChange)
```

Because timing is wall-clock, a phone call mid-round doesn't desync the protocol —
on return to foreground the runner recomputes which phase it's in. The §02 idle
watchdog is **disarmed while the runner is active** (decision #7) so a 4-min block
isn't mistaken for "idle."

### B. The full-screen color indicator (decision #20) — the flagship

A `FullScreenColorState` derived purely from the current phase + remaining time:

| Condition | State | Color | Motion |
|-----------|-------|-------|--------|
| work phase, > 30 s left | **WORK** | bright green | solid |
| work phase, ≤ 30 s left | **WARNING** | yellow/amber | solid |
| work phase, ≤ 3 s left | **IMMINENT** | yellow | **flashing** (pulse) |
| rest/recovery phase | **REST** | red | solid |
| warmup / cooldown | **NEUTRAL** | blue/gray | solid |

```
public enum FullScreenColorState { case work, warning, imminent, rest, neutral }
public func colorState(phase:, remaining:) -> FullScreenColorState   // pure, tested
```

The `IntervalView` paints the **entire screen background** that color with only
the essentials overlaid in huge, high-contrast type:

```
┌──────────────────────────────┐
│███████████ GREEN █████████████│
│                              │
│            WORK              │   ← phase label, very large
│           0:43              │   ← phase countdown, enormous (≥120pt)
│         Round 3 / 8          │
│                              │
│   ▮▮▮▮▮▮▮▮░░░  overall        │   ← thin overall progress
│                              │
│   [ Pause ]      [ End ]      │
└──────────────────────────────┘
last 3s → whole screen flashes yellow; rest → whole screen red "REST 0:10"
```

- **Legible from across the room** (the core requirement): the *color is the
  signal*, countdown is secondary. Numerals use the largest rounded weight,
  monospaced digits, max contrast on the fill.
- **Color-blind adjustable (decision #20):** the green/yellow/red are themeable in
  Settings (e.g. a blue/orange/magenta palette), and each state also carries a
  **text label** ("WORK"/"REST") and a **distinct icon**, so meaning never relies
  on color alone (NFR-2 / WCAG: don't encode by color only).
- Honors **Reduce Motion:** the "flash" degrades to a high-contrast border pulse
  or solid-with-icon instead of full-screen blinking (accessibility + avoids
  photosensitivity issues).

### C. Cues beyond color (decision #23)

Every phase transition fires:
- **Haptic** (reuse/extend `Haptics`: distinct patterns for work-start,
  rest-start, last-3s ticks, workout-complete) — felt with the phone in a pocket.
- **Audio beeps** (a short countdown beep on the last 3 s, a different tone on
  phase change) using `AVAudioPlayer`/`AudioToolbox` — **no new dep**. Must set an
  audio session that **mixes with / ducks** the user's music and works with the
  screen locked.
- **Optional spoken announcements** (`AVSpeechSynthesizer`): "Round 3, work",
  "Rest", "Last round" — toggle in Settings, off by default. Great for
  low-vision/no-look use.

### D. Setup screens (presets + custom builder)

**HIIT** (decision #21) launch screen:
```
HIIT
 • Tabata            8 × (20s / 10s)   ~14 min
 • Norwegian 4×4     4 × (4m / 3m)     ~38 min
 • Custom…           build your own
```
Custom builder: warmup, rounds, work, rest, cooldown (+ optional sets-of-rounds).

**Boxing** (decision #22) launch screen:
```
Boxing
 • 3 min / 1 min     rounds: [ 12 ]
 • 2 min / 30 s      rounds: [ 12 ]
 • Custom…           round / rest / count
```
Both feed the same `IntervalPlan` → `IntervalRunner` → `IntervalView`.

### E. Save (decision #24)

On End, write a **summary `HKWorkout`** (`.highIntensityIntervalTraining` for
HIIT, `.boxing` for boxing) with duration + estimated energy + captured HR series
(reuse `saveCardioWorkout` / `saveRecordedCardio` path; `CardioType.hiit/.boxing`
already exist). Round structure is **not** representable in HealthKit — it stays in
the local `CardioWorkout` (optionally persist the plan name in `notes`). Closes
Activity rings (FR-2.5).

---

## Data-model deltas (consolidated in §07)

- **None required** to ship: intervals persist as a `CardioWorkout`
  (`type = .hiit/.boxing`, plan name in `notes`, HR samples attached).
- *Optional later:* a `plan` JSON blob or `rounds` count on `CardioWorkout` if we
  want to render round-by-round history. Not needed for v1 — keep additive.

## Implementation steps

1. **Core:** `IntervalPhase/IntervalPlan` (+ `tabata/norwegian4x4/boxing/custom`
   factories), `FullScreenColorState` + `colorState(...)`, all pure + tested with
   injected `now` via `WorkoutClock`.
2. **`IntervalRunner`** (`@Observable`) on top of `WorkoutClock` (§02);
   `phaseDidChange` events.
3. **`IntervalView`:** full-screen color background, huge countdown/label,
   pause/end, Reduce-Motion + color-blind palettes, big-type accessibility.
4. **Cues:** extend `Haptics`; add a small `IntervalCues` (audio beeps via
   AudioToolbox + optional `AVSpeechSynthesizer`); configure a mixing/ducking
   audio session that works locked.
5. **Setup screens:** HIIT (Tabata / Norwegian 4×4 / custom) and Boxing (3/1,
   2/0.5, custom); route from the §02 type picker.
6. **Save:** finalize → summary `HKWorkout` (hiit/boxing) + local `CardioWorkout`.

## Testing

- **Unit (swift test):** Tabata expands to warmup + 8×(20/10) + cooldown with
  correct total; Norwegian 4×4 = 4×(240/180) + warmup/cooldown; boxing N rounds;
  `colorState` returns work>30s green, ≤30s warning, ≤3s imminent, rest red;
  `IntervalRunner` phase index correct across a simulated background gap
  (wall-clock).
- **UI (iPhone + iPad):** start Tabata → assert full-screen color element + phase
  label + countdown identifiers; advance time (inject clock) → assert state
  transitions green→yellow→red; Pause/End; verify color-blind palette setting
  swaps colors and labels remain.
- **Accessibility:** state announced via VoiceOver; Reduce Motion replaces flash;
  countdown legible at AX5; meaning conveyed by label+icon, not color alone.

## Open questions (resolved)

- Color mapping + applies to both + color-blind adjustable (decision #20). ✔
- Tabata + Norwegian 4×4 + custom builder (decision #21). ✔
- Boxing 3/1 & 2/0.5 + custom (decision #22). ✔
- Audio + haptics + optional speech (decision #23); summary HKWorkout
  (decision #24). ✔
