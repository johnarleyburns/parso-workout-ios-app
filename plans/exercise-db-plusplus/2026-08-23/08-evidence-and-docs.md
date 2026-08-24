# Phase 8 — Evidence surfacing, citations, docs and attribution

**Depends on:** Phases 3 and 7. **UI impact:** yes. **`make smoke` required.**

## Problem

DB++ ships 60 references (PMIDs/DOIs) and 89 pattern-level evidence summaries
explaining *why* a muscle is direct rather than indirect for a given movement.
Right now the app makes muscle-role claims — Home's volume rows, the suggested
workout's credit arithmetic, the exercise detail screen's muscle lists — with no
route to that literature. That violates the standing HARD RULE that every
coaching output cites navigable science.

## 1. `ExerciseEvidence` (new, `CadenceCore/Sources/CadenceCore/ExerciseEvidence.swift`)

```swift
/// The literature behind free-exercise-db++'s muscle-role annotations. Built from
/// the bundled document, so it can never drift from the data it explains.
public enum ExerciseEvidence {

    /// One movement pattern's evidence: a plain-language summary plus the papers.
    public struct PatternEvidence: Equatable, Sendable, Identifiable {
        public let id: String            // e.g. "horizontal_press"
        public let displayName: String   // "Horizontal Press"
        public let status: String        // "supported" | ...
        public let summary: String
        public let citationIDs: [String] // resolvable via CitationRegistry.citation(forId:)
    }

    /// All 89 patterns, keyed by id.
    public static let patterns: [String: PatternEvidence]

    /// The 60 DB++ references as `Citation` values. Ids are prefixed `exdb.` to
    /// keep them unambiguously separate from the curated coaching bibliography.
    public static let citations: [Citation]

    /// Evidence for one exercise, from its `movementPatternIDs`.
    public static func evidence(forPatternIDs ids: [String]) -> [PatternEvidence]
}
```

Mapping a DB++ reference to our `Citation`:

- `id` → `"exdb." + refId` (e.g. `exdb.bench_systematic_review_2017`)
- `authors` → `"free-exercise-db++ reference"` is **not** acceptable — the
  reference objects carry no author field. Use the paper's short title as
  `title`, `source` = the DB++ `type` humanised (`systematic_review` →
  "Systematic review", `experimental` → "Experimental study",
  `meta_regression` → "Meta-regression", `review_or_position` → "Review /
  position statement", `training_intervention` → "Training intervention",
  `randomized_controlled_trial` → "Randomized controlled trial"), `year` parsed
  from the trailing 4 digits of the ref id (all 60 end in a year), and
  `authors` = `""`.
  **`Citation.shortText` must not break on an empty author string** — it currently
  does `authors.split(separator: " ").first`. Add a guard: when `authors` is
  empty, `shortText` returns `"\(source) (\(year))"`. Cover it with a test.
- `url` → the DB++ `url` (always populated; PubMed or DOI).

`displayName` for a pattern id: split on `_`, capitalise each word, with a small
override table for the ones that read badly
(`kettlebell_figure8` → "Kettlebell Figure 8", `olympic_clean_and_jerk` →
"Olympic Clean and Jerk", `horizontal_press_triceps_bias` → "Horizontal Press
(Triceps Bias)", `elbow_flexion_brachioradialis_bias` → "Elbow Flexion
(Brachioradialis Bias)", `dip_chest_bias` → "Dip (Chest Bias)",
`dip_triceps_bias` → "Dip (Triceps Bias)", `squat_quad_bias` → "Squat (Quad
Bias)", `plantar_flexion_straight_knee` → "Plantar Flexion (Straight Knee)",
`plantar_flexion_bent_knee` → "Plantar Flexion (Bent Knee)").

## 2. `CitationRegistry` fall-through (decision D8)

```swift
public static func citation(forId id: String) -> Citation? {
    if let hit = byID[id] { return hit }
    return ExerciseEvidence.citationsByID[id]      // new fall-through
}
```

`CitationRegistry.all` and `usageReasons` are **not** extended, so the existing
1:1 integrity test keeps passing untouched. Add a note in `Citation.swift`
explaining the two-tier design: `all` is the curated coaching bibliography with
hand-written usage reasons; `ExerciseEvidence.citations` is generated movement
evidence that explains muscle attributions rather than coaching decisions.

## 3. `ExerciseDetailView` — show the roles and their evidence

Currently (lines 136–143) it renders `Primary` / `Secondary` muscle lists from
`exercise.primaryMuscles` / `secondaryMuscles` via a private `display(_:)`.

Replace with three labelled rows using `MuscleGroup.displayName`:

```
Trains directly      Chest
Trains indirectly    Triceps, Shoulders
Stabilises           —                      (omitted when empty)
```

Below them:

- A caption: `"Direct sets count once toward weekly volume, indirect sets count
  half, and stabilisers count zero."` with a `CitationLink` for
  `pellandDoseResponse2026`.
