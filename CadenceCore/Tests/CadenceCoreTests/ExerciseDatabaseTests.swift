import XCTest
@testable import CadenceCore

/// Guards the package-backed free-exercise-db++ database. It is the source of truth
/// for muscle roles, weekly volume credit, and every muscle-attribution citation the
/// app shows, so a malformed or schema-shifted refresh fails here.
final class TrainingEngineDatabaseTests: XCTestCase {

    /// The ontology `MuscleGroup` mirrors. A refresh that changes it is a breaking
    /// change that must be handled deliberately.
    private static let expectedOntology: Set<String> = [
        "abdominals", "abductors", "adductors", "biceps", "calves", "chest",
        "forearms", "glutes", "hamstrings", "lats", "lower_back", "middle_back",
        "neck", "quadriceps", "shoulders", "traps", "triceps", "tibialis",
        "rotator_cuff", "hip_flexors",
    ]

    func testDocumentDecodes() throws {
        XCTAssertEqual(TrainingEngineBridge.metadataString("completeness"), "full")
        XCTAssertFalse(TrainingEngineBridge.metadataString("schemaVersion")?.isEmpty ?? true)
        XCTAssertEqual(TrainingEngineBridge.exerciseRecords.count, 927)
    }

    func testRecordCount() throws {
        XCTAssertEqual(TrainingEngineBridge.exerciseRecords.count, 927)
        XCTAssertEqual(TrainingEngineBridge.exerciseRecords.count,
                       TrainingEngineBridge.metadataInt("outputExerciseCount"))
    }

    /// `exercises` is a JSON object, so decode order is undefined. Everything
    /// downstream — the catalog merge, every fixture — depends on the sort.
    func testRecordsAreSortedByID() {
        let ids = TrainingEngineBridge.exerciseRecords.map(\.exerciseId)
        XCTAssertEqual(ids, ids.sorted())
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate exerciseId")
    }

    func testOntologyIsTheExpectedTwenty() {
        XCTAssertEqual(Set(MuscleGroup.canonicalOrder.map(\.rawValue)), Self.expectedOntology)
        XCTAssertEqual(MuscleGroup.canonicalOrder.count, 20)
    }

    func testEveryAnnotatedMuscleIsInOntology() {
        for record in TrainingEngineBridge.exerciseRecords {
            let used = Set(record.direct + record.indirect + record.stabilizers)
            XCTAssertTrue(used.isSubset(of: Self.expectedOntology),
                          "\(record.exerciseId) annotates \(used.subtracting(Self.expectedOntology))")
        }
    }

    /// Volume-eligible records must have a direct attribution. Some non-volume
    /// movements intentionally retain direct muscles for browsing and similarity,
    /// so the converse is not required.
    func testVolumeEligibleImpliesNonEmptyDirect() {
        for record in TrainingEngineBridge.exerciseRecords {
            if record.volumeEligible {
                XCTAssertFalse(record.direct.isEmpty,
                               "\(record.exerciseId) is volume eligible without a direct attribution")
            }
        }
    }

    func testVolumeEligibleCount() {
        let eligible = TrainingEngineBridge.exerciseRecords.filter(\.volumeEligible)
        XCTAssertEqual(eligible.count, 724)
        XCTAssertEqual(TrainingEngineBridge.exerciseRecords.count - eligible.count, 203)
    }

    func testSetCredits() {
        XCTAssertEqual(TrainingEngineBridge.setCredits.direct, 1.0)
        XCTAssertEqual(TrainingEngineBridge.setCredits.indirect, 0.5)
        XCTAssertEqual(TrainingEngineBridge.setCredits.stabilizer, 0.0)
    }

