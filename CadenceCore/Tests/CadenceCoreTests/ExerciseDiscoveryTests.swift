import Testing
@testable import CadenceCore

/// Feedback batch 8 — exercise discovery: catalog integrity, the body-part index,
/// popular shortlist, gap-filling suggestions, and the EXRX reference link.
struct ExerciseDiscoveryTests {

    // Every built-in's muscle ids must resolve in MuscleCatalog (so search synonyms +
    // body-part mapping work), names are unique, and the plyometrics category landed.
    @Test func catalogIntegrity() {
        var seen = Set<String>()
        for t in ExerciseLibrary.starter {
            #expect(seen.insert(t.name.lowercased()).inserted, "duplicate exercise \(t.name)")
            for m in t.muscleGroups {
                #expect(MuscleGroup.canonical(m) != nil, "\(t.name) has unknown muscle id \(m)")
            }
        }
        #expect(ExerciseLibrary.starter.contains { $0.category == .plyometrics },
                      "plyometrics category should be populated")
        #expect(ExerciseLibrary.seedVersion >= 5, "seedVersion bumped for the expansion")
    }

    // The index reaches every group the coach programs toward, compound-first.
    // The remaining untracked specialised groups (neck, tibialis, rotator cuff,
    // hip flexors) are deliberately not
    // guaranteed coverage — decision D4 is that the catalog cannot fill them.
    @Test func byMuscleGroupIndexCoversTrackedGroups() {
        for part in MuscleGroup.canonicalOrder.filter(\.isTrackedByDefault) {
            let list = ExerciseLibrary.byMuscleGroup[part] ?? []
            #expect(!list.isEmpty, "no exercises indexed for \(part.displayName)")
            // Each listed exercise really trains that part.
            for t in list { #expect(ExerciseLibrary.muscleGroups(of: t).contains(part)) }
        }
    }

    // The curated popular shortlist all resolve to real built-ins.
    @Test func popularResolves() {
        #expect(ExerciseLibrary.popular.count == ExerciseLibrary.popularNames.count)
        #expect(ExerciseLibrary.popular.contains { $0.name == "Bench Press" })
    }

    // Suggestions cover all missing parts when the catalog can, fewest movements first.
    @Test func suggestionsCoverMissingParts() {
        let missing: [MuscleGroup] = [.lats, .quadriceps, .calves]
        let picks = ExerciseLibrary.suggestions(forMissing: missing, limit: 6)
        #expect(!picks.isEmpty)
        var covered = Set<MuscleGroup>()
        for t in picks { covered.formUnion(ExerciseLibrary.muscleGroups(of: t)) }
        #expect(Set(missing).isSubset(of: covered), "suggestions should cover all the missing parts")
        #expect(picks.count <= 6)
        #expect(picks.allSatisfy { $0.volumeEligible }, "gap filling must never recommend non-volume movements")
        #expect(!picks.contains { $0.name == "90/90 Hamstring" })
    }

    // Exclusions apply before the cover is computed, so the remaining picks still
    // cover every group the catalog can reach without the excluded movements.
    @Test func suggestionsStillCoverMissingAfterExcludingFirstPicks() {
        let missing: [MuscleGroup] = [.lats, .quadriceps, .calves, .biceps]
        let first = ExerciseLibrary.suggestions(forMissing: missing, limit: 6)
        let banned = Set(first.map(\.name))
        let picks = ExerciseLibrary.suggestions(forMissing: missing, limit: 6) { !banned.contains($0.name) }
        #expect(picks.allSatisfy { !banned.contains($0.name) })
        var covered = Set<MuscleGroup>()
        for t in picks { covered.formUnion(ExerciseLibrary.muscleGroups(of: t)) }
        #expect(Set(missing).isSubset(of: covered))
    }

    @Test func suggestionsEmptyWhenNothingMissing() {
        #expect(ExerciseLibrary.suggestions(forMissing: []).isEmpty)
    }

    @Test func progressivePRDoesNotMarkSameOrLowerSetAgain() {
        let samples = [SetSample(weight: 100, reps: 12),
                       SetSample(weight: 100, reps: 12),
                       SetSample(weight: 100, reps: 10),
                       SetSample(weight: 105, reps: 12)]
        let indices = PRCalculator.progressivePRIndices(samples, prior: [], rule: .topWeight,
                                                         formula: .epley)
        #expect(indices == Set([0, 3]))
    }
}
