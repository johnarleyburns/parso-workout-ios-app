# Custom Exercise Completeness: Coach-Aware Definitions

**Date:** 2026-07-10
**Status:** planning — all open questions resolved

## Problem

Custom exercises created by the user (e.g., "rotary torso", "back extensio", "triceps pres") have `primaryMuscles: []` even though they carry an `ExerciseCategory` (e.g., "core", "pull", "push"). The coach's volume accounting (`TrainingFacts.make()`) only uses `primaryMuscles`/`secondaryMuscles` to derive `BodyPart` — it never consults `category`. This makes every set logged under these exercises **invisible** to the coach, causing:

1. **Underestimated weekly volume** — the coach thinks body parts are untrained when they're not
2. **Phantom deficits** — the plan optimizer tries to fill non-existent volume gaps
3. **Naggy "Some planned volume still needs attention" insights** — the planner can't close deficits in remaining slots
4. **Wrong recommendations** — volume personalization, deload timing, and exercise selection all drift

The user's export has 5 custom exercises with this problem (`rotary torso`, `back extensio`, `triceps pres`, `Dumbbell Front Raise`, `L-Sit`). The immediate trigger was the coach complaining about 1 missing abs set when the user actually did 6 sets of "rotary torso" (category: core).

## Root cause chain

```
findOrCreateExercise(notInLibrary) → primaryMuscles: []
  → TrainingFacts.make() uses only primaryMuscles → BodyPart.parts(forMuscleIDs: []) = {}
    → coach sees 0 abs sets → deficit → planner tries to fill → session caps hit → unresolved → nag
```

There are **four compounding gaps**:

| Gap | Where | Effect |
|-----|-------|--------|
| A. No category→muscle fallback | `WorkoutRepository.findOrCreateExercise:183` | New custom exercises get empty muscles even when category is known |
| B. No category→bodypart fallback | `TrainingFacts.make():188`, `CoachPlanOptimizer` | Existing exercises with empty muscles contribute 0 to volume |
| C. No user guidance at creation time | `ExercisePickerView.create()` | User creates a "rotary torso" with no way to specify muscles |
| D. No detection/remediation for existing gaps | Coach engine | Invisible problem festers silently |

## Design (resolved from user feedback)

1. **Category→muscle derivation:** When creating a custom exercise with a known category, automatically pre-fill primary muscles
2. **Creation-time pills:** Before finalizing, show a confirmation sheet with adjustable muscle/body-part pills
3. **Match suggestion:** After typing, if a fuzzy match exists in the library, show an inline suggestion card
4. **Settings custom exercise management:** A new Settings section listing custom exercises with edit + "delete & reassign" merge
5. **Coach insight:** Detect incomplete custom exercises and warn the user with a navigable insight (citing Brennan 2025)
6. **Export round-trip:** Include custom exercise facet data in JSON export so imports preserve muscle definitions
7. **Post-import auto-trigger:** After importing a v4 export (no exercises array), run a completeness check

---

# Phase 1 — Category-to-Muscle & Category-to-BodyPart Derivation (CadenceCore)

**Dependency: none** | **Testable: `swift test`**

## 1a. BodyPart fallback from ExerciseCategory

Add to `BodyPart.swift`:

```swift
public static func parts(forCategory cat: ExerciseCategory) -> Set<BodyPart> {
    switch cat {
    case .push: return [.chest, .shoulders, .triceps]
    case .pull: return [.back, .biceps]
    case .legs: return [.legs, .calves]
    case .core: return [.abs]
    case .cardio, .plyometrics, .other: return []
    }
}
```

Wire as fallback in `TrainingFacts.make()` (line 188). When `primary` comes back empty AND the exercise has a category, resolve via the category:

```swift
var primary = BodyPart.parts(forMuscleIDs: ws.exercise.primaryMuscles)
if primary.isEmpty, let cat = ws.exercise.categoryValue {
    primary = BodyPart.parts(forCategory: cat)
}
```

Same fallback in `CoachPlanOptimizer.partsCovered(by:)` and `PlanAwareInsightEngine.plannedSetsByPart(from:)` so planned exercises also benefit.

## 1b. Category→muscle derivation for new exercise creation

Add to `BodyPart.swift`:

```swift
public static func defaultMuscles(forCategory cat: ExerciseCategory) -> [String] {
    switch cat {
    case .push: return ["chest", "delts", "triceps"]
    case .pull: return ["lats", "biceps"]
    case .legs: return ["quads", "hamstrings", "glutes"]
    case .core: return ["abs"]
    case .cardio, .plyometrics, .other: return []
    }
}
```

