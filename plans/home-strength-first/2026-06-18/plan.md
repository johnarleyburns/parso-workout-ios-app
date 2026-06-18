# Home strength-first action spine + README fix

Branch: `feat/home-strength-first` off `main`. One PR.

## Problem

The Home hero button ("Start") leads to different flows depending on the
Coach/Custom toggle — Coach opens the prescribed workout editor (strength), but
Custom opens the **all-types WorkoutTypePicker** (strength, run, walk, cycle,
swim, HIIT, boxing, other). This equal-weight presentation contradicts the
strength-pivot: strength is now the app's core identity, and cardio is a
supported-but-secondary capability.

Separately, README.md drifts from the shipped app: it overemphasizes watch-first
and broad cardio/Smart Start framing, and doesn't reflect the iPhone-first v1
with the scientific strength coach as the centerpiece.

## What the code does today

`HomeView.swift` body VStack (line ~82):

```
resumeCard → CoachCardView → startModePicker → startButton → logButton
  → thisWeekSection → recentWorkoutsSection
```

`startModePicker` (line ~386): segmented Coach / My Own toggle. Default `.coach`.

`startButton` (line ~415):
- Coach mode → `coachEditorPresented = true` (WorkoutPlanEditor — strength editor)
- Custom mode → `typePickerPresented = true` (all-types WorkoutTypePicker)

Three relevant sheets already exist:
1. `typePickerPresented` (line ~124) — all-types picker (strength + all cardio)
2. `cardioPickerPresented` (line ~155) — cardio-only picker (run/walk/cycle/swim/hiit/boxing/other)
3. `weightsStartPresented` (line ~163) — WeightsStartView (Quick Start / Warm-Up / Reuse / presets)

The `start(_:)` function (line ~578) routes types chosen from any picker — still
needed by the cardio picker.

a11y: `home.startWorkout` on the hero. No standalone cardio entry.

## Design

### New action spine layout

```
┌──────────────────────────────────────────┐
│  Resume Workout (if active)              │ ← unchanged
├──────────────────────────────────────────┤
│  ┌────────────────────────────────────┐  │
│  │ 🧬 Coach Card (top prescription)  │  │ ← unchanged
│  │ "Do this workout" · "See all"     │  │
│  └────────────────────────────────────┘  │
│                                          │
│  ┌──────────────┬───────────────┐        │
│  │ Coach Workout│   My Own      │        │ ← unchanged toggle
│  └──────────────┴───────────────┘        │
│                                          │
│  ╔══════════════════════════════════════╗ │
│  ║ ▶ Start       (green hero)    ▸     ║ │ ← CHANGED: always strength
│  ╚══════════════════════════════════════╝ │   Coach → editor, Custom → WeightsStart
│                                          │
│  ┌──────────────────────────────────────┐ │
│  │ 🏃 Start Cardio   (tint-on-tint)  ▸ │ │ ← NEW secondary button
│  └──────────────────────────────────────┘ │   → cardioPickerPresented
│                                          │
│  ┌──────────────────────────────────────┐ │
│  │ 📝 Log Workout    (tint-on-tint)  ▸ │ │ ← unchanged
│  └──────────────────────────────────────┘ │
│                                          │
│  This week                               │ ← unchanged
│  [ workouts ] [ cardio min ]             │
│  [ volume   ] [ body parts ]             │
│                                          │
│  Recent workouts                         │ ← unchanged
└──────────────────────────────────────────┘
```

### Changes

1. **Repoint the hero** (`startButton`, line ~415):
   - Coach mode: keep `coachEditorPresented = true` (already strength).
   - Custom mode: change `typePickerPresented = true` → `weightsStartPresented = true`.
   - a11y id stays `home.startWorkout`, label stays "Start a workout".

2. **Add `cardioButton`** — new computed property, inserted into the body VStack
   between `startButton` and `logButton`:
   - Mirrors `logButton` styling (tint-on-tint, same padding/rounding/chevron).
   - Icon: `figure.run` (or `figure.outdoor.cycle` — TBD, `figure.run` is most
     universal). Text: "Start Cardio".
   - Action: `cardioPickerPresented = true`.
   - a11y: `.accessibilityIdentifier("home.startCardio")`,
     `.accessibilityLabel("Start a cardio workout")`.
   - Dynamic Type: uses `.headline` like `logButton` (auto-scales).

3. **Remove orphaned all-types path** (only after confirming nothing else refs it):
   - Delete `@State private var typePickerPresented = false` (line 18).
   - Delete the `.sheet(isPresented: $typePickerPresented)` block (lines 124–129).
   - Audit: `typePickerPresented` is also set to `false` in `start(_:)` (line 587
     etc.) and `startOtherCardio` (line 600) and `launchFromPicker` (line 621).
     These are only called from the all-types picker's callbacks — once the sheet is
     gone, they can't fire. BUT `start(_:)` is also used by the **cardio picker**
     (line 156). The cardio picker doesn't use `typePickerPresented` — it manages
     `cardioPickerPresented` separately. So removing `typePickerPresented` is safe.
     Keep `start(_:)` — the cardio picker's `onSelect` still calls it.
   - Clean up the `typePickerPresented = false` lines in `start(_:)`,
     `startOtherCardio`, and `launchFromPicker` since the var is gone.

### Out of scope (leave as-is)

