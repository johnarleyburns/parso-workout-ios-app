# Agentic Coding Handoff: Custom Exercise Completeness

**Source plan:** `.opencode/plans/custom-exercise-completeness.md`
**Date:** 2026-07-10
**Target:** SwiftUI iOS app (Cadence), CadenceCore Swift package

---

## Executive Summary

Custom exercises with empty `primaryMuscles` are invisible to the coach's volume accounting, causing phantom deficits and naggy "planned volume needs attention" insights. Five phases fix this end-to-end:

| Phase | Summary | Test gate |
|-------|---------|-----------|
| 1 | Category→muscle/bodypart fallback + name→category guessing | `swift test` all green |
| 5 | Custom exercises in JSON export/import round-trip | `swift test` all green |
| 3 | Settings → Custom Exercises list with edit + delete & reassign | Builds, navigable |
| 2 | Exercise picker: match suggestion card + pre-creation pills | Builds, picker flow works |
| 4 | Coach insight "Custom exercises need muscle definitions" | Builds, insight appears |

**Critical dependency chain:** 1 → 5 → 3 → 2 → 4. Phase 1 unblocks everything. Phases 2 and 4 touch UI but depend on core changes from 1.

---

## Environment

- **Core package:** `CadenceCore/` — pure Swift, headlessly testable
- **App target:** `Cadence/Cadence/` — SwiftUI views
- **Test commands:** `cd CadenceCore && swift test` (core) and `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build` (full app)
- **Key conventions:** Logic in CadenceCore, thin UI on top. No comments unless asked. Follow existing patterns (FlowLayout chips, NavigationLink routes, `@Query` for SwiftData).

---

## Phase 1 — Core: Category-to-Muscle & Category-to-BodyPart

### Files to modify

**1. `CadenceCore/Sources/CadenceCore/BodyPart.swift`** — Add three static functions:

```swift
// Add after the existing parts(forMuscleIDs:) function (after line 46):

/// Body parts implied by an exercise category. Used as a fallback when
/// primaryMuscles is empty but the category is known.
public static func parts(forCategory cat: ExerciseCategory) -> Set<BodyPart> {
    switch cat {
    case .push: return [.chest, .shoulders, .triceps]
    case .pull: return [.back, .biceps]
    case .legs: return [.legs, .calves]
    case .core: return [.abs]
    case .cardio, .plyometrics, .other: return []
    }
}

/// Default primary muscle IDs for an exercise category. Used when creating
/// a custom exercise where no template exists but a category is provided.
public static func defaultMuscles(forCategory cat: ExerciseCategory) -> [String] {
    switch cat {
    case .push: return ["chest", "delts", "triceps"]
    case .pull: return ["lats", "biceps"]
    case .legs: return ["quads", "hamstrings", "glutes"]
    case .core: return ["abs"]
    case .cardio, .plyometrics, .other: return []
    }
}

/// Guess an ExerciseCategory from a raw name using common fitness naming
/// conventions observed across ExerciseLibrary + free-exercise-db.
public static func guessCategory(from name: String) -> ExerciseCategory? {
    let lower = name.lowercased()
    if lower.contains("press") || lower.contains("push") || lower.contains("extension")
        || lower.contains("fly") || lower.contains("raise") || lower.contains("overhead") {
        return .push
    }
    if lower.contains("curl") || lower.contains("row") || lower.contains("pulldown")
        || lower.contains("pull") || lower.contains("snatch") || lower.contains("clean") {
        return .pull
    }
    if lower.contains("squat") || lower.contains("deadlift") || lower.contains("lunge")
        || lower.contains("leg") || lower.contains("calf") || lower.contains("step")
        || lower.contains("hip thrust") || lower.contains("glute") {
        return .legs
    }
    if lower.contains("crunch") || lower.contains("abs") || lower.contains("core")
        || lower.contains("plank") || lower.contains("sit-up") || lower.contains("torso")
        || lower.contains("russian twist") || lower.contains("leg raise") {
        return .core
    }
    return nil
}
```

**2. `CadenceCore/Sources/CadenceCore/TrainingFacts.swift`** — In `make()`, at line 188, after computing `primary`, add category fallback:

```swift
// Existing (line 188):
let primary = BodyPart.parts(forMuscleIDs: ws.exercise.primaryMuscles)

// Change to:
var primary = BodyPart.parts(forMuscleIDs: ws.exercise.primaryMuscles)
if primary.isEmpty, let cat = ws.exercise.categoryValue {
    primary = BodyPart.parts(forCategory: cat)
}
```