Use in `WorkoutRepository.findOrCreateExercise` (line 189-190): when `template == nil` AND `primaryMuscles` is empty AND `category` is non-nil, pre-fill with `defaultMuscles(forCategory:)`:

```swift
let resolvedPrimary: [String]
if !primaryMuscles.isEmpty {
    resolvedPrimary = primaryMuscles
} else if let tp = template?.primaryMuscles, !tp.isEmpty {
    resolvedPrimary = tp
} else if let cat = resolvedCategory {
    resolvedPrimary = BodyPart.defaultMuscles(forCategory: cat)
} else {
    resolvedPrimary = []
}
```

## 1c. Category guessing heuristic for exercise name

Add a utility that derives `ExerciseCategory` from an exercise name based on common naming conventions in fitness (derived from existing exercise name patterns in `ExerciseLibrary` + `free-exercise-db`):

```swift
public static func guessCategory(from name: String) -> ExerciseCategory? {
    let lower = name.lowercased()
    // Push keywords
    if lower.contains("press") || lower.contains("push") || lower.contains("extension")
        || lower.contains("fly") || lower.contains("raise") || lower.contains("overhead") { return .push }
    // Pull keywords
    if lower.contains("curl") || lower.contains("row") || lower.contains("pulldown")
        || lower.contains("pull") || lower.contains("snatch") || lower.contains("clean") { return .pull }
    // Leg keywords
    if lower.contains("squat") || lower.contains("deadlift") || lower.contains("lunge")
        || lower.contains("leg") || lower.contains("calf") || lower.contains("step")
        || lower.contains("hip thrust") || lower.contains("glute") { return .legs }
    // Core keywords
    if lower.contains("crunch") || lower.contains("abs") || lower.contains("core")
        || lower.contains("plank") || lower.contains("sit-up") || lower.contains("torso")
        || lower.contains("russian twist") || lower.contains("leg raise") { return .core }
    return nil
}
```

This is used by the exercise picker creation sheet (Phase 2) to pre-populate the category dropdown.

**Files to change:**
- `CadenceCore/Sources/CadenceCore/BodyPart.swift` — add `parts(forCategory:)`, `defaultMuscles(forCategory:)`, `guessCategory(from:)`
- `CadenceCore/Sources/CadenceCore/TrainingFacts.swift` — add category fallback at line 188
- `CadenceCore/Sources/CadenceCore/CoachPlanOptimizer.swift` — add category fallback in `partsCovered(by:)` (line 792)
- `CadenceCore/Sources/CadenceCore/PlanAwareInsightEngine.swift` — add category fallback in `muscleIDs(for:)` (line 40)
- `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift` — pre-fill muscles from category at line 189

**Tests:**
- `BodyPartTests` — `testPartsForCategory` (all 7 categories)
- `BodyPartTests` — `testDefaultMusclesForCategory` (each category returns non-empty for push/pull/legs/core)
- `BodyPartTests` — `testGuessCategory` (press→push, curl→pull, squat→legs, crunch→core, random→nil)
- `TrainingFactsTests` — exercise with category "core" but empty muscles contributes to abs
- `CoachPlanOptimizerTests` — custom exercise "rotary torso" with category core counts as abs volume

---

# Phase 2 — Exercise Picker: Match Suggestion + Creation Pills (UI)

**Dependency: Phase 1**

## 2a. Inline match suggestion card

In `ExercisePickerView.swift`, after the user types a query but before showing "Create {name}", check for a **fuzzy library match** (a `non-custom` exercise whose normalized name is a close match to the query but not an exact match). Show an inline card above the "Create" button:

```
┌─────────────────────────────────────────┐
│  🔍 Found a good match                  │
│  "Torso Rotation"  — core, abs          │
│  [Use this exercise]                    │
└─────────────────────────────────────────┘
```

Match criteria:
- An existing **built-in** (non-custom, `isCustom == false`) exercise where:
  - `normalize(name).contains(normalize(query))` OR `normalize(query).contains(normalize(name))`
  - AND it's NOT an exact match (`normalize(name) != normalize(query)`)
- If multiple matches, pick the highest-ranking built-in from `ExerciseSearchIndex.rank(query)`
- Only show when the user has typed ≥3 characters

Tapping "Use this exercise" calls `onPick(match)` and dismisses — same as picking any exercise.