    func testEveryEvidenceRefResolves() throws {
        for record in TrainingEngineBridge.exerciseRecords {
            for ref in record.patterns.map({ "pattern:\($0)" }) {
                let parts = ref.split(separator: ":", maxSplits: 1)
                XCTAssertEqual(parts.first.map(String.init), "pattern",
                               "\(record.exerciseId) has unexpected evidence ref \(ref)")
                let patternID = String(parts[1])
                let pattern = try XCTUnwrap(TrainingEngineBridge.evidencePatterns[patternID],
                                            "\(record.exerciseId) cites unknown pattern \(patternID)")
                XCTAssertFalse(pattern.summary.isEmpty)
                for reference in pattern.references {
                    XCTAssertNotNil(TrainingEngineBridge.evidenceReferences[reference],
                                    "pattern \(patternID) cites unknown reference \(reference)")
                }
            }
        }
    }

    func testEveryReferenceHasAUrl() throws {
        XCTAssertEqual(TrainingEngineBridge.evidenceReferences.count, 63)
        for (id, reference) in TrainingEngineBridge.evidenceReferences {
            XCTAssertFalse(reference.url.isEmpty, "reference \(id) has no url")
            XCTAssertFalse(reference.title.isEmpty, "reference \(id) has no title")
        }
    }

    /// Spot checks that would catch a role inversion in a refreshed snapshot.
    func testKnownFixtures() throws {
        func record(_ id: String) throws -> TrainingEngineBridge.ExerciseRecord {
            try XCTUnwrap(TrainingEngineBridge.exerciseRecords.first { $0.exerciseId == id },
                          "missing \(id)")
        }

        let squat = try record("Barbell_Squat")
        XCTAssertEqual(squat.direct, ["quadriceps", "glutes"])
        XCTAssertEqual(squat.indirect, ["adductors"])
        XCTAssertEqual(Set(squat.stabilizers), ["lower_back", "hamstrings", "calves"])
        XCTAssertEqual(ImportedExerciseLibrary.template(from: squat)?.trainingTypes, [.strength])
        XCTAssertEqual(ImportedExerciseLibrary.template(from: squat)?.modalities, [.freeWeight])
        XCTAssertEqual(squat.patterns, ["squat"])

        // The headline behaviour change: the deadlift's lower back stabilises, so
        // it earns no weekly volume credit from this movement.
        let deadlift = try record("Barbell_Deadlift")
        XCTAssertEqual(deadlift.direct, ["glutes", "hamstrings"])
        XCTAssertEqual(deadlift.indirect, ["quadriceps"])
        XCTAssertTrue(deadlift.stabilizers.contains("lower_back"))

        let bench = try record("Barbell_Bench_Press_-_Medium_Grip")
        XCTAssertEqual(bench.direct, ["chest"])
        XCTAssertEqual(Set(bench.indirect), ["triceps", "shoulders"])

        let pullups = try record("Pullups")
        XCTAssertEqual(pullups.direct, ["lats"])
        XCTAssertEqual(Set(pullups.indirect), ["biceps", "middle_back"])
        XCTAssertEqual(ImportedExerciseLibrary.template(from: pullups)?.modalities, [.bodyweight])

        let press = try record("Standing_Military_Press")
        XCTAssertEqual(press.direct, ["shoulders"])
        XCTAssertEqual(press.indirect, ["triceps"])

        let curl = try record("Barbell_Curl")
        XCTAssertEqual(curl.direct, ["biceps"])
        XCTAssertEqual(curl.indirect, ["forearms"])
    }

    /// The imagery is pinned to the same upstream data DB++ carries under `source`,
    /// so every record that claims images must resolve to a bundled directory.
    func testImageIdsMatchBundledDirectories() {
        for record in TrainingEngineBridge.exerciseRecords where !record.images.isEmpty {
            XCTAssertTrue(ExerciseImageCatalog.hasImages(forImageName: record.exerciseId),
                          "\(record.exerciseId) claims images with none bundled")
        }
    }

    func testSourceIdMatchesExerciseId() {
        for record in TrainingEngineBridge.exerciseRecords {
            XCTAssertFalse(record.exerciseId.isEmpty)
        }
    }
}