- "This week" stat tiles and their tap-to-start behavior.
- Coach card.
- Log Workout.
- Recent workouts list.
- `startModePicker` — stays; both modes are now strength (Coach = prescribed,
  My Own = Quick Start / Warm-Up / Reuse / presets).

### Open question: stat tile taps

The steps tile (`stepsQuickStart`) and cardio-minutes tile (`cardioPickerPresented`)
currently quick-start cardio when tapped. Should we:

**(A) Leave them as-is** (lean) — they're contextual: you're looking at a cardio
stat, so tapping it starts cardio. The new `home.startCardio` is the primary
entry; the tiles are shortcuts tied to the stat they summarize.

**(B) Route through `home.startCardio`** — for consistency, have the tiles scroll
to / highlight the cardio button instead of presenting their own sheets.

My recommendation: **(A)** — the tiles are already shipped, well-tested
(batch 8), and contextually correct. The new cardio button doesn't obsolete them.

## Steps

### Step 1: Add cardio button + repoint hero (additive)

1. Add `cardioButton` computed property to `HomeView`, styled like `logButton`.
2. Insert `cardioButton` into the body VStack after `startButton`, before `logButton`.
3. Change `startButton` Custom-mode action from `typePickerPresented = true` to
   `weightsStartPresented = true`.
4. Build: `cd CadenceCore && swift test` + `xcodebuild build`.

### Step 2: Remove orphaned all-types path (subtractive)

1. Remove `@State private var typePickerPresented`.
2. Remove the `.sheet(isPresented: $typePickerPresented)` block.
3. Remove `typePickerPresented = false` from `start(_:)`, `startOtherCardio`,
   `launchFromPicker`.
4. Build again to confirm no references remain.

### Step 3: Update UI tests

8 test call sites currently tap `home.startWorkout` then pick a cardio type from
WorkoutTypePicker. They need rerouting to `home.startCardio`:

| File | Line(s) | Current flow | New flow |
|---|---|---|---|
| FR2CardioUITests | 20 | hero → `startType.run` | `home.startCardio` → `startType.run` |
| FR2CardioUITests | 48 | hero → `startType.other` | `home.startCardio` → `startType.other` |
| FR2IntervalsUITests | 9 | hero → `startType.boxing` | `home.startCardio` → `startType.boxing` |
| FR2IntervalsUITests | 34 | hero → `startType.hiit` | `home.startCardio` → `startType.hiit` |
| FR9Feedback2UITests | 37 | hero → `startType.swim` | `home.startCardio` → `startType.swim` |
| FR11Feedback4UITests | 109 | hero → `startType.boxing` | `home.startCardio` → `startType.boxing` |
| FR12Feedback5UITests | 15 | hero → `startType.hiit` | `home.startCardio` → `startType.hiit` |
| FR7LifecycleUITests | 139 | hero → `startType.other` | `home.startCardio` → `startType.other` |
| FR13Feedback6UITests | 62 | hero → `startType.other` | `home.startCardio` → `startType.other` |

5 test call sites tap `home.startWorkout` then pick `startType.weights` from the
all-types picker. After the change, the hero in Custom mode goes directly to
WeightsStartView — they need to:
- Toggle to Custom mode (`startMode.custom`) if not already there.
- Tap the hero (which now opens WeightsStartView directly — no type picker).
- Remove the `startType.weights` tap.

| File | Line(s) | Notes |
|---|---|---|
| FR9Feedback2UITests | 9 | Weights Quick Start + Library |
| FR10Feedback3UITests | 25 | Library presets |
| FR11Feedback4UITests | 50, 65 | Warm-up flow |
| FR7LifecycleUITests | 27 | Countdown + preset |

Non-taps (existence checks — no change needed):
FR7LifecycleUITests:103, FR7LifecycleUITests:130, FR9PolishUITests:13.

P5DoThisUITests:10, P5DoThisUITests:33 — already use Coach mode, no type picker involved.

**New test coverage to add:**
- Assert that tapping the hero in Custom mode opens WeightsStartView (check for
  `weights.quickStart` or similar a11y id).
- Assert that tapping `home.startCardio` opens the cardio-only picker (check for
  `startType.run` or similar).

### Step 4: Fix README.md

1. Reframe lead: iPhone-first v1, watch deferred to long-term.
2. Lead features with strength coach; keep cardio as secondary.
3. Name: use "Cladiron" as the user-visible product name throughout; "Cadence" is
   only the internal project name (per user confirmation).
4. Keep edits tight — fix drift, don't rewrite the whole file.

### Step 5: Update current_state.md

Record the phase start and what changed.

### Step 6: Build + verify + commit + PR

- `cd CadenceCore && swift test`
- `xcodebuild -project Cadence/Cadence.xcodeproj -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`
- UI test suite (if sim is healthy).
- Commit with Co-Authored-By trailer. Open PR.

## Tests

- **CadenceCore:** should stay green — this is UI-only, no core changes.
- **UI tests:** 8 cardio-via-hero tests rerouted to `home.startCardio`;
  5 weights-via-hero tests updated to skip type picker; 2 new assertions added.
- **Manual check:** hero opens strength flow in both Coach and Custom modes;
  cardio button opens the cardio-only picker.

## Open questions

1. **Stat tile taps** — see above. Recommendation: leave as-is (option A).
2. ~~**Product name** — README says "Cadence", `navigationTitle` says "Cladiron".
   Which is canonical?~~ **Resolved:** Cladiron is the user-visible name; Cadence
   is internal only.
