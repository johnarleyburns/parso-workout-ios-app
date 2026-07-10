# Export Freeze/Crash — Root Cause & Fix Plan (rev 2)

**Repo:** `johnarleyburns/parso-workout-ios-app` (Cadence / Cladiron)
**Status:** Diagnosed. Prior fix (`fd0a106` — Task.detached off-main build) addressed the wrong stage.
**Severity:** Watchdog termination (0x8badf00d) / Jetsam on device with realistic data. Simulator tests pass because seeded data is tiny and the simulator has no watchdog.

---

## 1. Root cause (primary)

`ExportView.swift` renders the **entire export payload** in a SwiftUI `Text`:

```swift
Text(preview.isEmpty ? "No data to export." : preview)
    .font(.system(.caption, design: .monospaced))
    .textSelection(.enabled)
```

- `Text` layout is **monolithic** — `ScrollView` does not make it lazy. The full string is laid out before first frame.
- `.textSelection(.enabled)` routes through heavier UITextView-adjacent machinery.
- The freeze happens at `MainActor.run { preview = previewText }` — i.e. **after** the background build completes. This is why moving `buildExport` to `Task.detached` didn't fix it.

### Data volume math

- HR sampled at **1 Hz**: `CardioRecorder.tick()`, `IntervalView`, `SessionView.sampleHR()`. HealthKit import (`HealthKitProvider`) brings full per-workout HR series for the user's entire Watch history.
- Route samples on top for GPS types (`run`, `cycle`, `walk`).
- Encoder uses `.prettyPrinted` — each `ExportHRSample` costs ~4 lines / ~45 bytes.
- **One 1-hour run ≈ 3,600 HR + 3,600 route samples ≈ 0.5 MB of JSON.** A year of history: tens of MB. `Text` layout of that blocks the main thread for minutes → watchdog kill, or CoreText glyph storage blows memory → Jetsam.

## 2. Accomplice bugs (same file / path)

| # | Location | Problem |
|---|----------|---------|
| A | `ShareLink(item: preview)` | Shares a multi-MB `String` as an in-memory item; share-sheet serialization spikes memory. |
| B | Restore `TextEditor(text: $restoreText)` | Pasting a large JSON into UITextView hangs on its own, before merge even runs. |
| C | `restore()` | Runs `DataExport.decodeJSON` + `WorkoutRepository.merge` **synchronously on the main thread**. |
| D | `merge()` → `findOrCreateExercise` | Full `allExercises(context)` fetch **per set** → O(sets × exercises). |
| E | `merge()` sample inserts | Inserts every HRSample/RouteSample into one context with a single terminal `save()` — unbounded memory for large imports. |
| F | `rebuild()` | `buildTask?.cancel()` is called but the task never checks `Task.isCancelled`; toggling JSON↔CSV mid-build runs two full exports concurrently (2× peak memory). |
| G | `merge()` dedup | `Set(try allSessions(context).map(\.id))` faults full models just for IDs; use `propertiesToFetch: [\.id]`. |

## 3. Fix plan

### 3.1 ExportView — summary only, no payload shown (rev)

The preview `Text` is **removed entirely**. Replace with a summary card computed in the background task alongside the encode:

- Strength sessions: count (and total sets)
- Cardio workouts: count, with per-type breakdown (run / cycle / swim / boxing / hiit / walk / rowing / other)
- HR points: total count
- Route points: total count
- Assessments: count
- Date span: first workout date, last workout date, number of days covered
- Preferences: included yes/no, number of settings keys exported; Coach profile included yes/no (with preference + event counts)
- Total size: encoded bytes via `ByteCountFormatter` (KB/MB), shown for both raw and compressed (§3.6)

New `ExportSummary` struct (Sendable) in CadenceCore, computed from the `CadenceExport` DTO — unit-testable without UI. `@State` holds `exportURL: URL?` and `summary: ExportSummary?`; no full-payload string ever touches SwiftUI. Keep an `accessibilityIdentifier("export.summary")`; retire `export.preview` (update `FR6MigrationUITests` + `AppStoreScreenshotsUITests` accordingly).

### 3.2 Export as a file, share a URL

- Detached task writes to `FileManager.default.temporaryDirectory / "Cladiron-Export-\(ISO8601 date).json.gz"` (see §3.6; `.csv` stays uncompressed).
- `ShareLink(item: url)` — streams, real filename, works with Files/AirDrop.
- Delete stale temp exports on view appear.

### 3.3 Encoder

- Drop `.prettyPrinted`; keep `[.sortedKeys, .withoutEscapingSlashes]`. Round-trip unaffected — tests compare decoded structs, not bytes. Verify `DataExportTests` don't assert on formatting.

### 3.4 Restore path

- Replace `TextEditor` with `.fileImporter` accepting `.json`, `.gz`, and (optionally) `.zip`.
- Run decode + merge in `Task.detached` with a fresh `ModelContext(container)`; progress UI; honor `Task.isCancelled`; surface result via `MainActor.run`.

### 3.5 merge() performance

- Build `var exerciseByName: [String: Exercise]` once (case-folded keys) before the session loop; insert-on-miss updates the dict. Same for `findOrCreatePerson`.
- Dedup ID sets via `FetchDescriptor` with `propertiesToFetch: [\.id]`.
- Batch `context.save()` every ~25 cardio workouts (or ~50k sample inserts) to bound memory.

### 3.6 Compression (rev — evaluated: YES, gzip)

The payload is highly compressible: repeated JSON keys (`"t"`, `"bpm"`, `"lat"`, `"lon"`, `"elevation"`) and numerically similar values give **~15–20× deflate ratio** on HR/route-heavy exports; combined with dropping pretty-print, expect **~25–50× smaller files** than today (tens of MB → sub-MB).