## 2b. Pre-creation confirmation sheet

When the user taps "Create {name}" (whether the match card was shown or not), instead of immediately creating and picking, present a `.sheet` with:

```
┌─────────────────────────────────────────┐
│  New Custom Exercise                    │
│  "rotary torso"                         │
│                                         │
│  Category: [Core  ▼]  (guessed)         │
│                                         │
│  Body Parts:                            │
│  [Abs ×]    ← pre-selected, tappable    │
│                                         │
│  Primary Muscles:                       │
│  [abs ×] [obliques]                     │
│                                         │
│  [Create & Add Exercise]                │
│  [Cancel]                               │
└─────────────────────────────────────────┘
```

The sheet pre-populates:
- Category from `BodyPart.guessCategory(from: name)` (Phase 1c) or defaults to `.other`
- Body parts from `BodyPart.parts(forCategory:)` when a category is set
- Primary muscles from `BodyPart.defaultMuscles(forCategory:)` when a category is set
- If `guessCategory` returns nil, body parts and muscles start empty and the user must select them

Body part chips and muscle chips are selectable/unselectable — same `FlowLayout` chip pattern from `CustomExerciseEditView`. The category is a `Picker`/`Menu` dropdown.

On "Create & Add Exercise":
1. Call `WorkoutRepository.findOrCreateExercise(named:category:primaryMuscles:secondaryMuscles:...)` with the selected values
2. Call `onPick(ex)` and dismiss

**Files to change:**
- `Cadence/Cadence/Features/Train/ExercisePickerView.swift` — match suggestion card + create confirmation sheet

---

# Phase 3 — Settings: Custom Exercise Management (UI + Logic)

**Dependency: Phase 1** | **New screen**

## 3a. Settings entry point

Add a new `NavigationLink` in `SettingsView.swift` under a new "Exercises" section:

```swift
Section("Exercises") {
    NavigationLink {
        CustomExerciseListView()
    } label: {
        Label("Custom Exercises", systemImage: "figure.strengthtraining.traditional")
    }
}
```

Show a badge count if any custom exercises lack muscle definitions (`primaryMuscles.isEmpty`).

## 3b. CustomExerciseListView

A new `List` view showing all custom exercises (`isCustom == true`). Uses `@Query` to fetch them. Each row shows:
- Exercise name
- Category badge (colored chip)
- Body part chips (from `BodyPart.parts(forMuscleIDs:)` + category fallback, or "No muscles defined" in orange if empty)
- If incomplete: an orange "Incomplete" badge

Tapping a row opens `CustomExerciseEditView` (already exists) in a sheet.

## 3c. Delete & Reassign (merge) functionality

On each row, a context menu option "Delete & reassign to library exercise". Tapping it opens a mini picker/search of non-custom exercises (filtered to those whose category matches or whose name is similar). The picker suggests similar built-in exercises (using the same fuzzy match from Phase 2a but filtered to the same ExerciseCategory). After the user selects a target exercise:

1. Find all `SetEntry` records across **all sessions** whose `exercise.id` matches the custom exercise
2. Reassign each set's `exercise` to the selected built-in exercise
3. Find all `plannedExerciseNames` across all sessions that contain the custom exercise name — replace with the built-in name
4. Delete the custom exercise from the store
5. Save context
6. Show a confirmation toast: "{N} sets reassigned to '{target.name}'. '{custom.name}' deleted."

New function in `WorkoutRepository`:

```swift
@discardableResult
public static func reassignAndDeleteExercise(from custom: Exercise,
                                              into builtIn: Exercise,
                                              in context: ModelContext) throws -> Int {
    let allSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
    var moved = 0
    for session in allSessions {
        let sets = (session.sets ?? []).filter { $0.exercise?.id == custom.id }
        for set in sets {
            set.exercise = builtIn
            set.updatedAt = Date()
            moved += 1
        }
        if let idx = session.plannedExerciseNames.firstIndex(of: custom.name) {
            session.plannedExerciseNames[idx] = builtIn.name
        }
        session.updatedAt = Date()
    }
    context.delete(custom)
    try context.save()
    return moved
}
```

**Files to change:**
- `Cadence/Cadence/Features/Settings/SettingsView.swift` — add "Exercises" section with badge count
- `Cadence/Cadence/Features/Settings/CustomExerciseListView.swift` — new file (list, edit sheet, delete & reassign)
- `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift` — add `reassignAndDeleteExercise(from:into:)`
- `CadenceCore/Tests/CadenceCoreTests/` — reassign+delete tests