Note: `primary` changes from `let` to `var`. The `secondary` line (189) doesn't need this — secondary muscles are ancillary and the category fallback only covers primary intent.

**3. `CadenceCore/Sources/CadenceCore/CoachPlanOptimizer.swift`** — In `partsCovered(by:)` (line 792), add category fallback:

```swift
private static func partsCovered(by exercise: CoachSession.RecommendedExercise) -> Set<BodyPart> {
    let muscles = muscleIDs(for: exercise)
    let primary = BodyPart.parts(forMuscleIDs: muscles.primary)
        .union(BodyPart.parts(forMuscleIDs: muscles.secondary))
    // If muscles are empty but the exercise name suggests a category, derive parts
    if primary.isEmpty, !exercise.name.isEmpty {
        // Try lookup in library first, then guess from name
        if let template = ExerciseLibrary.byName[exercise.name.lowercased()] {
            return BodyPart.parts(forMuscleIDs: template.primaryMuscles)
                .union(BodyPart.parts(forMuscleIDs: template.secondaryMuscles))
        }
        if let cat = BodyPart.guessCategory(from: exercise.name) {
            return BodyPart.parts(forCategory: cat)
        }
    }
    return primary
}
```

**4. `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift`** — In `findOrCreateExercise` (around line 189-190), pre-fill muscles from category:

```swift
// Existing:
let resolvedPrimary = primaryMuscles.isEmpty ? (template?.primaryMuscles ?? []) : primaryMuscles

// Change to:
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

Do the same pattern for `resolvedSecondary` (line 190).

Also update the `muscleGroups` parameter on the `Exercise` init call (line 194): `muscleGroups: resolvedPrimary + resolvedSecondary` (use the new resolved values).

**5. `CadenceCore/Sources/CadenceCore/PlanAwareInsightEngine.swift`** — In `muscleIDs(for:)` (line 40-48), add category fallback:

```swift
private static func muscleIDs(for exercise: CoachSession.RecommendedExercise) -> (primary: [String], secondary: [String]) {
    if !exercise.primaryMuscles.isEmpty {
        return (exercise.primaryMuscles, [])
    }
    if let template = ExerciseLibrary.byName[exercise.name.lowercased()] {
        return (template.primaryMuscles, template.secondaryMuscles)
    }
    // Fallback: derive muscles from category guessed from the name
    if let cat = BodyPart.guessCategory(from: exercise.name) {
        return (BodyPart.defaultMuscles(forCategory: cat), [])
    }
    return ([], [])
}
```

### Tests for Phase 1

Add to `CadenceCore/Tests/CadenceCoreTests/BodyPartTests.swift` (create if it doesn't exist, or find the existing test file for BodyPart):

```swift
func testPartsForCategory() {
    XCTAssertEqual(BodyPart.parts(forCategory: .push), [.chest, .shoulders, .triceps])
    XCTAssertEqual(BodyPart.parts(forCategory: .pull), [.back, .biceps])
    XCTAssertEqual(BodyPart.parts(forCategory: .legs), [.legs, .calves])
    XCTAssertEqual(BodyPart.parts(forCategory: .core), [.abs])
    XCTAssertTrue(BodyPart.parts(forCategory: .cardio).isEmpty)
    XCTAssertTrue(BodyPart.parts(forCategory: .other).isEmpty)
}

func testDefaultMusclesForCategory() {
    XCTAssertFalse(BodyPart.defaultMuscles(forCategory: .push).isEmpty)
    XCTAssertFalse(BodyPart.defaultMuscles(forCategory: .pull).isEmpty)
    XCTAssertFalse(BodyPart.defaultMuscles(forCategory: .legs).isEmpty)
    XCTAssertFalse(BodyPart.defaultMuscles(forCategory: .core).isEmpty)
    XCTAssertTrue(BodyPart.defaultMuscles(forCategory: .cardio).isEmpty)
}