**Chosen format: gzip (`.json.gz`)** via the system Compression framework (zlib deflate + a ~40-line gzip header/CRC32 wrapper). Rationale:

- **No dependency** — fits the Parso no-third-party posture; Apple's `libcompression` is first-party.
- **Universally openable** — every desktop OS unpacks `.gz`; preserves user sovereignty over their data (a raw `.aar` Apple Archive fails this test → rejected).
- ZIPFoundation `.zip` was considered (nicer Files-app double-click) but adds a dependency for marginal gain; **optional** follow-up: accept `.zip` on *import* only if users bring one.

**Import sniffs magic bytes** and never breaks back-compat:

| Bytes | Format | Action |
|-------|--------|--------|
| `1F 8B` | gzip | inflate → decode JSON |
| `50 4B` | zip | (optional) unzip first entry → decode |
| `{` / whitespace | plain JSON | decode directly — **accepted forever** (all v1–v4 exports remain importable) |

Decompression runs in the same detached import task; a 4 GB inflated-size sanity cap guards against zip-bomb-style inputs.

## 4. Test plan

### 4.1 Comprehensive round-trip seed fixture (rev)

A single `ExportRoundTripFixture` seeder in CadenceCore (shared by unit + UI tests) covering **every type and subtype**:

**Cardio — one of each `CardioType`:** run (HR + GPS route), cycle (HR + route), walk (route, no HR), swim (HR, no route), rowing (machine source), boxing (custom interval `IntervalSummary`), other (with `customTitle`, e.g. "Yardwork"), plus a HealthKit-imported workout (`importedWorkoutKindRaw` set, `source: .watch`) and one manually-logged (`isLogged: true`, no samples).

**HIIT — one per interval preset** (each with distinct `intervalDetailData`): `tabata`, `norwegian` 4×4, `gibala`, `sit` (Wingate), `ten` (10-20-30), `rehit`, and a `custom` plan with non-default rounds/work/rest/warm-up/cool-down.

**Strength — structural variations:**
1. one exercise, one set (minimal)
2. multiple exercises × multiple sets
3. warm-up sets (`isWarmup`) mixed with working sets
4. sets with RPE + per-set notes; session notes
5. partner session: `activePartnerIDs` + sets with `performedBy` ≠ owner
6. bodyweight sets (`usesBodyweight`)
7. each `loadAccountingMode` variant with `barWeightKg` / `loadMultiplier`
8. plan-based session: `planKey`, `templateName`, `plannedExerciseNames`, `plannedRepLadder`, `warmupSeconds`/`cooldownSeconds`, `prescribedLoadKg`, `endedAt`

**Assessments:** one of each `AssessmentKind`, exercising every optional input field (weight/reps, distance/time, ending HR, age/sex, protocolName, notes).

**Preferences:** every `ExportPreferences` field non-default; populated `ExportCoachPreferences` (aerobic + strength preferences, avoided tags, selection events).

**Round-trip assertion:** export → wipe store → import → export again → compare decoded `CadenceExport` structs field-by-field (ignoring `exportedAt`). Any subtype not surviving fails with a named diff.

### 4.2 Coach determinism check (rev)

`CoachFacts` carries `referenceDate` — pin it for reproducibility:

1. On the seeded store, build `CoachFacts` with a **fixed** `referenceDate` and fixed preferences; capture the full recommendation set (rules + add-on engine outputs) as a canonical, sorted DTO list.
2. Export → wipe → import (including preferences + coach profile).
3. Rebuild `CoachFacts` with the **same** `referenceDate`; recompute recommendations.
4. Assert recommendation lists are **exactly equal** — proves the export is lossless *for coach-relevant state* and the engine is deterministic given identical facts.
5. If any nondeterminism surfaces (unseeded RNG, unordered dictionary iteration, `Date()` calls inside rules), fix at the source — determinism is a coach-quality property worth owning, consistent with the evidence-gated `Prescription` posture.

### 4.3 Scale / regression

1. **Unit:** `buildExport` + `encodeJSON` + gzip on 50 cardio workouts × 3,600 HR + 3,600 route samples; assert completion, compressed size ≪ raw.
2. **UI (must fail on current `main`):** seed the same volume via launch-argument path used by `FR6MigrationUITests`; open Export; assert `export.summary` appears within 10 s and the screen stays hittable. Current main blows the timeout on `Text` layout — proving repro.
3. **UI round-trip:** export file → fileImporter import into wiped store → summary counts match pre-export summary.

## 5. Non-goals

- No schema/model changes; `CadenceExport` v4 format unchanged (compact + gzip are byte-level only; plain JSON import kept forever).
- No streaming JSON encoder — `JSONEncoder` off-main is fine at this scale once nothing renders the result. Revisit only past ~200 MB raw.

## 6. Acceptance criteria

- [ ] Export screen shows the summary card in <1 s with the §4.3 seed on device; no full payload string ever assigned to SwiftUI state.
- [ ] Share produces a named `.json.gz` (or `.csv`); peak memory <150 MB during export + share.
- [ ] Import accepts `.json.gz` and plain `.json` (magic-byte sniff); completes off-main with progress; UI never blocks >100 ms.
- [ ] §4.1 fixture round-trips losslessly — every cardio type, every HIIT preset, all eight strength variations, all assessment kinds, all preferences.
- [ ] §4.2 coach recommendations identical pre-export vs post-import at pinned `referenceDate`.
- [ ] JSON↔CSV toggle mid-build never runs two builds concurrently.
