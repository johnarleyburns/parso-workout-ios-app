import XCTest
@testable import CadenceCore

/// Guards the vendored free-exercise-db++ snapshot. The document is the source of
/// truth for muscle roles, weekly volume credit, and every muscle-attribution
/// citation the app shows, so a malformed or schema-shifted refresh must fail here
/// rather than degrade the coach silently.
final class ExerciseDatabaseTests: XCTestCase {

    /// The ontology `MuscleGroup` mirrors. A refresh that changes it is a breaking
    /// change that must be handled deliberately.
    private static let expectedOntology: Set<String> = [
        "abdominals", "abductors", "adductors", "biceps", "calves", "chest",
        "forearms", "glutes", "hamstrings", "lats", "lower_back", "middle_back",
        "neck", "quadriceps", "shoulders", "traps", "triceps", "tibialis",
        "rotator_cuff", "hip_flexors",
    ]

    func testDocumentDecodes() throws {
        let document = try XCTUnwrap(ExerciseDatabase.document)
        XCTAssertEqual(document.metadata.completeness, "full")
        XCTAssertFalse(document.metadata.schemaVersion.isEmpty)
        XCTAssertEqual(document.metadata.upstream.project, "yuhonas/free-exercise-db")
    }

    func testRecordCount() throws {
        let metadata = try XCTUnwrap(ExerciseDatabase.metadata)
        XCTAssertEqual(ExerciseDatabase.records.count, 873)
        XCTAssertEqual(ExerciseDatabase.records.count, metadata.outputExerciseCount)
    }

    /// `exercises` is a JSON object, so decode order is undefined. Everything
    /// downstream — the catalog merge, every fixture — depends on the sort.
    func testRecordsAreSortedByID() {
        let ids = ExerciseDatabase.records.map(\.exerciseId)
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate exerciseId")
    }

    func testOntologyIsTheExpectedTwenty() {
        XCTAssertEqual(Set(ExerciseDatabase.muscleOntology), Self.expectedOntology)
        XCTAssertEqual(ExerciseDatabase.muscleOntology.count, 20)
    }

    func testEveryAnnotatedMuscleIsInOntology() {
        for record in ExerciseDatabase.records {
            let annotation = record.annotation
            let used = Set(annotation.direct + annotation.indirect + annotation.stabilizers)
            XCTAssertTrue(used.isSubset(of: Self.expectedOntology),
                          "\(record.exerciseId) annotates \(used.subtracting(Self.expectedOntology))")
        }
    }

    /// Volume eligibility and a non-empty direct list are the same fact. This is
    /// what lets `volumeEligible` gate weekly credit on its own.
    func testVolumeEligibleImpliesNonEmptyDirect() {
        for record in ExerciseDatabase.records {
            XCTAssertEqual(record.annotation.volumeEligible, !record.annotation.direct.isEmpty,
                           "\(record.exerciseId) disagrees about volume eligibility")
        }
    }

    func testVolumeEligibleCount() {
        let eligible = ExerciseDatabase.records.filter(\.annotation.volumeEligible)
        XCTAssertEqual(eligible.count, 673)
        XCTAssertEqual(ExerciseDatabase.records.count - eligible.count, 200)
    }

    func testSetCredits() {
        XCTAssertEqual(ExerciseDatabase.setCredits.direct, 1.0)
        XCTAssertEqual(ExerciseDatabase.setCredits.indirect, 0.5)
        XCTAssertEqual(ExerciseDatabase.setCredits.stabilizer, 0.0)
    }

    func testEveryEvidenceRefResolves() throws {
        let evidence = try XCTUnwrap(ExerciseDatabase.metadata).evidence
        for record in ExerciseDatabase.records {
            for ref in record.annotation.evidenceRefs {
                let parts = ref.split(separator: ":", maxSplits: 1)
                XCTAssertEqual(parts.first.map(String.init), "pattern",
                               "\(record.exerciseId) has unexpected evidence ref \(ref)")
                let patternID = String(parts[1])
                let pattern = try XCTUnwrap(evidence.patterns[patternID],
                                            "\(record.exerciseId) cites unknown pattern \(patternID)")
                XCTAssertFalse(pattern.summary.isEmpty)
                for reference in pattern.references {
                    XCTAssertNotNil(evidence.references[reference],
                                    "pattern \(patternID) cites unknown reference \(reference)")
                }
            }
        }
    }

    func testEveryReferenceHasAUrl() throws {
        let evidence = try XCTUnwrap(ExerciseDatabase.metadata).evidence
        XCTAssertEqual(evidence.references.count, 60)
        for (id, reference) in evidence.references {
            XCTAssertFalse(reference.url.isEmpty, "reference \(id) has no url")
            XCTAssertFalse(reference.title.isEmpty, "reference \(id) has no title")
        }
    }

    /// Spot checks that would catch a role inversion in a refreshed snapshot.
    func testKnownFixtures() throws {
        func record(_ id: String) throws -> ExerciseDatabase.Record {
            try XCTUnwrap(ExerciseDatabase.recordsByID[id], "missing \(id)")
        }

        let squat = try record("Barbell_Squat")
        XCTAssertEqual(squat.annotation.direct, ["quadriceps", "glutes"])
        XCTAssertEqual(squat.annotation.indirect, ["adductors"])
        XCTAssertEqual(Set(squat.annotation.stabilizers), ["lower_back", "hamstrings", "calves"])
        XCTAssertEqual(squat.classification.trainingTypes, ["strength"])
        XCTAssertEqual(squat.classification.modalities, ["free_weight"])
        XCTAssertEqual(squat.annotation.patterns, ["squat"])

        // The headline behaviour change: the deadlift's lower back stabilises, so
        // it earns no weekly volume credit from this movement.
        let deadlift = try record("Barbell_Deadlift")
        XCTAssertEqual(deadlift.annotation.direct, ["glutes", "hamstrings"])
        XCTAssertEqual(deadlift.annotation.indirect, ["quadriceps"])
        XCTAssertTrue(deadlift.annotation.stabilizers.contains("lower_back"))

        let bench = try record("Barbell_Bench_Press_-_Medium_Grip")
        XCTAssertEqual(bench.annotation.direct, ["chest"])
        XCTAssertEqual(Set(bench.annotation.indirect), ["triceps", "shoulders"])

        let pullups = try record("Pullups")
        XCTAssertEqual(pullups.annotation.direct, ["lats"])
        XCTAssertEqual(Set(pullups.annotation.indirect), ["biceps", "middle_back"])
        XCTAssertEqual(pullups.classification.modalities, ["bodyweight"])

        let press = try record("Standing_Military_Press")
        XCTAssertEqual(press.annotation.direct, ["shoulders"])
        XCTAssertEqual(press.annotation.indirect, ["triceps"])

        let curl = try record("Barbell_Curl")
        XCTAssertEqual(curl.annotation.direct, ["biceps"])
        XCTAssertEqual(curl.annotation.indirect, ["forearms"])
    }

    /// The imagery is pinned to the same upstream data DB++ carries under `source`,
    /// so every record that claims images must resolve to a bundled directory.
    func testImageIdsMatchBundledDirectories() {
        for record in ExerciseDatabase.records where !record.source.images.isEmpty {
            XCTAssertTrue(ExerciseImageCatalog.hasImages(forImageName: record.exerciseId),
                          "\(record.exerciseId) claims images with none bundled")
        }
    }

    func testSourceIdMatchesExerciseId() {
        for record in ExerciseDatabase.records {
            XCTAssertEqual(record.source.id, record.exerciseId)
        }
    }
}