---

# Phase 4 — Coach Insight: Incomplete Custom Exercises (Core + UI)

**Dependency: Phase 1, 3**

## 4a. Insight rule

Add a new insight kind and rule. The insight triggers when:
- Any custom exercise in the store has `primaryMuscles.isEmpty` AND `muscleGroups.isEmpty`
- That exercise has been used in at least 1 logged working set (not just created and never used)

New `InsightKind` case: `.exerciseDefinition` (symbol: `exclamationmark.triangle.fill` in `CoachCardView.swift`).

Add `var incompleteCustomExerciseNames: [String]` to `TrainingFacts`, populated in `make()` by scanning all week-session exercises, finding distinct ones where `isCustom && primaryMuscles.isEmpty && muscleGroups.isEmpty`, collecting their names.

Add `IncompleteCustomExerciseRule` to `KnowledgeBase.p3Rules`:

Insight content:
- `title: "Custom exercises need muscle definitions"`
- `message: "{n} exercise(s) like '{example}, …' are missing muscle data — the coach can't track volume for them."`
- `detail: "Accurate exercise classification is important for training program monitoring (Brennan et al., 2025). Tap to open Custom Exercises in Settings where you can edit or merge them."`
- `kind: .exerciseDefinition`
- `severity: .attention`

## 4b. Citation

Add a new `Citation` to `CitationRegistry`:

```swift
static let exerciseClassification = Citation(
    id: "brennanExerciseClassification2025",
    title: "Exercise Classification in Resistance Training: A Systematic Review of Technological Approaches",
    authors: "Brennan TR, Weakley J, Johnston RD, Creaby MW",
    journal: "Sports Medicine",
    year: 2025,
    volume: 55,
    issue: 10,
    pages: "2529–2565",
    doi: "10.1007/s40279-025-02281-8",
    pmid: "40745224",
    url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC12513948/",
    snippet: "Accurate classification of resistance training exercises is essential for quantifying training loads, monitoring adherence, and informing exercise programming decisions.",
    tags: ["exercise-classification", "resistance-training", "technology"])
```

Add it to the `all` array and create a `exerciseDefinitionPool` that references this citation.

## 4c. Insight navigation

In `CoachDecisionCardView.swift`, when `insight.kind == .exerciseDefinition`, show a "Fix in Settings" button alongside the existing "More insights" button. This button navigates to Settings → Custom Exercises.

Add a new `HomeRoute` case: `case customExercises` that pushes `CustomExerciseListView` (wrapped in navigation).

## 4d. Post-import auto-trigger

After `WorkoutRepository.merge()` completes (import), if the imported data was version < 5 (no `exercises` array), add a `postImportMissingExerciseCount: Int?` to the import result or return value. The UI can then show a one-time alert: "{n} custom exercises were imported without muscle data. Define them in Settings → Custom Exercises for accurate coaching."

Alternative simpler approach: since Phase 4a's insight runs on every coach snapshot rebuild (which happens whenever history changes), a post-import session-count change will naturally trigger the snapshot rebuild and the insight will appear automatically. No special post-import hook needed — just ensure `CoachSnapshotBuilder` rebuilds after import.

**Files to change:**
- `CadenceCore/Sources/CadenceCore/Insight.swift` — add `.exerciseDefinition` kind
- `CadenceCore/Sources/CadenceCore/TrainingFacts.swift` — add `incompleteCustomExerciseNames`
- `CadenceCore/Sources/CadenceCore/InsightRule.swift` — add `IncompleteCustomExerciseRule`
- `CadenceCore/Sources/CadenceCore/Citation.swift` — add `exerciseClassification` citation + pool
- `CadenceCore/Sources/CadenceCore/CoachCardView.swift` — add symbol for `.exerciseDefinition`
- `Cadence/Cadence/Features/Home/HomeView.swift` — add `HomeRoute.customExercises`
- `Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift` — insight tap action for `.exerciseDefinition`

---

# Phase 5 — Custom Exercises in JSON Export/Import Round-Trip (Core)

**Dependency: Phase 1** | **Testable: `swift test`**

## 5a. Export custom exercise definitions

Add an `exercises` array to `CadenceExport` (version bump to 5):

