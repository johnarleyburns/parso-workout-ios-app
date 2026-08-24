# Phase 1 — Vendor the DB++ snapshot and decode it

**Depends on:** nothing. **UI impact:** none. **Behaviour change:** none
(the produced `ExerciseTemplate`s are byte-for-byte what they are today).

## Problem

`CadenceCore/Sources/CadenceCore/Resources/free-exercise-db.json` is a 1 MB array
of 873 raw upstream records. `ImportedExerciseLibrary` decodes it into
`RawEntry` and maps it onto our taxonomy. There is no annotation layer, so we
cannot tell direct work from stabilizer work, cannot exclude non-volume movements,
and cannot cite anything for a muscle attribution.

## What the code does today

- `ImportedExerciseLibrary.RawEntry` — `Decodable` over the flat upstream record.
- `ImportedExerciseLibrary.templates` — `[ExerciseTemplate]`, lazily decoded from
  `Bundle.module`, `compactMap`ped through `template(from:)`. Order follows the
  source array.
- `ExerciseLibrary.starter` merges `curated` (124 hand-written templates) with
  `templates`, curated winning on a name/alias collision.
- `Package.swift` declares `.copy("Resources/free-exercise-db.json")` and
  `.copy("Resources/free-exercise-db.LICENSE")`.
- `scripts/update-exercises.sh` refreshes the snapshot from the upstream raw URL.
- `scripts/build-exercise-images.sh` is pinned to upstream commit `b0eed06` and is
  **not** run in CI.

## Verified precondition

The DB++ `source` object is byte-identical to our current snapshot for all 873
records and every field (verified 2026-08-23), and the id set matches the 873
bundled image directories exactly. **This phase therefore cannot change any
produced template.** That is the phase's own acceptance test.

## Design

Introduce a decoder for the whole DB++ document and re-express
`ImportedExerciseLibrary` on top of it, leaving its public surface untouched.

### New file: `CadenceCore/Sources/CadenceCore/ExerciseDatabase.swift`