func testGuessCategory() {
    XCTAssertEqual(BodyPart.guessCategory(from: "Bench Press"), .push)
    XCTAssertEqual(BodyPart.guessCategory(from: "Triceps Extension"), .push)
    XCTAssertEqual(BodyPart.guessCategory(from: "Bicep Curl"), .pull)
    XCTAssertEqual(BodyPart.guessCategory(from: "Lat Pulldown"), .pull)
    XCTAssertEqual(BodyPart.guessCategory(from: "Back Squat"), .legs)
    XCTAssertEqual(BodyPart.guessCategory(from: "Romanian Deadlift"), .legs)
    XCTAssertEqual(BodyPart.guessCategory(from: "Crunches"), .core)
    XCTAssertEqual(BodyPart.guessCategory(from: "rotary torso"), .core)
    XCTAssertNil(BodyPart.guessCategory(from: "xyzzy"))
}
```

### Verification for Phase 1

```bash
cd CadenceCore && swift test
```

All existing tests + new tests must pass. No regressions.

---

## Phase 5 — Export/Import Round-Trip

### Files to modify

**1. `CadenceCore/Sources/CadenceCore/DataExport.swift`** — Add `ExportExercise` struct and update `CadenceExport`:

Add the new struct (near the other Export types):

```swift
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

    public init(id: UUID, name: String, category: String? = nil,
                primaryMuscles: [String] = [], secondaryMuscles: [String] = [],
                equipment: String? = nil, isLateral: Bool = false,
                mechanics: String? = nil, force: String? = nil,
                level: String? = nil, instructions: [String] = [],
                defaultBarWeightKg: Double = 0, loadAccountingMode: String? = nil) {
        self.id = id; self.name = name; self.category = category
        self.primaryMuscles = primaryMuscles; self.secondaryMuscles = secondaryMuscles
        self.equipment = equipment; self.isLateral = isLateral
        self.mechanics = mechanics; self.force = force
        self.level = level; self.instructions = instructions
        self.defaultBarWeightKg = defaultBarWeightKg; self.loadAccountingMode = loadAccountingMode
    }
}
```

Update `CadenceExport` — bump version to 5 and add `exercises` with default `[]` for backward compat:

```swift
public struct CadenceExport: Codable, Equatable, Sendable {
    public var version: Int = 5  // was 4
    public var exportedAt: Date
    public var sessions: [ExportSession]
    public var cardio: [ExportCardio]
    public var assessments: [ExportAssessment]
    public var exercises: [ExportExercise] = []   // NEW — default [] so v4 decodes
    public var coachPreferences: ExportCoachPreferences?
    public var preferences: ExportPreferences?
    // ... existing inits ...
}
```

**2. `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift`** — `buildExport()`: after building the sessions/cardio/assessments arrays, add:

```swift
let allEx = (try? allExercises(context)) ?? []
let customExercises: [ExportExercise] = allEx
    .filter { $0.isCustom }
    .map { ex in
        ExportExercise(
            id: ex.id,
            name: ex.name,
            category: ex.category,
            primaryMuscles: ex.primaryMuscles,
            secondaryMuscles: ex.secondaryMuscles,
            equipment: ex.equipment,
            isLateral: ex.isLateral,
            mechanics: ex.mechanics,
            force: ex.force,
            level: ex.level,
            instructions: ex.instructions,
            defaultBarWeightKg: ex.defaultBarWeightKg,
            loadAccountingMode: ex.loadAccountingMode)
    }