- For each `PatternEvidence` from the exercise's `movementPatternIDs`: the
  pattern `displayName`, its `summary`, and a `CitationLink` per reference
  (`compact: true`). Identifier `exercise.evidence.<patternID>`.
- When `annotationConfidence == nil` (a curated entry with no DB++ match, Phase 3
  §3.3), show instead: `"Muscle roles for this movement are Cladiron's own
  mapping — no published movement analysis is attached."` No fabricated citation.
- When `annotationConfidence == "medium"`, append `"Attribution confidence:
  medium."` to the caption.

Keep the existing attribution link, updated to name DB++ (see §5).

The file is 190 LOC and this adds ~50; if it crosses 400 it must be split, but it
will not.

## 4. Docs + guardrail

- `docs/CITATIONS.md`: add a section
  ```
  ## Movement evidence (generated — do not hand-edit)

  <!-- BEGIN exercise-evidence -->
  ...one line per DB++ reference: `exdb.<id>` — Title. **Source type**, PMID/DOI, URL
  <!-- END exercise-evidence -->
  ```
  plus a paragraph above the markers explaining that these back muscle-role
  attributions rather than coaching decisions, and that they are regenerated from
  the bundled snapshot.
- `scripts/generate-exercise-citations.py` (new): reads the bundled DB++ JSON and
  rewrites the block between the markers. Run once, commit the result.
- `scripts/check-citations-sync.sh` (new): regenerates into a temp file and
  `diff`s against `docs/CITATIONS.md`; non-zero exit on drift. Wire it into the
  `guardrails` target in the `Makefile` (`bash scripts/check-citations-sync.sh`)
  so a data refresh that adds a reference cannot land without the doc update.

## 5. Attribution

- `Cadence/Cadence/Features/Settings/AboutView.swift` and
  `ExerciseDetailView`: `ExerciseLibrary.exerciseRepoURL` currently points at
  `yuhonas/free-exercise-db`. Add
  ```swift
  static let exerciseAnnotationRepoURL =
      URL(string: "https://github.com/johnarleyburns/free-exercise-db-plusplus")!
  ```
  and show both — "Exercise data: free-exercise-db++ (annotations) /
  free-exercise-db (source data and imagery)". Both are displayed and opened in
  Safari on tap; neither is fetched (`scripts/check-no-network.sh` unchanged).
- `README.md`: update the exercise-database paragraph to name DB++, the 20-muscle
  ontology, the direct/indirect/stabilizer set-credit model, and the five
  suggested-workout styles.
- `CadenceCore/CREDITS.md`: already updated in Phase 1 — verify it still matches.

## Tests

`CadenceCoreTests/ExerciseEvidenceTests.swift` (new)

- `testAllSixtyReferencesBecomeCitations`
- `testEveryEvidenceCitationHasUrlAndYear`
- `testCitationRegistryResolvesExerciseEvidenceIds`
- `testCuratedRegistryIsUnchanged` — `CitationRegistry.all.count` equals the
  pre-phase value (hard-code it) and `usageReasons.count == all.count`
- `testShortTextHandlesEmptyAuthors`
- `testEveryPatternHasSummaryAndAtLeastOneCitation`
- `testEveryExercisePatternResolves` — for all 873 records, every
  `movementPatternIDs` entry resolves in `ExerciseEvidence.patterns`
- `testPatternDisplayNamesAreHumanReadable` — no underscores in any display name

`CadenceCoreTests/CitationIntegrityTests.swift` (existing) — unchanged and must
pass unmodified. That is the point of D8.

Smoke test: within the existing flow, after opening an exercise, assert
`exercise.evidence.*` exists for a movement known to have a pattern (the flow
already opens an exercise; pick whichever it uses).

## Verification

```
make ci && make smoke
```

## Acceptance criteria

- [ ] Every DB++ reference resolves through `CitationRegistry.citation(forId:)`
      and renders through `CitationLink`; no raw id is ever displayed.
- [ ] The exercise detail screen shows direct / indirect / stabiliser roles and
      the literature behind them, or says plainly when there is none.
- [ ] `docs/CITATIONS.md` has a generated movement-evidence section and
      `make guardrails` fails if it drifts.
- [ ] Attribution names both repositories; no runtime network path added.
- [ ] `CitationIntegrityTests` passes **unmodified**.
- [ ] `make ci` and `make smoke` green.

## Commit

`feat: cite the movement evidence behind every muscle attribution`

---

## After phase 8 — follow-ups deliberately not in scope

- DB++'s `workout.schema.json` as an interchange format for export/import.
- `competitionMovements` (5 records) surfacing as a "competition lift" badge.
- `reviewReasons` (`complex_pattern_bookkeeping`, 72 records) as a quality filter
  in the picker.
- Per-`MuscleGroup` volume landmarks personalised from the user's own response
  (`VolumeGuidance` already exists for this and stays untouched here).
