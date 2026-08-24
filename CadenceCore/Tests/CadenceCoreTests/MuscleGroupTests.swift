import XCTest
@testable import CadenceCore

final class MuscleGroupTests: XCTestCase {

    /// The whole point of the type: it mirrors the vendored ontology exactly, so a
    /// data refresh that adds or renames a muscle fails here instead of silently
    /// producing an unreachable dimension.
    func testRawValuesMatchDatabaseOntology() {
        XCTAssertEqual(Set(MuscleGroup.allCases.map(\.rawValue)),
                       Set(ExerciseDatabase.muscleOntology))
        XCTAssertEqual(MuscleGroup.allCases.count, 20)
    }

    func testAllCasesHaveDistinctDisplayNames() {
        let names = MuscleGroup.allCases.map(\.displayName)
        XCTAssertEqual(Set(names).count, names.count)
        for name in names {
            XCTAssertFalse(name.isEmpty)
            XCTAssertEqual(String(name.prefix(1)), String(name.prefix(1)).uppercased())
            XCTAssertFalse(name.contains("_"), "\(name) leaks a raw value")
        }
    }

    func testEveryCaseHasScientificNameAndSynonyms() {
        for group in MuscleGroup.allCases {
            XCTAssertFalse(group.scientificName.isEmpty, "\(group) has no scientific name")
            XCTAssertFalse(group.synonyms.isEmpty, "\(group) has no synonyms")
        }
    }

    func testSearchTermsAreLowercasedAndUnique() {
        for group in MuscleGroup.allCases {
            let terms = group.searchTerms
            XCTAssertEqual(Set(terms).count, terms.count, "\(group) repeats a search term")
            for term in terms {
                XCTAssertEqual(term, term.lowercased(), "\(group) has an uppercased term \(term)")
            }
            XCTAssertTrue(terms.contains(group.displayName.lowercased()))
        }
    }

    /// Every id the old `MuscleCatalog` could have written into a stored exercise
    /// must still resolve, or a user's logged history silently stops counting.
    func testRetiredMuscleIdsCanonicalize() {
        let expected: [String: MuscleGroup] = [
            "abs": .abdominals,
            "obliques": .abdominals,
            "quads": .quadriceps,
            "delts": .shoulders,
            "front-delts": .shoulders,
            "rear-delts": .shoulders,
            "rhomboids": .middleBack,
            "lower-back": .lowerBack,
            "upper-chest": .chest,
            "hip-flexors": .hipFlexors,
            "chest": .chest,
            "lats": .lats,
            "traps": .traps,
            "biceps": .biceps,
            "triceps": .triceps,
            "forearms": .forearms,
            "hamstrings": .hamstrings,
            "glutes": .glutes,
            "calves": .calves,
            "adductors": .adductors,
            "abductors": .abductors,
        ]
        for (legacy, group) in expected {
            XCTAssertEqual(MuscleGroup.canonical(legacy), group, "\(legacy) did not canonicalize")
        }
    }

    func testUpstreamSpellingsCanonicalize() {
        XCTAssertEqual(MuscleGroup.canonical("lower back"), .lowerBack)
        XCTAssertEqual(MuscleGroup.canonical("middle back"), .middleBack)
        XCTAssertEqual(MuscleGroup.canonical("Middle Back"), .middleBack)
        XCTAssertEqual(MuscleGroup.canonical("  LATS  "), .lats)
        XCTAssertEqual(MuscleGroup.canonical("rotator cuff"), .rotatorCuff)
        XCTAssertEqual(MuscleGroup.canonical("hip flexors"), .hipFlexors)
    }

    /// The pre-DB++ import folded upstream `neck` into traps. DB++ has a real neck
    /// group, and that mis-mapping must not survive.
    func testNeckIsItsOwnGroup() {
        XCTAssertEqual(MuscleGroup.canonical("neck"), .neck)
    }

    func testUnknownReturnsNil() {
        XCTAssertNil(MuscleGroup.canonical(""))
        XCTAssertNil(MuscleGroup.canonical("   "))
        XCTAssertNil(MuscleGroup.canonical("unicorn"))
        XCTAssertNil(MuscleGroup.canonical("pecs deck"))
    }

