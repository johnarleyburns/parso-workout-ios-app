import Foundation
import Testing
@testable import CadenceCore

struct MuscleGroupTests {

    /// The whole point of the type: it mirrors the DB++ ontology exactly, so a
    /// data refresh that adds or renames a muscle fails here instead of silently
    /// producing an unreachable dimension.
    @Test func rawValuesMatchDatabaseOntology() {
        #expect(Set(MuscleGroup.allCases.map(\.rawValue)) ==
                       Set(MuscleGroup.canonicalOrder.map(\.rawValue)))
        #expect(MuscleGroup.allCases.count == 20)
    }

    @Test func allCasesHaveDistinctDisplayNames() {
        let names = MuscleGroup.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(!name.isEmpty)
            #expect(String(name.prefix(1)) == String(name.prefix(1)).uppercased())
            #expect(!name.contains("_"), "\(name) leaks a raw value")
        }
    }

    @Test func everyCaseHasScientificNameAndSynonyms() {
        for group in MuscleGroup.allCases {
            #expect(!group.scientificName.isEmpty, "\(group) has no scientific name")
            #expect(!group.synonyms.isEmpty, "\(group) has no synonyms")
        }
    }

    @Test func searchTermsAreLowercasedAndUnique() {
        for group in MuscleGroup.allCases {
            let terms = group.searchTerms
            #expect(Set(terms).count == terms.count, "\(group) repeats a search term")
            for term in terms {
                #expect(term == term.lowercased(), "\(group) has an uppercased term \(term)")
            }
            #expect(terms.contains(group.displayName.lowercased()))
        }
    }

    /// Every id the old `MuscleCatalog` could have written into a stored exercise
    /// must still resolve, or a user's logged history silently stops counting.
    @Test func retiredMuscleIdsCanonicalize() {
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
            #expect(MuscleGroup.canonical(legacy) == group, "\(legacy) did not canonicalize")
        }
    }

    @Test func upstreamSpellingsCanonicalize() {
        #expect(MuscleGroup.canonical("lower back") == .lowerBack)
        #expect(MuscleGroup.canonical("middle back") == .middleBack)
        #expect(MuscleGroup.canonical("Middle Back") == .middleBack)
        #expect(MuscleGroup.canonical("  LATS  ") == .lats)
        #expect(MuscleGroup.canonical("rotator cuff") == .rotatorCuff)
        #expect(MuscleGroup.canonical("hip flexors") == .hipFlexors)
    }

    /// The pre-DB++ import folded upstream `neck` into traps. DB++ has a real neck
    /// group, and that mis-mapping must not survive.
    @Test func neckIsItsOwnGroup() {
        #expect(MuscleGroup.canonical("neck") == .neck)
    }

    @Test func unknownReturnsNil() {
        #expect(MuscleGroup.canonical("") == nil)
        #expect(MuscleGroup.canonical("   ") == nil)
        #expect(MuscleGroup.canonical("unicorn") == nil)
        #expect(MuscleGroup.canonical("pecs deck") == nil)
    }

    @Test func canonicalizePreservesOrderAndDeduplicates() {
        #expect(MuscleGroup.canonicalize(["quads", "abs", "quadriceps"]) ==
                       [.quadriceps, .abdominals])
        #expect(MuscleGroup.canonicalize(["front-delts", "rear-delts", "delts"]) ==
                       [.shoulders])
        #expect(MuscleGroup.canonicalize(["unicorn", "lats"]) == [.lats])
        #expect(MuscleGroup.canonicalize([]) == [])
    }

    @Test func descendingMassOrderCoversEveryCase() {
        #expect(Set(MuscleGroup.descendingMassOrder) == Set(MuscleGroup.allCases))
        #expect(MuscleGroup.descendingMassOrder.count == MuscleGroup.allCases.count)
        let priorities = MuscleGroup.descendingMassOrder.map(MuscleGroup.massPriority(for:))
        #expect(priorities == Array(0..<MuscleGroup.allCases.count))
    }

    @Test func defaultTrackedMatchesDBPlusPlusPlanningGroups() {
        #expect(MuscleGroup.defaultTracked == [
            .abdominals, .abductors, .adductors, .biceps, .calves, .chest, .forearms,
            .glutes, .hamstrings, .lats, .lowerBack, .middleBack, .quadriceps,
            .shoulders, .traps, .triceps, .hipFlexors, .tibialis, .neck, .rotatorCuff
        ])
        #expect(MuscleGroup.defaultTracked.count == 20)
    }

    /// The test that would have caught `tibialis`: a group the coach targets must
    /// have at least one volume-eligible movement that trains it directly, or its
    /// weekly deficit can never be closed.
    @Test func defaultTrackedGroupsAllHaveDirectExercises() {
        var directCounts: [MuscleGroup: Int] = [:]
        for record in TrainingEngineBridge.exerciseRecords where record.volumeEligible {
            for group in MuscleGroup.canonicalize(record.direct) {
                directCounts[group, default: 0] += 1
            }
        }
        for group in MuscleGroup.defaultTracked {
            #expect((directCounts[group] ?? 0) > 0,
                                 "\(group) is tracked but no movement trains it directly")
        }
        #expect(MuscleGroup.defaultTracked.contains(.tibialis))
    }

    @Test func canonicalOrderIsAPermutationWithTrackedFirst() {
        #expect(Set(MuscleGroup.canonicalOrder) == Set(MuscleGroup.allCases))
        #expect(MuscleGroup.canonicalOrder.count == MuscleGroup.allCases.count)
        let trackedPrefix = MuscleGroup.canonicalOrder.prefix(MuscleGroup.defaultTracked.count)
        #expect(Set(trackedPrefix) == MuscleGroup.defaultTracked)
    }

    @Test func regionIsGroupingOnlyAndCoversEveryCase() {
        // Every group has a region, and no region is used as a volume dimension —
        // several groups deliberately share one.
        var byRegion: [BodyRegion: [MuscleGroup]] = [:]
        for group in MuscleGroup.allCases { byRegion[group.region, default: []].append(group) }
        #expect(byRegion[.back]?.count == 5)
        #expect(byRegion[.legs]?.count == 7)
        #expect(byRegion[.chest] == [.chest])
        #expect(byRegion[.fullBody] == nil)
    }

    @Test func defaultsForCategory() {
        #expect(MuscleGroup.defaults(forCategory: .push) == [.chest, .shoulders, .triceps])
        #expect(MuscleGroup.defaults(forCategory: .pull) == [.lats, .biceps])
        #expect(MuscleGroup.defaults(forCategory: .legs) == [.quadriceps, .hamstrings, .glutes])
        #expect(MuscleGroup.defaults(forCategory: .core) == [.abdominals])
        #expect(MuscleGroup.defaults(forCategory: .cardio) == [])
    }

    @Test func codableRoundTripsRawValues() throws {
        let data = try JSONEncoder().encode([MuscleGroup.lowerBack, .middleBack, .hipFlexors])
        #expect(String(data: data, encoding: .utf8) ==
                       #"["lower_back","middle_back","hip_flexors"]"#)
        #expect(try JSONDecoder().decode([MuscleGroup].self, from: data) ==
                       [.lowerBack, .middleBack, .hipFlexors])
    }
}