```

Pass `exercises: customExercises` into the `CadenceExport` init.

**3. `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift`** — `merge()` import: before the session-import loop, process the exercises array:

```swift
// Pre-load exercises from export (v5+)
var exerciseByName: [String: Exercise] = [:]
for exportEx in export.exercises {
    let key = exportEx.name.lowercased()
    // Check local cache — skip if already exists by name or UUID
    if exerciseByName[key] != nil { continue }
    let allLocal = (try? allExercises(context)) ?? []
    if allLocal.contains(where: { $0.id == exportEx.id || $0.name.lowercased() == key }) { continue }
    let ex = Exercise(
        id: exportEx.id,
        name: exportEx.name,
        category: exportEx.category.flatMap(ExerciseCategory.init(rawValue:)),
        primaryMuscles: exportEx.primaryMuscles,
        secondaryMuscles: exportEx.secondaryMuscles,
        equipment: exportEx.equipment.flatMap(Equipment.init(rawValue:)),
        isLateral: exportEx.isLateral,
        mechanics: exportEx.mechanics.flatMap(Mechanics.init(rawValue:)),
        force: exportEx.force.flatMap(Force.init(rawValue:)),
        instructions: exportEx.instructions,
        level: exportEx.level,
        defaultBarWeightKg: exportEx.defaultBarWeightKg,
        loadAccountingMode: exportEx.loadAccountingMode.flatMap(LoadAccountingMode.init(rawValue:)),
        isCustom: true)
    context.insert(ex)
    exerciseByName[key] = ex
}
```

Then inside the existing `resolveExercise` function, add a `check exerciseByName` cache at the top before querying the DB.

### Tests for Phase 5

Add to `CadenceCore/Tests/CadenceCoreTests/DataExportTests.swift`:

```swift
func testCustomExerciseRoundTrip() throws {
    // 1. Create a custom exercise + session
    let ex = Exercise(name: "rotary torso", category: .core,
                      primaryMuscles: ["abs"], secondaryMuscles: [],
                      isCustom: true)
    context.insert(ex)
    let session = WorkoutSession(...)  // session with sets referencing ex
    context.insert(session)
    try context.save()

    // 2. Export
    let export = try WorkoutRepository.buildExport(context: context)
    XCTAssertEqual(export.version, 5)
    XCTAssertEqual(export.exercises.count, 1)
    XCTAssertEqual(export.exercises.first?.name, "rotary torso")
    XCTAssertEqual(export.exercises.first?.primaryMuscles, ["abs"])

    // 3. Encode → decode
    let data = try JSONEncoder().encode(export)
    let decoded = try JSONDecoder().decode(CadenceExport.self, from: data)
    XCTAssertEqual(decoded.exercises.count, 1)

    // 4. Import into fresh store
    let newContext = try ModelContext(...)  // fresh in-memory store
    try WorkoutRepository.merge(decoded, into: newContext)
    let imported = try WorkoutRepository.allExercises(newContext)
    let rotary = imported.first { $0.name == "rotary torso" }
    XCTAssertNotNil(rotary)
    XCTAssertEqual(rotary?.primaryMuscles, ["abs"])
    XCTAssertTrue(rotary?.isCustom ?? false)

    // 5. Re-export and verify idempotent
    let reexport = try WorkoutRepository.buildExport(context: newContext)
    XCTAssertEqual(reexport.exercises.count, 1)
    XCTAssertEqual(reexport.exercises.first?.primaryMuscles, ["abs"])
}