```swift
import Foundation

/// The vendored free-exercise-db++ document (Unlicense — see `CREDITS.md`).
/// An evidence-audited annotation layer over `yuhonas/free-exercise-db`: every
/// upstream record is preserved verbatim under `source`, and DB++ adds movement
/// classification, direct/indirect/stabilizer muscle roles, volume eligibility,
/// and per-pattern literature references.
///
/// Decoded once, lazily, from `Bundle.module`. There is no runtime network path
/// (NFR-3) — `scripts/check-no-network.sh` enforces it.
public enum ExerciseDatabase {

    // MARK: Document

    public struct Document: Decodable, Sendable {
        public let metadata: Metadata
        public let exercises: [String: Record]
    }

    public struct Metadata: Decodable, Sendable {
        public let schemaVersion: String
        public let converterVersion: String
        public let generatedAt: String
        public let upstream: Upstream
        public let setCredits: SetCredits
        public let setCreditEvidence: SetCreditEvidence
        public let evidence: Evidence
        public let muscleOntology: [String]
        public let sourceExerciseCount: Int
        public let outputExerciseCount: Int
        public let completeness: String
    }

    public struct Upstream: Decodable, Sendable {
        public let project: String
        public let sourceUrl: String
        public let sha256: String?
    }

    public struct SetCredits: Decodable, Sendable {
        public let direct: Double
        public let indirect: Double
        public let stabilizer: Double
    }

    public struct SetCreditEvidence: Decodable, Sendable {
        public let status: String
        public let interpretation: String
        public let references: [String]
    }

    public struct Evidence: Decodable, Sendable {
        public let references: [String: Reference]
        public let patterns: [String: PatternEvidence]
    }

    public struct Reference: Decodable, Sendable {
        public let title: String
        public let type: String
        public let pmid: String?
        public let doi: String?
        public let url: String
    }

    public struct PatternEvidence: Decodable, Sendable {
        public let status: String
        public let summary: String
        public let references: [String]
    }

    // MARK: Record

    public struct Record: Decodable, Sendable {
        public let exerciseId: String
        public let classification: Classification
        public let annotation: Annotation
        public let source: Source
    }

    public struct Classification: Decodable, Sendable {
        public let trainingTypes: [String]
        public let modalities: [String]
        public let sportContexts: [String]
        public let competitionMovements: [String]
    }

    public struct Annotation: Decodable, Sendable {
        public let patterns: [String]
        public let direct: [String]
        public let indirect: [String]
        public let stabilizers: [String]
        public let volumeEligible: Bool
        public let confidence: String
        public let reviewReasons: [String]
        public let evidenceRefs: [String]
    }

    /// The upstream record, preserved verbatim by DB++.
    public struct Source: Decodable, Sendable {
        public let id: String
        public let name: String
        public let force: String?
        public let level: String?
        public let mechanic: String?
        public let equipment: String?
        public let primaryMuscles: [String]
        public let secondaryMuscles: [String]
        public let instructions: [String]
        public let category: String
        public let images: [String]
    }

    // MARK: Bundled data

    /// The decoded document, or `nil` if the resource is missing/corrupt — callers
    /// degrade to the curated catalog rather than trapping.
    public static let document: Document? = {
        guard let url = Bundle.module.url(forResource: "free-exercise-db-plusplus",
                                          withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Document.self, from: data)
        else { return nil }
        return decoded
    }()

    /// Every record, ordered by `exerciseId`. `exercises` is a JSON *object*, so
    /// decoding loses file order; sorting by id restores determinism, which the
    /// catalog merge and every fixture depend on.
    public static let records: [Record] = {
        guard let document else { return [] }
        return document.exercises.values.sorted { $0.exerciseId < $1.exerciseId }
    }()

    public static let recordsByID: [String: Record] = {
        Dictionary(records.map { ($0.exerciseId, $0) }, uniquingKeysWith: { a, _ in a })
    }()

    /// Case- and punctuation-insensitive lookup by upstream name, for attaching
    /// annotations to curated entries. Key is `source.name.lowercased()`.
    public static let recordsByName: [String: Record] = {
        Dictionary(records.map { ($0.source.name.lowercased(), $0) },
                   uniquingKeysWith: { a, _ in a })
    }()

    /// Set credits, from the document rather than hard-coded, so a data refresh
    /// that changes the model cannot silently disagree with our arithmetic.
    /// Falls back to the published 1.0 / 0.5 / 0.0 when the resource is absent.
    public static var setCredits: SetCredits {
        document?.setCredits ?? SetCredits(direct: 1, indirect: 0.5, stabilizer: 0)
    }
}
```

`SetCredits` needs a memberwise `init` for the fallback — add
`public init(direct: Double, indirect: Double, stabilizer: Double)` explicitly
(a `Decodable` struct in another module does not get a usable synthesized one
here because the properties are `let` with no defaults; declaring it is simpler
than relying on synthesis).

### Rewire `ImportedExerciseLibrary`

Keep the whole public surface (`templates`, and the `static` helpers the tests
already call). Changes:

1. Delete `RawEntry`; `template(from:)` takes `ExerciseDatabase.Record`.
2. `templates` becomes:
   ```swift
   public static let templates: [ExerciseTemplate] =
       ExerciseDatabase.records.compactMap(template(from:))
   ```
3. Inside `template(from:)`, read `record.source.*` exactly where `e.*` was read.
   **Do not** consume annotation/classification yet — that is Phase 3. This keeps
   the phase provably behaviour-neutral.
4. Leave `muscleMap` / `equipmentMap` / `category(primaryIDs:force:rawCategory:)`
   / `isLateral(_:)` untouched.

### Resource + script changes

- `git mv` is not usable (contents differ). Write
  `Resources/free-exercise-db-plusplus.json`, write
  `Resources/free-exercise-db-plusplus.LICENSE` (the DB++ Unlicense text, fetched
  from the repo), and **delete** `Resources/free-exercise-db.json` and
  `Resources/free-exercise-db.LICENSE`.
- `Package.swift`: replace the two `.copy` lines and update the comment to name
  DB++, its schema version, and that images still come from upstream `b0eed06`.
