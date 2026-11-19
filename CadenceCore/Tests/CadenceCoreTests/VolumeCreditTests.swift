import Testing
@testable import CadenceCore

/// `VolumeCredit` is the single place a working set becomes weekly volume, so a
/// screen and a nag can never disagree about how much a set counted for.
struct VolumeCreditTests {

    @Test func weightsComeFromTheVendoredDocument() {
        #expect(VolumeCredit.direct == 1.0)
        #expect(VolumeCredit.indirect == 0.5)
        #expect(VolumeCredit.stabilizer == 0.0)
        #expect(VolumeCredit.direct == TrainingEngineBridge.setCredits.direct)
        #expect(VolumeCredit.indirect == TrainingEngineBridge.setCredits.indirect)
    }

    /// The credit model is a science claim on screen, so it must cite.
    @Test func citationResolves() {
        #expect(CitationRegistry.citation(forId: VolumeCredit.citationID) != nil)
    }

    @Test func directAndIndirectWeights() {
        let credits = VolumeCredit.credits(direct: [.chest], indirect: [.triceps, .shoulders],
                                           volumeEligible: true)
        #expect(credits[.chest] == 1.0)
        #expect(credits[.triceps] == 0.5)
        #expect(credits[.shoulders] == 0.5)
        #expect(credits[.lats] == nil)
    }

    @Test func stabilizersAreSimplyAbsent() {
        // Stabilisers are never passed to `credits`; a group that only stabilises
        // therefore has no entry at all, which is the same as zero credit.
        let credits = VolumeCredit.credits(direct: [.glutes, .hamstrings],
                                           indirect: [.quadriceps], volumeEligible: true)
        #expect(credits[.lowerBack] == nil)
        #expect(credits.values.reduce(0, +) == 2.5)
    }

    @Test func nonVolumeEligibleContributesNothing() {
        let credits = VolumeCredit.credits(direct: [.chest, .lats],
                                           indirect: [.biceps], volumeEligible: false)
        #expect(credits.isEmpty)
    }

    @Test func directWinsWhenAGroupIsBothDirectAndIndirect() {
        let credits = VolumeCredit.credits(direct: [.chest], indirect: [.chest],
                                           volumeEligible: true)
        #expect(credits[.chest] == 1.0)
        #expect(credits.count == 1, "a muscle is never counted twice for one set")
    }

    @Test func templateCredits() throws {
        let squat = try #require(ExerciseLibrary.starter.first { $0.name == "Back Squat" })
        #expect(VolumeCredit.credits(for: squat)[.quadriceps] == 1.0)
        #expect(VolumeCredit.credits(for: squat)[.adductors] == 0.5)
        #expect(VolumeCredit.credits(for: squat)[.lowerBack] == nil)
    }

    @Test func exerciseCreditsFallBackToPrimarySecondaryAndCanonicalize() {
        let legacy = Exercise(name: "Legacy", isCustom: true,
                              primaryMuscles: ["quads"], secondaryMuscles: ["rear-delts"])
        #expect(VolumeCredit.credits(for: legacy)[.quadriceps] == 1.0)
        #expect(VolumeCredit.credits(for: legacy)[.shoulders] == 0.5)
    }

    @Test func exerciseRolesWinOverPrimarySecondaryWhenPresent() {
        let annotated = Exercise(name: "Annotated", isCustom: false,
                                 primaryMuscles: ["chest"], secondaryMuscles: ["triceps"],
                                 directMuscles: [.lats], indirectMuscles: [.biceps])
        #expect(annotated.setCredit(for: .lats) == 1.0)
        #expect(annotated.setCredit(for: .biceps) == 0.5)
        #expect(annotated.setCredit(for: .chest) == 0.0)
    }

    /// Every seeded exercise credits only muscles it actually trains, and a
    /// non-eligible movement credits nothing at all.
    @Test func everyStarterTemplateCreditsConsistently() {
        for template in ExerciseLibrary.starter {
            let credits = VolumeCredit.credits(for: template)
            if !template.volumeEligible {
                #expect(credits.isEmpty, "\(template.name) credits volume it should not")
                continue
            }
            #expect(!credits.isEmpty, "\(template.name) is eligible but credits nothing")
            for (group, weight) in credits {
                #expect(weight == VolumeCredit.direct || weight == VolumeCredit.indirect,
                              "\(template.name) credits \(group) at \(weight)")
                #expect(!template.stabilizerMuscles.contains(group),
                               "\(template.name) credits \(group), which only stabilises")
            }
        }
    }
}

/// The DB++ movement patterns replace name-keyword guessing where they exist.
struct MovementPatternAnnotationTests {

    @Test func annotatedPatternWinsOverTheKeywordHeuristic() {
        // The name says nothing useful; the annotation does.
        let patterns = MovementPattern.patterns(
            forExerciseNamed: "Zercher Whatever", primaryMuscles: ["chest"],
            databasePatternIDs: ["conventional_deadlift"])
        #expect(patterns == [.hinge])
    }

    @Test func isolationPatternsFallBackToTheHeuristic() {
        // `elbow_flexion` has no bucket in our coarse vocabulary, so the name and
        // muscle heuristic still decides.
        let patterns = MovementPattern.patterns(
            forExerciseNamed: "Barbell Curl", primaryMuscles: ["biceps"],
            databasePatternIDs: ["elbow_flexion"])
        #expect(!patterns.isEmpty)
        #expect(MovementPattern(databasePatternID: "elbow_flexion") == nil)
        #expect(MovementPattern(databasePatternID: "grip") == nil)
        #expect(MovementPattern(databasePatternID: "neck_flexion") == nil)
    }

    @Test func mappedPatternsCoverTheMovementsWeProgramAround() {
        #expect(MovementPattern(databasePatternID: "squat") == .squat)
        #expect(MovementPattern(databasePatternID: "hip_hinge") == .hinge)
        #expect(MovementPattern(databasePatternID: "horizontal_press") == .horizontalPush)
        #expect(MovementPattern(databasePatternID: "horizontal_pull") == .horizontalPull)
        #expect(MovementPattern(databasePatternID: "vertical_press") == .verticalPush)
        #expect(MovementPattern(databasePatternID: "vertical_pull") == .verticalPull)
        #expect(MovementPattern(databasePatternID: "farmer_carry") == .carry)
        #expect(MovementPattern(databasePatternID: "trunk_flexion") == .core)
        #expect(MovementPattern(databasePatternID: "olympic_snatch") == .hinge)
        #expect(MovementPattern(databasePatternID: "olympic_jerk") == .verticalPush)
    }

    /// Every pattern id the shipped data actually uses is either mapped or a
    /// deliberate single-joint fall-through — never an unnoticed typo.
    @Test func everyDatabasePatternIsAccountedFor() throws {
        let used = Set(TrainingEngineBridge.exerciseRecords.flatMap(\.patterns))
        #expect(!used.isEmpty)
        for id in used {
            #expect(TrainingEngineBridge.evidencePatterns[id] != nil,
                            "pattern \(id) has no evidence entry")
        }
        let mapped = used.filter { MovementPattern(databasePatternID: $0) != nil }
        #expect(mapped.count > 40,
                             "the mapping table has drifted away from the data")
    }
}
