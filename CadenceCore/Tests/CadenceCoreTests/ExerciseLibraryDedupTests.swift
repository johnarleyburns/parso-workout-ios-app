import Testing
@testable import CadenceCore

/// Locks in that the seeded catalog has no "same movement, different spelling"
/// duplicates (feedback: "Handstand Push-Up" empty stub alongside the full
/// "Handstand Push-Ups"), and that the survivor keeps the full instructions/image.
struct ExerciseLibraryDedupTests {

    @Test func dedupKeyFoldsPluralAndPunctuation() {
        #expect(ExerciseLibrary.dedupKey("Handstand Push-Up") ==
                       ExerciseLibrary.dedupKey("Handstand Push-Ups"))
        #expect(ExerciseLibrary.dedupKey("Muscle-Up") ==
                       ExerciseLibrary.dedupKey("Muscle Up"))
        #expect(ExerciseLibrary.dedupKey("Bench Dip") ==
                       ExerciseLibrary.dedupKey("Bench Dips"))
        // Genuinely different movements must NOT collide.
        #expect(ExerciseLibrary.dedupKey("Bench Press") !=
                          ExerciseLibrary.dedupKey("Overhead Press"))
        #expect(ExerciseLibrary.dedupKey("Front Squat") !=
                          ExerciseLibrary.dedupKey("Back Squat"))
    }

    @Test func starterCatalogHasNoDuplicateVariants() {
        var groups: [String: [String]] = [:]
        for t in ExerciseLibrary.starter {
            groups[ExerciseLibrary.dedupKey(t.name), default: []].append(t.name)
        }
        let dups = groups.filter { $0.value.count > 1 }
        #expect(dups.isEmpty,
                      "catalog still has spelling-variant duplicates: \(dups.values.map { $0.joined(separator: " / ") })")
    }

    @Test func starterCatalogNamesAreUnique() {
        let names = ExerciseLibrary.starter.map { $0.name.lowercased() }
        #expect(names.count == Set(names).count, "exact-name duplicates in the catalog")
    }

    @Test func handstandPushUpIsSingleEntryWithFullDetail() {
        let matches = ExerciseLibrary.starter.filter {
            ExerciseLibrary.dedupKey($0.name) == ExerciseLibrary.dedupKey("Handstand Push-Up")
        }
        #expect(matches.count == 1, "exactly one handstand push-up entry")
        let entry = matches.first!
        #expect(!entry.instructions.isEmpty, "the surviving entry keeps instructions")
        #expect(entry.imageName != nil, "the surviving entry keeps its demo image")
    }

    /// A curated stub that was previously left empty because its imported twin had a
    /// slightly different name must now be enriched by the collapse pass.
    @Test func knownStubEntriesGainInstructions() {
        for name in ["Bench Dip", "Concentration Curl", "Mountain Climber", "Ring Dip"] {
            let matches = ExerciseLibrary.starter.filter {
                ExerciseLibrary.dedupKey($0.name) == ExerciseLibrary.dedupKey(name)
            }
            #expect(matches.count == 1, "\(name): one entry")
            #expect(!matches.first!.instructions.isEmpty,
                           "\(name): should be enriched from its imported twin")
        }
    }

    @Test func noZombieExercisesMissingImageAndInstructions() {
        let zombies = ExerciseLibrary.starter.filter {
            $0.imageName == nil && $0.instructions.isEmpty
        }.map(\.name).sorted()
        #expect(zombies.isEmpty,
                      "Exercises missing BOTH image and instructions (zombies to purge):\n\(zombies.joined(separator: "\n"))")
    }

    @Test func collapseVariantsKeepsFirstAndEnriches() {
        var a = ExerciseTemplate("Foo Curl", .pull, .dumbbell, .pull, .isolation, primary: ["biceps"])
        a.instructions = []
        a.imageName = nil
        var b = ExerciseTemplate("Foo Curls", .pull, .dumbbell, .pull, .isolation, primary: ["biceps"])
        b.instructions = ["step one", "step two"]
        b.imageName = "Foo_Curls"
        let out = ExerciseLibrary.collapseVariants([a, b])
        #expect(out.count == 1)
        #expect(out.first?.name == "Foo Curl", "first (curated) name survives")
        #expect(out.first?.instructions == ["step one", "step two"], "enriched from the twin")
        #expect(out.first?.imageName == "Foo_Curls")
    }
}