func testV4BackwardCompat() throws {
    let v4JSON = """
    {"version":4,"exportedAt":"2026-01-01T00:00:00Z","sessions":[],"cardio":[],"assessments":[]}
    """
    let decoded = try JSONDecoder().decode(CadenceExport.self, from: Data(v4JSON.utf8))
    XCTAssertEqual(decoded.version, 4)
    XCTAssertTrue(decoded.exercises.isEmpty) // default [] from v5 field
}
```

### Verification for Phase 5

```bash
cd CadenceCore && swift test
```

All tests pass, including the new round-trip and v4 compat tests.

---

## Phase 3 — Settings: Custom Exercise List with Edit & Delete/Reassign

### Files to create

**1. `Cadence/Cadence/Features/Settings/CustomExerciseListView.swift`** — New file:

SwiftUI `List` with `@Query(sort: \Exercise.name)` filtered to `isCustom == true`. Each row renders:
- Exercise name (bold)
- Category chip (colored capsule, small)
- Body part chips from `BodyPart.parts(forMuscleIDs: ex.primaryMuscles)` with category fallback
- If `primaryMuscles.isEmpty`: orange badge "Incomplete"

Tapping a row opens `CustomExerciseEditView` (already exists at `Cadence/Cadence/Features/Train/CustomExerciseEditView.swift`) as a `.sheet`.

Context menu (`.contextMenu`) on each row:
- "Delete & reassign to library exercise" → opens a `.sheet` with a mini exercise picker showing only non-custom exercises, filtered to matching category (use `ExerciseCategory` from the custom exercise, or `BodyPart.guessCategory(from: name)`). Picker confirms, then calls `WorkoutRepository.reassignAndDeleteExercise(from:into:)`. Dismiss sheet, show toast/alert with count.
- "Edit" → opens `CustomExerciseEditView` sheet (same as tap).

Follow existing coding patterns: `@Environment(\.modelContext)`, `@Query`, NavigationStack with toolbar.

**2. `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift`** — Add `reassignAndDeleteExercise`:

```swift
@discardableResult
public static func reassignAndDeleteExercise(from custom: Exercise,
                                              into builtIn: Exercise,
                                              in context: ModelContext) throws -> Int {
    let allSessions = try context.fetch(FetchDescriptor<WorkoutSession>())
    var moved = 0
    for session in allSessions {
        guard let sets = session.sets else { continue }
        for set in sets where set.exercise?.id == custom.id {
            set.exercise = builtIn
            set.updatedAt = Date()
            moved += 1
        }
        var names = session.plannedExerciseNames
        if let idx = names.firstIndex(of: custom.name) {
            names[idx] = builtIn.name
            var seen = Set<String>()
            names = names.filter { seen.insert($0).inserted }
            session.plannedExerciseNames = names
        }
        session.updatedAt = Date()
    }
    context.delete(custom)
    try context.save()
    return moved
}
```

Add a test for this:
```swift
func testReassignAndDeleteExercise() throws {
    let custom = Exercise(name: "rotary torso", category: .core, primaryMuscles: [], isCustom: true)
    let builtIn = Exercise(name: "Torso Rotation", primaryMuscles: ["abs"], isCustom: false)
    context.insert(custom); context.insert(builtIn)
    let session = WorkoutSession(...)  // has sets referencing custom
    context.insert(session)
    try context.save()

    let moved = try WorkoutRepository.reassignAndDeleteExercise(from: custom, into: builtIn, in: context)
    XCTAssertEqual(moved, N) // N = number of sets originally on custom
    // Verify sets now reference builtIn
    // Verify custom is deleted
}
```

### Files to modify

**3. `Cadence/Cadence/Features/Settings/SettingsView.swift`** — Add "Exercises" section before "Data" section (or wherever makes visual sense):

```swift
Section("Exercises") {
    NavigationLink {
        CustomExerciseListView()
    } label: {
        Label("Custom Exercises", systemImage: "figure.strengthtraining.traditional")
    }
}
```

Optionally add a badge showing count of incomplete custom exercises. Use `@Query` in the label or a `@State` variable populated `.onAppear`.

### Verification for Phase 3

- Build and run: `xcodebuild -scheme Cadence -destination 'platform=iOS Simulator,name=iPhone 16' build`
- Navigate to Settings → Custom Exercises — list appears with custom exercises
- Tap a row → CustomExerciseEditView opens
- Long-press/context-menu → "Delete & reassign" → picker appears → select target → exercise reassigned
- `swift test` for the new `reassignAndDeleteExercise` test

---

## Phase 2 — Exercise Picker: Match Suggestion + Creation Pills

### Files to modify

**1. `Cadence/Cadence/Features/Train/ExercisePickerView.swift`**

**2a — Match suggestion card:** Add a computed property:

```swift
private var bestLibraryMatch: Exercise? {
    guard trimmedQuery.count >= 3 else { return nil }
    let normalized = ExerciseSearch.normalize(trimmedQuery)
    let builtIns = exercises.filter { !$0.isCustom }
    // Check for name containment (but not exact match)
    let matches = builtIns.filter { ex in
        let exName = ExerciseSearch.normalize(ex.name)
        guard exName != normalized else { return false }
        return exName.contains(normalized) || normalized.contains(exName)
    }
    // Pick highest-ranking from search index
    if matches.count == 1 { return matches[0] }
    if matches.count > 1 {
        return ExerciseSearchIndex(matches).rank(trimmedQuery).first
    }
    return nil
}
```

Render it in the List, above the "Create" Section but below filter chips. Something like:

```swift
if !trimmedQuery.isEmpty, let match = bestLibraryMatch {
    Section {
        HStack {
            Image(systemName: "sparkle.magnifyingglass")
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text("Found a good match")
                    .font(.subheadline.weight(.medium))
                Text(match.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Use this exercise") {
                onPick(match)
                dismiss()
            }
            .buttonStyle(.bordered).controlSize(.small)
        }
    }
}
```

**2b — Pre-creation confirmation sheet:** Change the "Create" button's action:

```swift
if !trimmedQuery.isEmpty && !exactMatchExists {
    Section {
        Button { showCreationSheet = true } label: {
            Label("Create \(query)", systemImage: "plus.circle.fill")
        }
    }
}
```

Add a `@State private var showCreationSheet = false` and `.sheet(isPresented: $showCreationSheet)` with the creation sheet content. The sheet view (inline or extracted to a private struct):

- Text showing the exercise name (non-editable)
- Category Picker: `Picker("Category", selection: $selectedCategory)` with `ExerciseCategory.allCases` (excluding cardio/plyometrics/other if desired). Initialized from `BodyPart.guessCategory(from: trimmedQuery) ?? .other`.
- Body Part chips: `FlowLayout` of `BodyPart.allCases` as selectable chips. Pre-selected from `BodyPart.parts(forCategory: selectedCategory)`. Allow user to toggle.
- Primary Muscle chips: `FlowLayout` grouped by `BodyRegion`, using the same chip pattern from `CustomExerciseEditView`. Pre-selected from `BodyPart.defaultMuscles(forCategory: selectedCategory)`. Allow toggle.
- When category changes, update pre-selected muscles accordingly.
- "Create & Add Exercise" button → calls `findOrCreateExercise(named:category:primaryMuscles:secondaryMuscles:)` → `onPick(ex)` → dismiss
- "Cancel" button

### Verification for Phase 2

- Build and run
- Open exercise picker, type "torso" — see "Found a good match: Torso Rotation" card with "Use this exercise" button
- Tap "Use this exercise" → picker dismisses, exercise is added
- Type "xyzzy123" — no match card, "Create xyzzy123" button appears
- Tap "Create xyzzy123" → confirmation sheet opens with Category: Other, no pre-selected muscles
- Change category to Core → Abs body part + abs primary muscle auto-selected
- Tap "Create & Add Exercise" → exercise created with muscles, picker dismisses

---

## Phase 4 — Coach Insight: Incomplete Custom Exercises

### Files to modify

**1. `CadenceCore/Sources/CadenceCore/Insight.swift`** — Add case to `InsightKind`:

```swift
public enum InsightKind: String, Sendable, Equatable {
    case volume
    case trend
    case frequency
    case intensity
    case assessment
    case coldStart
    case exerciseDefinition  // NEW
}
```

**2. `CadenceCore/Sources/CadenceCore/CoachCardView.swift`** — Add symbol in the extension:

```swift
extension InsightKind {
    var symbol: String {
        switch self {
        // ... existing cases ...
        case .exerciseDefinition: return "exclamationmark.triangle.fill"
        }
    }
}
```

**3. `CadenceCore/Sources/CadenceCore/TrainingFacts.swift`** — Add field and populate:

```swift
public struct TrainingFacts: Sendable {
    // ... existing fields ...
    public let incompleteCustomExerciseNames: [String]  // NEW

