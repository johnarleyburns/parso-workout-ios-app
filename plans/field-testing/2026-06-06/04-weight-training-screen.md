# §04 — Weight Training Screen

> Addresses field note **#4 (logging parts)**: enter my own exercises; drop
> "templates" in favor of **recording workouts and reusing an existing one
> fresh**; **dual lb/kg entry** (enter either, auto-fill the other); **partners**
> entered at workout time (mark a set as me — default — or a named partner, up to
> several, kept distinct in health data); and easy begin/end (the lifecycle lives
> in §02).

Decisions applied: #4 (dual units, kg canonical), #13 (partner sets never in
HealthKit), #14 (partners in export, tagged), #15 (exact conversion, plate-round
optional/off), #16 (retire templates → reuse workout). Depends on §02 (engine) and
§03 (database).

---

## Problem (from the field test)

1. **Custom exercises** — currently you can create a custom exercise inline
   (`findOrCreateExercise`), but only with a name; no equipment/muscles (§03 adds
   those facets, this section wires the create UI).
2. **Templates feel wrong** — "instead of templates just record workouts and we
   can reuse existing workouts fresh." Today there's a whole `SessionTemplate`
   system (`TemplatesView`, `TrainView` "Quick Start", `startSession(from:)`).
3. **Dual units** — "show both lbs and kgs… let me enter either and auto-fill the
   other." Today `SetEditorView` has a single weight field in the *one* global
   unit (`settings.unit`); no dual display, no auto-fill.
4. **Partners** — entirely absent. No `Person`, no per-set attribution.

## What the code does today

- `SessionView.swift` — per-exercise cards, last-time + PR context, set rows,
  Add Set / Repeat last, manual "save to Health" toolbar button.
- `SetEditorView.swift` — single `weightText` in `settings.unit`, reps stepper,
  warmup/RPE/note. Converts to kg via `WorkoutMath.canonical`.
- `WorkoutRepository` — `addSet/updateSet/deleteSet`, `findOrCreateExercise`,
  and the **template** API (`createTemplate/startSession(from:)/allTemplates/
  deleteTemplate`) + `TemplatesView`/`TrainView` Quick Start.
- `WorkoutMath` — `canonical(_:from:)` / `display(_:in:)` lb↔kg already exist.
- `SetEntry.weight` is **canonical kg** already → dual units is a UI concern, no
  storage change.

---

## Design

### A. `StrengthSessionView` (evolves `SessionView`)

Keep the strong parts (per-exercise cards, inline last-time/PR, Repeat last) and
add:
- A **session header** with elapsed (from `WorkoutClock`, §02), a prominent
  **End Workout** button (finalize → summary `HKWorkout`, §02), and the
  **partner selector** (below).
- "Add Exercise" → the §03 ranked search picker, with **Create** carrying
  equipment/muscle facets.
- Tie into the engine: logging a set pokes the `IdleWatchdog` (§02).

### B. Dual lb/kg entry control (decision #4 / #15)

Replace the single weight field in `SetEditorView` with a **dual control**:

```
Weight
┌───────────────┐   ┌───────────────┐
│  100.0   lb   │ ⇄ │  45.4    kg    │
└───────────────┘   └───────────────┘
   (active)            (auto-filled)
```

- The user types in **either** field; the other updates live via
  `WorkoutMath.canonical`/`display`. Storage stays **kg** (`SetEntry.weight`).
