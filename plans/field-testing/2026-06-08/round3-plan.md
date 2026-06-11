# Field-Testing Round 3 — 2026-06-08

Plan + mockups for the latest field-test feedback. Builds on the in-progress
round-2 branch (`feat/ft2-home-session`: pre-workout countdown, session
"Use Previous Workout", Add-Exercise-at-bottom — all kept). This round **revises
the home page and the interval flow**, adds **4 science-backed HIIT protocols**,
and gives the app a **more visual feel**.

---

## 1. Interval engine — explicit START, persistent name, 4 new protocols

### 1a/1c/3 — No auto-start; prominent START; protocol name shown all workout
**Today:** tapping a preset (Tabata/Norwegian, or boxing 3×1) *immediately*
launches the runner. **Wanted:** selecting a preset only *selects* it; a big
**START** button launches it (like a hero button). The chosen protocol's **name
stays on screen the whole workout**.

New `IntervalSetupView` flow (HIIT and Boxing identical):

```
┌──────────────────────────────┐
│  HIIT                     ✕  │
│  PRESETS                     │
│  ┌──────────────────────────┐│
│  │ ✓ Tabata     8×20s/10s   ││  ← tap selects (checkmark + highlight)
│  ├──────────────────────────┤│
│  │   Norwegian 4×4  4×4m/3m ││
│  │   Gibala     8×60s/60s   ││
│  │   SIT (Wingate) 4×30s    ││
│  │   10-20-30   5×(30/20/10)││
│  │   REHIT      2×20s sprint││
│  └──────────────────────────┘│
│  CUSTOM                       │
│   Rounds 8  Work 30s  Rest …  │
│   ( ✓ Custom selected )       │
│                              │
│  ┌──────────────────────────┐│
│  │        ▶  START          ││  ← one prominent button (was "Start Custom")
│  └──────────────────────────┘│
└──────────────────────────────┘
```
- A `selected: IntervalPlan?` state; tapping a preset (or editing custom) sets it.
- One **START** button (`interval.start`) at the bottom → countdown → runner.
- Runner (`IntervalView`) shows `plan.name` in a persistent top bar for the whole
  session:
```
┌──────────────────────────────┐
│  TABATA            ▓ round 3/8│  ← plan name persists top-left, all workout
│██████████ GREEN ██████████████│
│            WORK               │
│            0:14               │
│   [ Pause ]        [ End ]    │
└──────────────────────────────┘
```

### 1c — Four new science-backed protocols (added to presets)
All authored as `IntervalPlan` factories (pure, tested). Structures per the
user's spec:

| Preset | Structure | Factory |
|--------|-----------|---------|
| **Gibala** | 60s work / 60s rest × 8–10 (~20 min) | `gibala(rounds:8, work:60, rest:60)` |
| **SIT / Wingate** | 30s all-out / 4 min recovery × 4–6 | `sit(rounds:4, work:30, recover:240)` |
| **10-20-30** | 5 × (30s easy → 20s moderate → 10s sprint), 2 min break, repeated | `tenTwentyThirty(reps:5, sets:3)` |
| **REHIT** | warm-up → 2 × (20s all-out / 3 min recovery) → cool-down | `rehit(rounds:2, work:20, recover:180)` |

- Gibala/SIT/REHIT fit the existing warmup→rounds×(work/rest)→cooldown shape.
- **10-20-30** needs sub-intensities; modeled per rep as
  `rest(30,"Easy") + work(20,"Moderate") + work(10,"Sprint!")`, 5 reps per set,
  `rest(120,"Recover")` between sets. The 10s sprint shows the warning/flash
  colour as it ends.

---

## 2. Home page — a real dashboard (visible, not hidden under menus)

**Wanted:** remove the step *ring*; show a **simple step count**; show
**workouts this week**, **trends**, **cardio history**, and **workout history**
directly on Home (not behind Stats/History/Cardio buttons).

New `HomeView` (scrolling dashboard):