    func testCanonicalizePreservesOrderAndDeduplicates() {
        XCTAssertEqual(MuscleGroup.canonicalize(["quads", "abs", "quadriceps"]),
                       [.quadriceps, .abdominals])
        XCTAssertEqual(MuscleGroup.canonicalize(["front-delts", "rear-delts", "delts"]),
                       [.shoulders])
        XCTAssertEqual(MuscleGroup.canonicalize(["unicorn", "lats"]), [.lats])
        XCTAssertEqual(MuscleGroup.canonicalize([]), [])
    }

    func testDescendingMassOrderCoversEveryCase() {
        XCTAssertEqual(Set(MuscleGroup.descendingMassOrder), Set(MuscleGroup.allCases))
        XCTAssertEqual(MuscleGroup.descendingMassOrder.count, MuscleGroup.allCases.count)
        let priorities = MuscleGroup.descendingMassOrder.map(MuscleGroup.massPriority(for:))
        XCTAssertEqual(priorities, Array(0..<MuscleGroup.allCases.count))
    }

    func testDefaultTrackedIsTheThirteen() {
        XCTAssertEqual(MuscleGroup.defaultTracked, [
            .abdominals, .biceps, .calves, .chest, .forearms, .glutes, .hamstrings,
            .lats, .middleBack, .quadriceps, .shoulders, .traps, .triceps
        ])
        XCTAssertEqual(MuscleGroup.defaultTracked.count, 13)
    }

    /// The test that would have caught `tibialis`: a group the coach targets must
    /// have at least one volume-eligible movement that trains it directly, or its
    /// weekly deficit can never be closed.
    func testDefaultTrackedGroupsAllHaveDirectExercises() {
        var directCounts: [MuscleGroup: Int] = [:]
        for record in ExerciseDatabase.records where record.annotation.volumeEligible {
            for group in MuscleGroup.canonicalize(record.annotation.direct) {
                directCounts[group, default: 0] += 1
            }
        }
        for group in MuscleGroup.defaultTracked {
            XCTAssertGreaterThan(directCounts[group] ?? 0, 0,
                                 "\(group) is tracked but no movement trains it directly")
        }
        XCTAssertEqual(directCounts[.tibialis] ?? 0, 0,
                       "tibialis gained a direct movement — reconsider defaultTracked")
        XCTAssertFalse(MuscleGroup.defaultTracked.contains(.tibialis))
    }

    func testCanonicalOrderIsAPermutationWithTrackedFirst() {
        XCTAssertEqual(Set(MuscleGroup.canonicalOrder), Set(MuscleGroup.allCases))
        XCTAssertEqual(MuscleGroup.canonicalOrder.count, MuscleGroup.allCases.count)
        let trackedPrefix = MuscleGroup.canonicalOrder.prefix(MuscleGroup.defaultTracked.count)
        XCTAssertEqual(Set(trackedPrefix), MuscleGroup.defaultTracked)
    }

    func testRegionIsGroupingOnlyAndCoversEveryCase() {
        // Every group has a region, and no region is used as a volume dimension —
        // several groups deliberately share one.
        var byRegion: [BodyRegion: [MuscleGroup]] = [:]
        for group in MuscleGroup.allCases { byRegion[group.region, default: []].append(group) }
        XCTAssertEqual(byRegion[.back]?.count, 5)
        XCTAssertEqual(byRegion[.legs]?.count, 7)
        XCTAssertEqual(byRegion[.chest], [.chest])
        XCTAssertNil(byRegion[.fullBody])
    }

    func testDefaultsForCategory() {
        XCTAssertEqual(MuscleGroup.defaults(forCategory: .push), [.chest, .shoulders, .triceps])
        XCTAssertEqual(MuscleGroup.defaults(forCategory: .pull), [.lats, .biceps])
        XCTAssertEqual(MuscleGroup.defaults(forCategory: .legs), [.quadriceps, .hamstrings, .glutes])
        XCTAssertEqual(MuscleGroup.defaults(forCategory: .core), [.abdominals])
        XCTAssertEqual(MuscleGroup.defaults(forCategory: .cardio), [])
    }

    func testCodableRoundTripsRawValues() throws {
        let data = try JSONEncoder().encode([MuscleGroup.lowerBack, .middleBack, .hipFlexors])
        XCTAssertEqual(String(data: data, encoding: .utf8),
                       #"["lower_back","middle_back","hip_flexors"]"#)
        XCTAssertEqual(try JSONDecoder().decode([MuscleGroup].self, from: data),
                       [.lowerBack, .middleBack, .hipFlexors])
    }
}
