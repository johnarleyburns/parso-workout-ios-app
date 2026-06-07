# §07 — Consolidated Data Model, Migration & Rollout

> Pulls every schema delta from §01–§06 into one place, proves they're CloudKit-
> and migration-safe (decision #25, additive only), and lays out the phased
> rollout (decision #5, one PR per section) and a full test matrix.

---

## A. Consolidated schema deltas

All deltas obey the CloudKit rules already enforced in `Models.swift`: every new
stored property is **optional or defaulted**, every new relationship is optional,
**no `@Attribute(.unique)`**, inverse on one side, and every entity keeps
`id`/`updatedAt`/`originDevice`. This makes the migration **lightweight/automatic**
(SwiftData additive migration) and keeps CloudKit sync working.

### `Exercise` (from §03)
Add (all optional/defaulted):
- `equipment: String?` — `Equipment` raw (barbell/dumbbell/cable/machine/
  bodyweight/plyometric/kettlebell/band/smith)
- `isLateral: Bool = false` — isolateral/unilateral
- `mechanics: String?` — compound/isolation
- `force: String?` — push/pull/static (biomechanical; distinct from `category`)
- `primaryMuscles: [String] = []`, `secondaryMuscles: [String] = []` — muscle ids
- `searchKeywords: [String] = []` — derived at seed/create
- (keep existing `muscleGroups` for back-compat)
- Add `equipmentValue`/`mechanicsValue`/`forceValue` computed accessors (mirror
  `categoryValue`).

### `WorkoutSession` (from §02)
- `endedAt: Date?` — real end time for strength (parity with cardio's `end`);
  used by duration + idle finalizer.

### `SetEntry` (from §04)
- `performedBy: Person?` — optional to-one; **nil ⇒ owner ("me")**. Owner stats
  filter on this.

### New `@Model Person` (from §04)
```
id: UUID = UUID()
name: String = ""
isMe: Bool = false
createdAt/updatedAt/originDevice (standard)
@Relationship(.nullify, inverse: \SetEntry.performedBy) sets: [SetEntry]? = []
```

### Retained-but-unsurfaced (from §04)
- `SessionTemplate` / `TemplateExercise` **stay** in the schema and repository
  (migration safety); just removed from the UI. Do **not** delete the models.

### Bundled resource (from §03)
- `CadenceCore/.../Resources/exercises.json` (~300 entries) + `resources:` in
  `Package.swift`; loaded via `Bundle.module`.

### Export schema (from §04, decision #14)
- `ExportSet.performedBy: String?` (person name) — additive, older exports still
  decode.

### Pure (non-`@Model`) core additions
- §02: `WorkoutClock`, `IdleWatchdog`, `WorkoutType`
- §03: `Equipment`, `Mechanics`, `Force`, `BodyRegion`, `Muscle`,
  `MuscleCatalog`, `ExerciseSearch`
- §04: `UnitEntry`
- §06: `IntervalPhase`, `IntervalPlan`, `IntervalRunner` (app), `FullScreenColorState`

**No entity is removed; no property changes type; no uniqueness added** → additive
SwiftData migration, CloudKit-safe (decision #25).

## B. Migration & seeding safety

- **Versioned re-seed (critical).** Today `seedStarterLibraryIfNeeded` only runs
  when `Exercise` count == 0, so existing testers (who already have the 25) would
  **never** get the ~300. Replace with a `seedVersion` marker (UserDefaults or a
  tiny meta record): on launch, insert any built-in (by name) not already present,
  backfilling facets on the original 25, and **never** touching `isCustom`
  exercises. Idempotent.
- **Backfill facets** on the legacy 25 by name-match against the new seed so their
  search keywords/equipment populate.
- **Owner-only filters default safely:** existing sets have `performedBy == nil`
  ⇒ treated as owner ⇒ all current PRs/volume/trends are unchanged.
- **No destructive migration**; if a future change ever needs one, gate it behind
  a `SchemaMigrationPlan` — out of scope here.

## C. Highest-risk touch points (call-sites to update carefully)

1. **Owner-only stat filtering (§04).** Every PR/volume/last-time path must
   exclude partner sets. Update: `WorkoutRepository.sampleHistory`,
   `lastTimeSets`, `currentPR`, `wouldBePR`, `recentPRs`, `trendSeries`,
   `prTimeline`; `WorkoutSession.totalVolume`; `SessionView.isAllTimePR`. Add
   `ownerOnly: Bool = true` and filter `performedBy?.isMe ?? true`. **Regression
   risk:** miss one → partner sets pollute PRs. Cover each with a test.
2. **Navigation rewrite (§01).** Removing the tab bar breaks every UITest that
   navigates via `tab.*`. Update `UITestHelpers.swift` + each `FR*UITests` to go
   through Home identifiers, in the **same PR** as the shell change.
3. **Wall-clock timing (§02).** `RecordCardioView`'s tick-counting becomes display-
   only; elapsed must come from `WorkoutClock`. Audit anything that reads
   `recorder.elapsed` as truth.
4. **Search swap (§03).** `WorkoutRepository.searchExercises` → `ExerciseSearch`;
   keep the signature so `ExercisePickerView` is a minimal change.
5. **Background location (§05) & audio session (§06).** New capabilities/Info.plist
   entries + purpose strings; verify on device (simulator can't fully validate
   background location/audio).

## D. Rollout — one PR per section (decision #5)

Each PR: branch off `main`, reference the field-test section + FR ids, land green
(`swift test` + `xcodebuild` UI suite on iPhone **and** iPad per CLAUDE.md), then
next. Suggested order honoring dependencies:

| PR | Branch | Section(s) | Notes |
|----|--------|-----------|-------|
| 1 | `feat/ft-shell` | §01 nav + §02 engine core | Ship together: Home needs the active-session state; engine has no UI without a host. Includes UITest nav migration. |
| 2 | `feat/ft-exercise-db` | §03 | Model fields + seed JSON + search + versioned re-seed. Mostly core + tests; low UI risk. |
| 3 | `feat/ft-strength` | §04 | Dual units, partners, reuse-workout, retire templates UI. Highest stat-filter risk — lots of tests. Depends on PR 1+2. |
| 4 | `feat/ft-cardio-gps` | §05 | OutdoorCardioView + map + background location. Depends on PR 1. |
| 5 | `feat/ft-intervals` | §06 | Interval engine + full-screen color + cues. Depends on PR 1. |
| 6 | `feat/ft-polish` | cross-cut | Settings (timeout, units, GPS accuracy, color-blind palette, plate-round), Stats "Activity" block (migrated steps), accessibility pass. |

PRs 2/4/5 are largely independent after PR 1; 3 should follow 2.

## E. Settings added across sections (one consolidated list)

- Idle auto-terminate timeout (default 10 min) — §02
- Default unit (kg/lb) — §04 (existing `settings.unit`, now drives dual-field focus)
- Round to nearest plate (off) + plate set — §04
- PR rule (est. 1RM default) + 1RM formula (Epley) — cross-cutting #2/#3 (may
  already exist as `settings.prRule`/`settings.formula`; confirm UI)
- GPS accuracy tier (balanced) + auto-pause (off) — §05
- Interval color palette (default / color-blind) + spoken cues (off) — §06

## F. Test matrix (what "done" means — CLAUDE.md verify-before-done)

**Core (`swift test`, headless):**
- §02 `WorkoutClock` elapsed across pause + simulated background; `IdleWatchdog`
  expiry/disarm; cold-resume.
- §03 search ("cable"/"lats"/"pecs"/"push" facet hits, ranking, custom ordering);
  versioned re-seed idempotency + no-custom-clobber; JSON loads.
- §04 `UnitEntry` round-trips (exact + plate-round); owner-only excludes partner
  sets across all stat methods; `reuseSession` clones exercises w/ no sets; export
  carries partner tag.
- §06 plan expansion (Tabata/Norwegian/boxing totals); `colorState` thresholds;
  runner phase index across background gap.

**UI (`xcodebuild`, iPhone + iPad — both, per CLAUDE.md):**
- §01 no tab bar; Home → Stats/History/Settings; Resume card behavior; FR1–FR6
  suites re-pointed through Home stay green.
- §02 type picker routes; backgrounding advances wall-clock; idle prompt (short
  injected timeout) saves.
- §03 search returns equipment/muscle results; create custom w/ facets.
- §04 lb→kg auto-fill; partner attribution excluded from session volume/PR; reuse
  workout; templates UI gone.
- §05 Run shows map + distance + elapsed; pause/resume; End → History w/ route;
  background advances distance (injected fixes).
- §06 interval color state transitions; pause/end; color-blind palette swap.

**Device-only (manual, can't simulate):** HealthKit writeback (strength/cardio/
interval summaries close rings), real GPS route + background continuation during a
real phone call, audio cues with screen locked + music playing, BLE strap during
an interval/outdoor session.

**Accessibility (every PR, NFR-2):** VoiceOver labels on all new controls;
Dynamic Type to AX5 without clipping (especially the giant interval countdown and
dual-unit fields); Reduce Motion (map camera, interval flash); contrast on
full-screen color states; meaning never by color alone.

## G. Definition of done (whole effort)

- All six PRs merged, each green on iPhone + iPad.
- Tab bar gone; Home is action-first; one Start → type → purpose-built screen per
  type.
- ~300 faceted exercises searchable by name/equipment/muscle(sci+colloquial)/
  push-pull; custom exercises with facets.
- Strength: dual lb/kg entry, partners (distinct, excluded from owner stats,
  exported tagged), reuse-workout (no templates UI), begin/end + 10-min idle
  auto-terminate + survives backgrounding.
- Outdoor Run/Walk/Cycle with live map + background GPS.
- HIIT (Tabata/Norwegian 4×4/custom) + Boxing (3/1, 2/0.5, custom) with the
  full-screen green/yellow/flash/red indicator, haptics + audio + optional speech.
- HealthKit summaries for all workout kinds; CloudKit sync intact; no new
  proprietary deps (NFR-6).