```
┌──────────────────────────────┐
│ Cadence                   ⚙  │
│ ┌─────────┐ ┌──────────────┐ │
│ │ 8,200   │ │  3 workouts  │ │  ← simple step count + workouts-this-week
│ │ steps   │ │  this week   │ │
│ └─────────┘ └──────────────┘ │
│ ┌──────────────────────────┐ │
│ │   ▶  START WORKOUT        │ │  ← hero (visual; see §4)
│ └──────────────────────────┘ │
│  Trends  ▁▃▅▇▆▄▂  (7-day) →  │  ← inline mini step trend (tap → full Stats)
│                              │
│  Recent cardio          →    │
│   🏃 Run  3.4km  Mon          │  ← inline cardio history (tap row → detail)
│   🥊 Boxing 12r   Sun         │
│                              │
│  Recent workouts        →    │
│   Push Day  12 sets  Tue      │  ← inline strength history (tap → open)
│   Pull Day  10 sets  Sun      │
└──────────────────────────────┘
```
- **Steps:** simple number (`today.steps`) + label — ring removed.
- **Workouts this week:** count of sessions (strength + cardio) in the last 7
  days (`home.weekCount`).
- **Trends:** a compact inline 7-day step bar chart (`today.trendChart`), tappable
  → full `TrendsView` ("Stats").
- **Recent cardio:** top ~3 `CardioWorkout` rows (`cardioRow.<type>`), tap → detail;
  a "→" header link to the full cardio list.
- **Recent workouts:** top ~3 `WorkoutSession` rows, tap → `SessionView`; "→" to
  full history (`TrainView`).
- Settings stays behind the ⚙. The dedicated Stats/History/Cardio screens remain
  reachable via the "→" links (and Settings), but the data is now **surfaced on
  Home**.
- `goToTab` test helper updates: Today → Home (step count); Cardio → a Home cardio
  row's "see all" → CardioView; Trends → trend "→"; Train → history "→".

---

## 4. Visual feel — hero imagery for workout types

**Wanted:** popular images (weights, cycling, boxing…) instead of generic icons /
walls of text.

**Approach (responsible + implementable now):** a reusable `WorkoutHero` banner —
a rich **color gradient keyed to the workout type** with a large glyph and the
title, used on the Start-Workout type cards, the Start-Workout hero on Home, and
the interval setup header. Each type also looks for a **named image asset**
(`hero-weights`, `hero-run`, `hero-cycle`, `hero-boxing`, `hero-hiit`,
`hero-walk`, `hero-other`); if present it's used as the banner, else the gradient
fallback renders.

```
WorkoutTypePicker card:
┌──────────────┐   gradient (orange→red for boxing, blue→teal for run, …)
│  🥊          │   + large symbol + "Boxing"
│   Boxing     │
└──────────────┘
```
> Note on real photos: Wikipedia/Wikimedia images carry varied licenses
> (CC-BY-SA, public domain, etc.) and require attribution. I'm shipping the
> gradient/symbol hero (no licensing risk) plus the named asset *slots*; drop
> approved image files into those slots and they appear automatically. I can wire
> specific licensed images if you provide/approve them.

---

## Reconciliation with round-2 (kept)
- **Pre-workout countdown** (default 30s, settable, Skip) — kept; now also gates
  the interval START.
- **Use Previous Workout** (copies a full past workout) + **Add Exercise at the
  bottom** — kept.
- Round-2's inline step *ring* on Home is **replaced** by this dashboard.

## Implementation order
1. Core: 4 new `IntervalPlan` factories + tests.
2. `IntervalSetupView`: select-then-START; `IntervalView`: persistent plan name.
3. `HomeView`: dashboard rebuild (simple steps, week count, inline trend/cardio/
   history); remove ring.
4. `WorkoutHero` + gradient palette; apply to type picker + Home hero + interval
   setup; asset slots.
5. Update UI tests (`goToTab`, FR2/FR3/FR5, new interval START test); full suite.