- `scripts/update-exercises.sh`: point `SOURCE_URL` at
  `https://raw.githubusercontent.com/johnarleyburns/free-exercise-db-plusplus/main/free-exercise-db-plusplus.json`,
  `TARGET` at the new file, and replace the "is it valid JSON" check with:
  ```python
  d = json.load(open(path))
  assert d["metadata"]["completeness"] == "full"
  assert d["metadata"]["outputExerciseCount"] == len(d["exercises"])
  assert set(d["metadata"]["muscleOntology"]) == EXPECTED_ONTOLOGY   # the 20 strings
  for e in d["exercises"].values():
      for k in ("direct", "indirect", "stabilizers"):
          assert set(e["annotation"][k]) <= set(d["metadata"]["muscleOntology"])
  ```
  Print the record count and `schemaVersion` on success; keep the "keep existing
  snapshot on failure" behaviour.
- `scripts/build-exercise-images.sh`: `DB_JSON` now points at the DB++ file and
  the image-path extraction reads `d["exercises"][id]["source"]["images"]`. The
  pinned `COMMIT=b0eed06` stays — DB++'s `source` is that same upstream data.
- `CadenceCore/CREDITS.md`: add a DB++ section above the free-exercise-db one
  (repo URL, Unlicense, schemaVersion/converterVersion/generatedAt of the pinned
  snapshot, what we use it for), and reword the free-exercise-db section to
  "reached through DB++'s `source` field; images pinned at `b0eed06`".

## Tests — `CadenceCore/Tests/CadenceCoreTests/ExerciseDatabaseTests.swift` (new)

| test | asserts |
|---|---|
| `testDocumentDecodes` | `ExerciseDatabase.document != nil`; `metadata.completeness == "full"` |
| `testRecordCount` | `records.count == 873` and `== metadata.outputExerciseCount` |
| `testRecordsAreSortedByID` | `records.map(\.exerciseId) == records.map(\.exerciseId).sorted()` |
| `testOntologyIsTheExpectedTwenty` | `Set(metadata.muscleOntology)` equals the literal 20-string set |
| `testEveryAnnotatedMuscleIsInOntology` | direct ∪ indirect ∪ stabilizers ⊆ ontology, for all records |
| `testVolumeEligibleImpliesNonEmptyDirect` | for every record, `volumeEligible == !direct.isEmpty` |
| `testSetCredits` | `1.0 / 0.5 / 0.0` |
| `testEveryEvidenceRefResolves` | every `pattern:<id>` in every record resolves in `metadata.evidence.patterns`, and every pattern's `references` resolve in `metadata.evidence.references` |
| `testEveryReferenceHasAUrl` | non-empty `url` on all 60 references |
| `testKnownFixtures` | the six spot-check rows from `00-overview.md` §1 |
| `testImageIdsMatchBundledDirectories` | for each record with non-empty `source.images`, `ExerciseImageCatalog.hasImages(forImageName: record.exerciseId)` is true |

## Tests — `ImportedExerciseLibraryTests.swift` (existing, extend)

Add `testTemplatesUnchangedByDatabaseSwap`: assert
`ImportedExerciseLibrary.templates.count`, and for a fixed sample of 20 ids
(spread alphabetically) assert name / category / equipment / force / mechanics /
primary / secondary / imageName / level match the values the current code
produces. Capture those expected values from the current build **before**
swapping the resource, and hard-code them in the test — that is what makes this a
regression gate rather than a tautology.

Existing tests in that file must pass **unmodified**.

## Verification

```
make ci
```
Expect: build clean, all existing tests plus the new ones green, guardrails OK.
`make smoke` is not required — no UI touched.

## Acceptance criteria

- [ ] `free-exercise-db.json` / `.LICENSE` are gone; DB++ JSON + LICENSE are
      committed and declared in `Package.swift`.
- [ ] `ExerciseDatabase` decodes the full document including metadata and
      evidence, and orders records deterministically by id.
- [ ] `ImportedExerciseLibrary.templates` is unchanged in count and content.
- [ ] `scripts/update-exercises.sh` validates the DB++ schema and refuses to
      install a snapshot that fails it.
- [ ] `scripts/build-exercise-images.sh` reads the new layout and remains a
      no-op against the already-bundled images.
- [ ] `CREDITS.md` names DB++ and its upstream.
- [ ] `make ci` green.

## Commit

`feat: vendor free-exercise-db++ snapshot and decoder`
