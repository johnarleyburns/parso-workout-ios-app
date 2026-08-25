import XCTest
@testable import CadenceCore

/// Strength-pivot P2 — the public-domain (free-exercise-db, Unlicense) import:
/// the transform maps their coarse taxonomy onto ours, every imported entry is
/// catalog-valid, and the merge into `starter` adds the long tail without
/// disturbing the curated facets.
final class ImportedExerciseLibraryTests: XCTestCase {

    // The bundled resource decodes and transforms into a sizeable catalog.
    func testImportedLoadsAndIsLarge() {
        let imported = ImportedExerciseLibrary.templates
        XCTAssertGreaterThan(imported.count, 500,
                             "free-exercise-db should yield hundreds of movements")
    }

    // Every imported entry has ≥1 known MuscleCatalog id, a real category, and any
    // facets it carries are valid — the integrity guarantee the transform promises.
    func testEveryImportedEntryIsValid() {
        for t in ImportedExerciseLibrary.templates {
            XCTAssertFalse(t.primaryMuscles.isEmpty, "\(t.name) has no primary muscle")
            for m in t.muscleGroups {
                XCTAssertNotNil(MuscleGroup.canonical(m), "\(t.name) → unknown muscle id \(m)")
            }
            // Primary and secondary never overlap.
            XCTAssertTrue(Set(t.primaryMuscles).isDisjoint(with: Set(t.secondaryMuscles)),
                          "\(t.name) repeats a muscle across primary/secondary")
        }
    }

    // Mapping spot-checks: their strings → our ids/enums.
    func testMappingTables() {
        // The hand-written muscle table is gone — MuscleGroup canonicalizes upstream
        // spellings directly, which is also what ends `neck` being folded into traps.
        XCTAssertEqual(MuscleGroup.canonicalize(["middle back", "lower back", "quadriceps"]),
                       [.middleBack, .lowerBack, .quadriceps])
        XCTAssertEqual(ImportedExerciseLibrary.equipmentMap["e-z curl bar"], .barbell)
        XCTAssertEqual(ImportedExerciseLibrary.equipmentMap["body only"], .bodyweight)
        XCTAssertNil(ImportedExerciseLibrary.equipmentMap["foam roll"], "unmapped equipment stays nil")
    }

    // Category derivation: cardio/plyo carry over; strength splits by region + force.
    func testCategoryDerivation() {
        XCTAssertEqual(ImportedExerciseLibrary.category(primaryGroups: [.chest], force: .push, rawCategory: "strength"), .push)
        XCTAssertEqual(ImportedExerciseLibrary.category(primaryGroups: [.lats], force: .pull, rawCategory: "strength"), .pull)
        XCTAssertEqual(ImportedExerciseLibrary.category(primaryGroups: [.quadriceps], force: .push, rawCategory: "strength"), .legs)
        XCTAssertEqual(ImportedExerciseLibrary.category(primaryGroups: [.abdominals], force: nil, rawCategory: "strength"), .core)
        XCTAssertEqual(ImportedExerciseLibrary.category(primaryGroups: [.quadriceps], force: nil, rawCategory: "cardio"), .cardio)
        XCTAssertEqual(ImportedExerciseLibrary.category(primaryGroups: [.glutes], force: nil, rawCategory: "plyometrics"), .plyometrics)
        // No-force back movement falls back to pull by region.
        XCTAssertEqual(ImportedExerciseLibrary.category(primaryGroups: [.lats], force: nil, rawCategory: "strength"), .pull)
    }

    // The merge keeps every curated entry (curated wins on a name collision) and adds
    // imported movements not already covered by name.
    func testMergePrefersCuratedAndAddsTail() {
        let curatedNames = Set(ExerciseLibrary.curated.map { $0.name.lowercased() })
        let starterNames = Set(ExerciseLibrary.starter.map { $0.name.lowercased() })
        XCTAssertTrue(curatedNames.isSubset(of: starterNames), "every curated movement survives the merge")
        XCTAssertGreaterThan(ExerciseLibrary.starter.count, ExerciseLibrary.curated.count,
                             "imported tail should grow the catalog")
        // Curated facets win: "Bench Press" keeps its curated push/barbell facets.
        let bench = ExerciseLibrary.starter.first { $0.name == "Bench Press" }
        XCTAssertEqual(bench?.equipment, .barbell)
    }

    // Some imported entries carry the new public-domain facets (instructions + image).
    func testImportedCarriesInstructionsAndImage() {
        let withSteps = ImportedExerciseLibrary.templates.filter { !$0.instructions.isEmpty }
        XCTAssertGreaterThan(withSteps.count, 400, "most entries ship instructions")
        let withImage = ImportedExerciseLibrary.templates.filter { $0.imageName != nil }
        XCTAssertGreaterThan(withImage.count, 400, "most entries reference an image")
    }
}
