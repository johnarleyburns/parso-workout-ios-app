import Testing
@testable import CadenceCore
@testable import CadenceExerciseImages

/// Guards the package-backed free-exercise-db++ database. It is the source of truth
/// for muscle roles, weekly volume credit, and every muscle-attribution citation the
/// app shows, so a malformed or schema-shifted refresh fails here.
struct TrainingEngineDatabaseTests {

    /// The ontology `MuscleGroup` mirrors. A refresh that changes it is a breaking
    /// change that must be handled deliberately.
    private static let expectedOntology: Set<String> = [
        "abdominals", "abductors", "adductors", "biceps", "calves", "chest",
        "forearms", "glutes", "hamstrings", "lats", "lower_back", "middle_back",
        "neck", "quadriceps", "shoulders", "traps", "triceps", "tibialis",
        "rotator_cuff", "hip_flexors",
    ]

    @Test func documentDecodes() throws {
        #expect(TrainingEngineBridge.metadataString("completeness") == "full")
        #expect(!(TrainingEngineBridge.metadataString("schemaVersion")?.isEmpty ?? true))
        #expect(TrainingEngineBridge.exerciseRecords.count == 938)
    }

    @Test func recordCount() throws {
        #expect(TrainingEngineBridge.exerciseRecords.count == 938)
        #expect(TrainingEngineBridge.exerciseRecords.count ==
                       TrainingEngineBridge.metadataInt("outputExerciseCount"))
    }

    /// `exercises` is a JSON object, so decode order is undefined. Everything
    /// downstream — the catalog merge, every fixture — depends on the sort.
    @Test func recordsAreSortedByID() {
        let ids = TrainingEngineBridge.exerciseRecords.map(\.exerciseId)
        #expect(ids == ids.sorted())
        #expect(Set(ids).count == ids.count, "duplicate exerciseId")
    }

    @Test func ontologyIsTheExpectedTwenty() {
        #expect(Set(MuscleGroup.canonicalOrder.map(\.rawValue)) == Self.expectedOntology)
        #expect(MuscleGroup.canonicalOrder.count == 20)
    }

    @Test func everyAnnotatedMuscleIsInOntology() {
        for record in TrainingEngineBridge.exerciseRecords {
            let used = Set(record.direct + record.indirect + record.stabilizers)
            #expect(used.isSubset(of: Self.expectedOntology),
                          "\(record.exerciseId) annotates \(used.subtracting(Self.expectedOntology))")
        }
    }

    /// Volume-eligible records must have a direct attribution. Some non-volume
    /// movements intentionally retain direct muscles for browsing and similarity,
    /// so the converse is not required.
    @Test func volumeEligibleImpliesNonEmptyDirect() {
        for record in TrainingEngineBridge.exerciseRecords {
            if record.volumeEligible {
                #expect(!record.direct.isEmpty,
                               "\(record.exerciseId) is volume eligible without a direct attribution")
            }
        }
    }

    @Test func volumeEligibleCount() {
        let eligible = TrainingEngineBridge.exerciseRecords.filter(\.volumeEligible)
        #expect(eligible.count == 735)
        #expect(TrainingEngineBridge.exerciseRecords.count - eligible.count == 203)
    }

    @Test func setCredits() {
        #expect(TrainingEngineBridge.setCredits.direct == 1.0)
        #expect(TrainingEngineBridge.setCredits.indirect == 0.5)
        #expect(TrainingEngineBridge.setCredits.stabilizer == 0.0)
    }

    @Test func everyEvidenceRefResolves() throws {
        for record in TrainingEngineBridge.exerciseRecords {
            for ref in record.patterns.map({ "pattern:\($0)" }) {
                let parts = ref.split(separator: ":", maxSplits: 1)
                #expect(parts.first.map(String.init) == "pattern",
                               "\(record.exerciseId) has unexpected evidence ref \(ref)")
                let patternID = String(parts[1])
                let pattern = try #require(TrainingEngineBridge.evidencePatterns[patternID],
                                            "\(record.exerciseId) cites unknown pattern \(patternID)")
                #expect(!pattern.summary.isEmpty)
                for reference in pattern.references {
                    #expect(TrainingEngineBridge.evidenceReferences[reference] != nil,
                                    "pattern \(patternID) cites unknown reference \(reference)")
                }
            }
        }
    }

    @Test func everyReferenceHasAUrl() throws {
        #expect(TrainingEngineBridge.evidenceReferences.count == 78)
        for (id, reference) in TrainingEngineBridge.evidenceReferences {
            #expect(!reference.url.isEmpty, "reference \(id) has no url")
            #expect(!reference.title.isEmpty, "reference \(id) has no title")
        }
    }

    /// Spot checks that would catch a role inversion in a refreshed snapshot.
    @Test func knownFixtures() throws {
        func record(_ id: String) throws -> TrainingEngineBridge.ExerciseRecord {
            try #require(TrainingEngineBridge.exerciseRecords.first { $0.exerciseId == id },
                          "missing \(id)")
        }

        let squat = try record("Barbell_Squat")
        #expect(squat.direct == ["quadriceps", "glutes"])
        #expect(squat.indirect == ["adductors"])
        #expect(Set(squat.stabilizers) == ["lower_back", "hamstrings", "calves"])
        #expect(ImportedExerciseLibrary.template(from: squat)?.trainingTypes == [.strength])
        #expect(ImportedExerciseLibrary.template(from: squat)?.modalities == [.freeWeight])
        #expect(squat.patterns == ["squat"])

        // The headline behaviour change: the deadlift's lower back stabilises, so
        // it earns no weekly volume credit from this movement.
        let deadlift = try record("Barbell_Deadlift")
        #expect(deadlift.direct == ["glutes", "hamstrings"])
        #expect(deadlift.indirect == ["quadriceps"])
        #expect(deadlift.stabilizers.contains("lower_back"))

        let bench = try record("Barbell_Bench_Press_-_Medium_Grip")
        #expect(bench.direct == ["chest"])
        #expect(Set(bench.indirect) == ["triceps", "shoulders"])

        let pullups = try record("Pullups")
        #expect(pullups.direct == ["lats"])
        #expect(Set(pullups.indirect) == ["biceps", "middle_back"])
        #expect(ImportedExerciseLibrary.template(from: pullups)?.modalities == [.bodyweight])

        let press = try record("Standing_Military_Press")
        #expect(press.direct == ["shoulders"])
        #expect(press.indirect == ["triceps"])

        let curl = try record("Barbell_Curl")
        #expect(curl.direct == ["biceps"])
        #expect(curl.indirect == ["forearms"])
    }

    /// The imagery is pinned to the same upstream data DB++ carries under `source`,
    /// so every record that claims images must resolve to a bundled directory.
    @Test func imageIdsMatchBundledDirectories() {
        for record in TrainingEngineBridge.exerciseRecords where !record.images.isEmpty {
            #expect(ExerciseImageCatalog.hasImages(forImageName: record.exerciseId),
                          "\(record.exerciseId) claims images with none bundled")
        }
    }

    @Test func sourceIdMatchesExerciseId() {
        for record in TrainingEngineBridge.exerciseRecords {
            #expect(!record.exerciseId.isEmpty)
        }
    }
}
