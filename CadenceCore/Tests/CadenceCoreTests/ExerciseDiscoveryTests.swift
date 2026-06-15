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
                XCTAssertNotNil(MuscleCatalog.muscle(m), "\(t.name) has unknown muscle id \(m)")
            }
        }
        XCTAssertTrue(ExerciseLibrary.starter.contains { $0.category == .plyometrics },
                      "plyometrics category should be populated")
        XCTAssertGreaterThanOrEqual(ExerciseLibrary.seedVersion, 5, "seedVersion bumped for the expansion")
    }

    // The index reaches every body part, and entries are compound-first.
    func testByBodyPartIndexCoversAllParts() {
        for part in BodyPart.allCases {
            let list = ExerciseLibrary.byBodyPart[part] ?? []
            XCTAssertFalse(list.isEmpty, "no exercises indexed for \(part.displayName)")
            // Each listed exercise really trains that part.
            for t in list { XCTAssertTrue(ExerciseLibrary.bodyParts(of: t).contains(part)) }
        }
    }

    // The curated popular shortlist all resolve to real built-ins.
    func testPopularResolves() {
        XCTAssertEqual(ExerciseLibrary.popular.count, ExerciseLibrary.popularNames.count)
        XCTAssertTrue(ExerciseLibrary.popular.contains { $0.name == "Bench Press" })
    }

    // Suggestions cover all missing parts when the catalog can, fewest movements first.
    func testSuggestionsCoverMissingParts() {
        let missing: [BodyPart] = [.back, .legs, .calves]
        let picks = ExerciseLibrary.suggestions(forMissing: missing, limit: 6)
        XCTAssertFalse(picks.isEmpty)
        var covered = Set<BodyPart>()
        for t in picks { covered.formUnion(ExerciseLibrary.bodyParts(of: t)) }
        XCTAssertTrue(Set(missing).isSubset(of: covered), "suggestions should cover all the missing parts")
        XCTAssertLessThanOrEqual(picks.count, 6)
    }

    func testSuggestionsEmptyWhenNothingMissing() {
        XCTAssertTrue(ExerciseLibrary.suggestions(forMissing: []).isEmpty)
    }

    // EXRX link is an external site-scoped search (copyright-respecting), encoded.
    func testExrxReferenceURL() {
        let url = ExerciseLibrary.exrxReferenceURL(forName: "Bench Press")
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("exrx.net"))
        XCTAssertFalse(url!.absoluteString.contains(" "), "URL must be percent-encoded")
    }
}
