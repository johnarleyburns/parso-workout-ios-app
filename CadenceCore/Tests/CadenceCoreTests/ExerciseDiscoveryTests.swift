import XCTest
@testable import CadenceCore

/// Feedback batch 8 — exercise discovery: catalog integrity, the body-part index,
/// popular shortlist, gap-filling suggestions, and the EXRX reference link.
final class ExerciseDiscoveryTests: XCTestCase {

    // Every built-in's muscle ids must resolve in MuscleCatalog (so search synonyms +
    // body-part mapping work), names are unique, and the plyometrics category landed.
    func testCatalogIntegrity() {
        var seen = Set<String>()
        for t in ExerciseLibrary.starter {
            XCTAssertTrue(seen.insert(t.name.lowercased()).inserted, "duplicate exercise \(t.name)")
            for m in t.muscleGroups {
                XCTAssertNotNil(MuscleGroup.canonical(m), "\(t.name) has unknown muscle id \(m)")
            }
        }
        XCTAssertTrue(ExerciseLibrary.starter.contains { $0.category == .plyometrics },
                      "plyometrics category should be populated")
        XCTAssertGreaterThanOrEqual(ExerciseLibrary.seedVersion, 5, "seedVersion bumped for the expansion")
    }

    // The index reaches every group the coach programs toward, compound-first.
    // The untracked seven (neck, tibialis, rotator cuff, …) are deliberately not
    // guaranteed coverage — decision D4 is that the catalog cannot fill them.
    func testByMuscleGroupIndexCoversTrackedGroups() {
        for part in MuscleGroup.canonicalOrder.filter(\.isTrackedByDefault) {
            let list = ExerciseLibrary.byMuscleGroup[part] ?? []
            XCTAssertFalse(list.isEmpty, "no exercises indexed for \(part.displayName)")
            // Each listed exercise really trains that part.
            for t in list { XCTAssertTrue(ExerciseLibrary.muscleGroups(of: t).contains(part)) }
        }
    }

    // The curated popular shortlist all resolve to real built-ins.
    func testPopularResolves() {
        XCTAssertEqual(ExerciseLibrary.popular.count, ExerciseLibrary.popularNames.count)
        XCTAssertTrue(ExerciseLibrary.popular.contains { $0.name == "Bench Press" })
    }

    // Suggestions cover all missing parts when the catalog can, fewest movements first.
    func testSuggestionsCoverMissingParts() {
        let missing: [MuscleGroup] = [.lats, .quadriceps, .calves]
        let picks = ExerciseLibrary.suggestions(forMissing: missing, limit: 6)
        XCTAssertFalse(picks.isEmpty)
        var covered = Set<MuscleGroup>()
        for t in picks { covered.formUnion(ExerciseLibrary.muscleGroups(of: t)) }
        XCTAssertTrue(Set(missing).isSubset(of: covered), "suggestions should cover all the missing parts")
        XCTAssertLessThanOrEqual(picks.count, 6)
    }

    func testSuggestionsEmptyWhenNothingMissing() {
        XCTAssertTrue(ExerciseLibrary.suggestions(forMissing: []).isEmpty)
    }
}