    public init(..., incompleteCustomExerciseNames: [String] = [], ...) {
        // ... existing assignments ...
        self.incompleteCustomExerciseNames = incompleteCustomExerciseNames
    }
}
```

In `make()`, after the `weekSets` loop, scan for incomplete custom exercises:

```swift
var incompleteCustom: Set<String> = []
for ws in weekSets where ws.exercise.isCustom && ws.exercise.primaryMuscles.isEmpty {
    incompleteCustom.insert(ws.exercise.name)
}
let incompleteCustomExerciseNames = incompleteCustom.sorted()
```

Pass to the `TrainingFacts` init return.

**4. `CadenceCore/Sources/CadenceCore/InsightRule.swift`** — Add new rule:

```swift
static let incompleteCustomExercises = InsightRule(
    id: "incompleteCustomExercises",
    priority: 35,
    produce: { facts in
        guard !facts.incompleteCustomExerciseNames.isEmpty else { return [] }
        let names = facts.incompleteCustomExerciseNames
        let count = names.count
        let examples = names.prefix(3).map { "'\($0)'" }.joined(separator: ", ")
        let message = count == 1
            ? "\(examples) is missing muscle data — the coach can't track volume for it."
            : "\(count) exercises (\(examples)) are missing muscle data — the coach can't track volume for them."
        return [Insight(
            id: "exerciseDefinition.incomplete",
            kind: .exerciseDefinition,
            title: "Custom exercises need muscle definitions",
            message: message,
            detail: "Accurate exercise classification is essential for quantifying training loads and informing programming decisions (Brennan et al., 2025). Tap to open Custom Exercises in Settings to edit or merge them.",
            citation: CitationRegistry.exerciseClassification,
            severity: .attention)]
    }
)
```

Add to `p3Rules`:
```swift
public static let p3Rules: [InsightRule] = [volumeVsLandmarks, e1RMTrend, frequency, intensityVsGoal, incompleteCustomExercises]
```

**5. `CadenceCore/Sources/CadenceCore/Citation.swift`** — Add citation:

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

Add to `all` array and create pool:

```swift
static let exerciseDefinitionPool = CitationPool(
    id: "exerciseDefinition",
    citationIds: ["brennanExerciseClassification2025"],
    summary: "Why accurate exercise classification matters for training.")
