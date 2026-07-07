import XCTest
@testable import CadenceCore

/// Locks in that the seeded catalog has no "same movement, different spelling"
/// duplicates (feedback: "Handstand Push-Up" empty stub alongside the full
/// "Handstand Push-Ups"), and that the survivor keeps the full instructions/image.
final class ExerciseLibraryDedupTests: XCTestCase {

    func testDedupKeyFoldsPluralAndPunctuation() {
        XCTAssertEqual(ExerciseLibrary.dedupKey("Handstand Push-Up"),
                       ExerciseLibrary.dedupKey("Handstand Push-Ups"))
        XCTAssertEqual(ExerciseLibrary.dedupKey("Muscle-Up"),
                       ExerciseLibrary.dedupKey("Muscle Up"))
        XCTAssertEqual(ExerciseLibrary.dedupKey("Bench Dip"),
                       ExerciseLibrary.dedupKey("Bench Dips"))
        // Genuinely different movements must NOT collide.
        XCTAssertNotEqual(ExerciseLibrary.dedupKey("Bench Press"),
                          ExerciseLibrary.dedupKey("Overhead Press"))
        XCTAssertNotEqual(ExerciseLibrary.dedupKey("Front Squat"),
                          ExerciseLibrary.dedupKey("Back Squat"))
    }

    func testStarterCatalogHasNoDuplicateVariants() {
        var groups: [String: [String]] = [:]
        for t in ExerciseLibrary.starter {
            groups[ExerciseLibrary.dedupKey(t.name), default: []].append(t.name)
        }
        let dups = groups.filter { $0.value.count > 1 }
        XCTAssertTrue(dups.isEmpty,
                      "catalog still has spelling-variant duplicates: \(dups.values.map { $0.joined(separator: " / ") })")
    }

    func testStarterCatalogNamesAreUnique() {
        let names = ExerciseLibrary.starter.map { $0.name.lowercased() }
        XCTAssertEqual(names.count, Set(names).count, "exact-name duplicates in the catalog")
    }

    func testHandstandPushUpIsSingleEntryWithFullDetail() {
        let matches = ExerciseLibrary.starter.filter {
            ExerciseLibrary.dedupKey($0.name) == ExerciseLibrary.dedupKey("Handstand Push-Up")
        }
        XCTAssertEqual(matches.count, 1, "exactly one handstand push-up entry")
        let entry = matches.first!
        XCTAssertFalse(entry.instructions.isEmpty, "the surviving entry keeps instructions")
        XCTAssertNotNil(entry.imageName, "the surviving entry keeps its demo image")
    }

    /// A curated stub that was previously left empty because its imported twin had a
    /// slightly different name must now be enriched by the collapse pass.
    func testKnownStubEntriesGainInstructions() {
        for name in ["Bench Dip", "Concentration Curl", "Mountain Climber", "Ring Dip"] {
            let matches = ExerciseLibrary.starter.filter {
                ExerciseLibrary.dedupKey($0.name) == ExerciseLibrary.dedupKey(name)
            }
            XCTAssertEqual(matches.count, 1, "\(name): one entry")
            XCTAssertFalse(matches.first!.instructions.isEmpty,
                           "\(name): should be enriched from its imported twin")
        }
    }

    func testNoZombieExercisesMissingImageAndInstructions() {
        let zombies = ExerciseLibrary.starter.filter {
            $0.imageName == nil && $0.instructions.isEmpty
        }.map(\.name).sorted()
        XCTAssertTrue(zombies.isEmpty,
                      "Exercises missing BOTH image and instructions (zombies to purge):\n\(zombies.joined(separator: "\n"))")
    }

    func testCollapseVariantsKeepsFirstAndEnriches() {
        var a = ExerciseTemplate("Foo Curl", .pull, .dumbbell, .pull, .isolation, primary: ["biceps"])
        a.instructions = []
        a.imageName = nil
        var b = ExerciseTemplate("Foo Curls", .pull, .dumbbell, .pull, .isolation, primary: ["biceps"])
        b.instructions = ["step one", "step two"]
        b.imageName = "Foo_Curls"
        let out = ExerciseLibrary.collapseVariants([a, b])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.name, "Foo Curl", "first (curated) name survives")
        XCTAssertEqual(out.first?.instructions, ["step one", "step two"], "enriched from the twin")
        XCTAssertEqual(out.first?.imageName, "Foo_Curls")
    }
}