```swift
public struct CadenceExport: Codable, Equatable, Sendable {
    public var version: Int  // 5
    public var exportedAt: Date
    public var sessions: [ExportSession]
    public var cardio: [ExportCardio]
    public var assessments: [ExportAssessment]
    public var exercises: [ExportExercise]       // NEW
    public var coachPreferences: ExportCoachPreferences?
    public var preferences: ExportPreferences?
}

public struct ExportExercise: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var category: String?
    public var primaryMuscles: [String]
    public var secondaryMuscles: [String]
    public var equipment: String?
    public var isLateral: Bool
    public var mechanics: String?
    public var force: String?
    public var level: String?
    public var instructions: [String]
    public var defaultBarWeightKg: Double
    public var loadAccountingMode: String?
}
```

In `buildExport()`, iterate `allExercises(context)` and export only custom exercises (`isCustom == true`). Built-in exercises are reconstructed from the library on import, so we don't need to export them.

Version 5 is backward-compatible: the `exercises` field has a default value of `[]` in the Codable conformance, so decoding a v4 export produces an empty array. Old imports (no exercises array) still work — they create exercises with empty facets (Phase 4 insight will catch this).

## 5b. Import custom exercise definitions

In the `merge` import function, before importing sessions:

1. Check `exercises` is present and non-empty
2. For each `ExportExercise`:
   - If an exercise with the same UUID already exists locally → skip (don't overwrite user's local edits)
   - If an exercise with the same name already exists locally → skip (local wins)
   - Otherwise → create a new `Exercise` with all exported facets (primaryMuscles, secondaryMuscles, equipment, mechanics, force, isCustom: true, etc.)

This gives idempotent round-trip: export → import → export produces identical output for custom exercises.

## 5c. Round-trip test

Add tests that:
1. Create a session with a custom exercise (e.g., "rotary torso" with category: core, primaryMuscles: ["abs"])
2. Build a `CadenceExport` (version 5)
3. Encode to JSON
4. Decode from JSON
5. Verify `exercises` array is present and contains the custom exercise with correct facets
6. Import into a fresh store
7. Verify the exercise exists with correct `primaryMuscles == ["abs"]` and `isCustom == true`
8. Re-export and verify identical exercise data
9. Test v4 backward compat: decode a v4 JSON (no `exercises` key) and verify it produces `exercises: []`
10. Test name-conflict: import an export with a custom exercise whose name matches an existing local exercise → local wins, no duplicate

**Files to change:**
- `CadenceCore/Sources/CadenceCore/DataExport.swift` — add `ExportExercise`, add `exercises` to `CadenceExport` (default `[]`), bump version to 5
- `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift` — update `buildExport()`, update `merge()` import path
- `CadenceCore/Tests/CadenceCoreTests/DataExportTests.swift` — round-trip tests for custom exercises

---

# Implementation Order & Dependencies

```
Phase 1 (core)     ← no deps, unblocks all others
  ├── Phase 5 (export)       ← needs 1a for muscle field definitions
  ├── Phase 3 (settings)     ← needs Phase 1 (merge uses new fallback)
  ├── Phase 2 (UI picker)    ← needs 1a, 1b, 1c
  └── Phase 4 (insight)      ← needs 1a, 3b for navigation target
```

**Recommended execution order:** 1 → 5 → 3 → 2 → 4

---

# Resolved Open Questions

1. **Match suggestion threshold** — Keep as proposed: `normalize(libraryName).contains(normalize(query))` OR vice versa. Works well for practical exercise names.

2. **Category guessing heuristic** — Base on existing exercise names in `ExerciseLibrary` + `free-exercise-db` + common fitness naming conventions. Rule set in Phase 1c. Covers: press/push/extension/fly/raise → push; curl/row/pulldown/snatch/clean → pull; squat/deadlift/lunge/leg/calf/step → legs; crunch/abs/core/plank/torso → core.

3. **Citation for exercise definition insight** — Brennan et al. (2025), "Exercise Classification in Resistance Training: A Systematic Review of Technological Approaches", Sports Medicine. DOI: 10.1007/s40279-025-02281-8. PMC12513948. States: "Accurate classification of resistance training exercises is essential for quantifying training loads, monitoring adherence, and informing exercise programming decisions."

4. **Delete & reassign as merge** — Context menu on each custom exercise row: "Delete & reassign to library exercise". Opens picker with suggested similar built-in exercises (filtered by matching category). User picks target → all sets reassigned → custom exercise deleted.

5. **Post v4 import** — No special hook needed. The incomplete-custom-exercise insight already fires on every coach snapshot rebuild. After import, session count changes → snapshot rebuilds → insight appears automatically if any imported custom exercises lack muscles.