```

**6. `Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift`** — When `topInsight.kind == .exerciseDefinition`, add a "Fix in Settings" button below the insight content (next to or replacing "More insights"):

```swift
if topInsight.kind == .exerciseDefinition {
    Button { onFixCustomExercises() } label: {
        Label("Fix in Settings", systemImage: "gearshape")
    }
    .buttonStyle(.bordered)
}
```

Add `onFixCustomExercises: @escaping () -> Void` to the view's init and wire it up in `HomeView`.

**7. `Cadence/Cadence/Features/Home/HomeView.swift`** — Add route:

```swift
enum HomeRoute: Hashable {
    case history, settings, coach, coachPreview, coachPreferences, planning
    case yourPlan
    case workoutEditor(EditablePlan)
    case customExercises  // NEW
}
```

In the navigation destination switch:
```swift
case .customExercises:
    CustomExerciseListView()
```

In `coachTopSurface`, pass `onFixCustomExercises: { path.append(HomeRoute.customExercises) }`.

### Verification for Phase 4

- Build and run with data that has incomplete custom exercises
- Home screen should show an insight card: "Custom exercises need muscle definitions"
- Insight should show "Fix in Settings" button
- Tapping it navigates to Settings → Custom Exercises
- `swift test` — new insight rule produces correct output for empty/non-empty incomplete exercises

---

## Phase-by-Phase Test Gates

```
Phase 1: cd CadenceCore && swift test    ← ALL GREEN, no regressions
Phase 5: cd CadenceCore && swift test    ← new round-trip + v4 compat pass
Phase 3: xcodebuild ... build            ← compiles, navigable, merge works manually
Phase 2: xcodebuild ... build            ← compiles, picker flows work
Phase 4: xcodebuild ... build            ← compiles, insight renders, navigation works
```

Run `swift test` after EVERY phase. If something breaks, fix it before moving to the next phase.

---

## Files Changed Summary

| File | Phase | Action |
|------|-------|--------|
| `CadenceCore/Sources/CadenceCore/BodyPart.swift` | 1 | Add 3 functions |
| `CadenceCore/Sources/CadenceCore/TrainingFacts.swift` | 1, 4 | Category fallback + incompleteCustom names |
| `CadenceCore/Sources/CadenceCore/CoachPlanOptimizer.swift` | 1 | Category fallback in partsCovered |
| `CadenceCore/Sources/CadenceCore/WorkoutRepository.swift` | 1, 3, 5 | Muscle pre-fill, reassignAndDelete, export exercises |
| `CadenceCore/Sources/CadenceCore/PlanAwareInsightEngine.swift` | 1 | Category fallback in muscleIDs |
| `CadenceCore/Sources/CadenceCore/DataExport.swift` | 5 | ExportExercise, CadenceExport v5 |
| `CadenceCore/Sources/CadenceCore/Insight.swift` | 4 | New case exerciseDefinition |
| `CadenceCore/Sources/CadenceCore/InsightRule.swift` | 4 | New rule incompleteCustomExercises |
| `CadenceCore/Sources/CadenceCore/Citation.swift` | 4 | New citation + pool |
| `CadenceCore/Sources/CadenceCore/CoachCardView.swift` | 4 | Symbol for exerciseDefinition |
| `Cadence/Cadence/Features/Settings/CustomExerciseListView.swift` | 3 | **NEW FILE** |
| `Cadence/Cadence/Features/Settings/SettingsView.swift` | 3 | Add Exercises section |
| `Cadence/Cadence/Features/Train/ExercisePickerView.swift` | 2 | Match card + creation sheet |
| `Cadence/Cadence/Features/Coach/CoachDecisionCardView.swift` | 4 | Fix button for exerciseDefinition insight |
| `Cadence/Cadence/Features/Home/HomeView.swift` | 4 | HomeRoute.customExercises |
| `CadenceCore/Tests/CadenceCoreTests/BodyPartTests.swift` | 1 | New tests |
| `CadenceCore/Tests/CadenceCoreTests/DataExportTests.swift` | 5 | Round-trip + v4 compat tests |
| `CadenceCore/Tests/CadenceCoreTests/WorkoutRepositoryTests.swift` | 3 | ReassignAndDelete tests |