- The **global default unit** (decision #4, `settings.unit`) decides which field
  is focused first and which is emphasized — but both are always visible and
  editable.
- **Rounding (decision #15):** show the **exact** converted value (100 lb →
  45.4 kg). Add a Settings toggle "round to nearest plate" (default **off**); when
  on, the *display* snaps to a clean plate increment (configurable kg/lb plate
  set) while storage keeps the exact entered value.
- New pure helper in core: `UnitEntry` (given an edited value+unit, returns kg +
  the formatted partner value), unit-tested.

### C. Reuse workout, retire templates (decision #16)

- **Remove from UI:** `TemplatesView`, `TrainView`'s "Templates" button and
  "Quick Start" section. **Keep `SessionTemplate`/`TemplateExercise` in the
  schema** (and their repository methods) so existing data and CloudKit aren't
  broken — they're just unsurfaced (migration safety, §07).
- **Add "Reuse":** from History (a past `WorkoutSession`) and from Home's "reuse
  last" line (§01):
  - New repo method `reuseSession(_ past:) -> WorkoutSession` that creates a
    **fresh** session whose **exercises are pre-added** (in order) but with **no
    sets** (you log fresh), copying the title (e.g. "Push Day"). Optionally
    pre-fill target reps from last time as ghost placeholders (not logged sets).
  - This gives the template benefit ("start from my Push Day") without a separate
    template concept — the workout *is* the template (decision #16). Matches the
    tester's mental model and the original "replace a Gmail draft" goal.

### D. Partners (decisions #13/#14)

New lightweight entity + per-set attribution:

```
@Model Person {
  id: UUID; name: String = ""; isMe: Bool = false
  createdAt/updatedAt/originDevice
}
SetEntry.performedBy: Person?     // nil ⇒ owner ("me", default)
```

- **At workout time** (the tester's requirement), a **partner bar** on
  `StrengthSessionView` lets you add people you're training with (pick existing
  or type a name → creates a `Person`). "Me" is the default attribution.
- When logging a set, a quick segmented control chooses **who** the set is for —
  Me (default) or a partner — so alternating sets are captured distinctly. Up to
  several partners supported.
- **Distinct in health data (decision #13):** partner sets are **never** written
  to *your* HealthKit summary, and are **excluded** from your PRs, volume,
  trends, and last-time (those filter `performedBy == nil || isMe`). They live in
  the local store as the partner's record.
- **Export (decision #14):** partner sets are included in JSON/CSV **tagged by
  person**, so a partner can take their data; a partner can later be promoted to
  their own export filter.
- **PR/volume/last-time call-sites** that must learn the filter:
  `WorkoutRepository.sampleHistory/lastTimeSets/currentPR/wouldBePR/recentPRs/
  trendSeries/prTimeline/totalVolume` and `SessionView.isAllTimePR` → all add
  "owner-only" filtering. (This is the highest-touch part of the change; §07
  lists every call-site.)

### E. Mockup — strength session with partner + dual units

```
┌──────────────────────────────┐
│ Push Day            00:24:10  │  ← elapsed (WorkoutClock)
│ With: [Me ✓] [Sam] [＋]       │  ← partner bar
│                              │
│ Bench Press            ⟂ bar  │
│ Last: 100lb×5,5  PR 110lb     │
│  1  100 lb (45.4 kg) ×5  🏆   │
│  2  100 lb ×5   [Sam]         │  ← partner-attributed set, excluded from my PRs
│  [Add Set]   [Repeat last]    │
│                              │
│ [＋ Add Exercise]             │
│                              │
│        [ End Workout ]        │
└──────────────────────────────┘

Set editor:
  For: ( Me | Sam )           ← attribution
  Weight: [100.0 lb] ⇄ [45.4 kg]
  Reps: [ 5 ]   Warmup ▢   RPE ▢
```

---

## Data-model deltas (consolidated in §07)

- New `@Model Person { id, name, isMe, timestamps }`.
- `SetEntry.performedBy: Person?` (optional ⇒ CloudKit-safe; nil = owner).
- `WorkoutSession` gains `endedAt` (from §02).
- `SessionTemplate`/`TemplateExercise` **retained** (unsurfaced).
- Export schema (`ExportSet`) gains optional `performedBy` name (decision #14).
- No storage change for units (kg canonical already).

## Implementation steps

1. **Core:** `UnitEntry` helper (dual-field math) + tests; add owner-only filters
   to all PR/volume/last-time repo methods (param `ownerOnly: Bool = true`).
2. **`Person` model** + repo (`allPeople`, `findOrCreatePerson`, `me`).
3. **`SetEditorView`:** dual lb/kg control + "For:" attribution; plate-round
   setting.
4. **`StrengthSessionView`:** header w/ elapsed + End, partner bar, attribution on
   rows, set the §02 watchdog on log.
5. **Reuse:** `reuseSession(_:)` repo method; hook into History + Home.
6. **Retire templates from UI** (delete `TemplatesView` usage, `TrainView` Quick
   Start) — keep schema/methods.
7. **Create-exercise** UI carries §03 facets.

## Testing

- **Unit (swift test):** dual-entry round-trips (100 lb ↔ 45.4 kg, exact;
  plate-round when enabled); owner-only PR/volume excludes partner sets;
  `reuseSession` clones exercises with zero sets; export includes partner tag.
- **UI (iPhone + iPad):** log a set in lb, see kg auto-fill; add a partner,
  attribute a set, confirm it shows `[Sam]` and is **not** counted in your
  session volume/PR badge; reuse a past workout → exercises present, no sets;
  templates UI is gone.
- **Accessibility:** dual fields each labeled with unit; attribution control
  labeled; End button ≥44pt, high contrast.

## Open questions (resolved)

- Dual units, kg canonical, exact w/ optional plate-round-off (decisions #4/#15). ✔
- Partners never in HealthKit, excluded from owner stats, included in export
  tagged (decisions #13/#14). ✔
- Templates retired in UI, kept in schema; reuse-workout replaces them
  (decision #16). ✔
