import XCTest
@testable import CadenceCore

/// `VolumeCredit` is the single place a working set becomes weekly volume, so a
/// screen and a nag can never disagree about how much a set counted for.
final class VolumeCreditTests: XCTestCase {

    func testWeightsComeFromTheVendoredDocument() {
        XCTAssertEqual(VolumeCredit.direct, 1.0)
        XCTAssertEqual(VolumeCredit.indirect, 0.5)
        XCTAssertEqual(VolumeCredit.stabilizer, 0.0)
        XCTAssertEqual(VolumeCredit.direct, ExerciseDatabase.setCredits.direct)
        XCTAssertEqual(VolumeCredit.indirect, ExerciseDatabase.setCredits.indirect)
    }

    /// The credit model is a science claim on screen, so it must cite.
    func testCitationResolves() {
        XCTAssertNotNil(CitationRegistry.citation(forId: VolumeCredit.citationID))
    }

    func testDirectAndIndirectWeights() {
        let credits = VolumeCredit.credits(direct: [.chest], indirect: [.triceps, .shoulders],
                                           volumeEligible: true)
        XCTAssertEqual(credits[.chest], 1.0)
        XCTAssertEqual(credits[.triceps], 0.5)
        XCTAssertEqual(credits[.shoulders], 0.5)
        XCTAssertNil(credits[.lats])
    }

    func testStabilizersAreSimplyAbsent() {
        // Stabilisers are never passed to `credits`; a group that only stabilises
        // therefore has no entry at all, which is the same as zero credit.
        let credits = VolumeCredit.credits(direct: [.glutes, .hamstrings],
                                           indirect: [.quadriceps], volumeEligible: true)
        XCTAssertNil(credits[.lowerBack])
        XCTAssertEqual(credits.values.reduce(0, +), 2.5)
    }

    func testNonVolumeEligibleContributesNothing() {
        let credits = VolumeCredit.credits(direct: [.chest, .lats],
                                           indirect: [.biceps], volumeEligible: false)
        XCTAssertTrue(credits.isEmpty)
    }

    func testDirectWinsWhenAGroupIsBothDirectAndIndirect() {
        let credits = VolumeCredit.credits(direct: [.chest], indirect: [.chest],
                                           volumeEligible: true)
        XCTAssertEqual(credits[.chest], 1.0)
        XCTAssertEqual(credits.count, 1, "a muscle is never counted twice for one set")
    }

    func testTemplateCredits() throws {
        let squat = try XCTUnwrap(ExerciseLibrary.starter.first { $0.name == "Back Squat" })
        XCTAssertEqual(VolumeCredit.credits(for: squat)[.quadriceps], 1.0)
        XCTAssertEqual(VolumeCredit.credits(for: squat)[.adductors], 0.5)
        XCTAssertNil(VolumeCredit.credits(for: squat)[.lowerBack])
    }

    func testExerciseCreditsFallBackToPrimarySecondaryAndCanonicalize() {
        let legacy = Exercise(name: "Legacy", isCustom: true,
                              primaryMuscles: ["quads"], secondaryMuscles: ["rear-delts"])
        XCTAssertEqual(VolumeCredit.credits(for: legacy)[.quadriceps], 1.0)
        XCTAssertEqual(VolumeCredit.credits(for: legacy)[.shoulders], 0.5)
    }

    func testExerciseRolesWinOverPrimarySecondaryWhenPresent() {
        let annotated = Exercise(name: "Annotated", isCustom: false,
                                 primaryMuscles: ["chest"], secondaryMuscles: ["triceps"],
                                 directMuscles: [.lats], indirectMuscles: [.biceps])
        XCTAssertEqual(annotated.setCredit(for: .lats), 1.0)
        XCTAssertEqual(annotated.setCredit(for: .biceps), 0.5)
        XCTAssertEqual(annotated.setCredit(for: .chest), 0.0)
    }

    /// Every seeded exercise credits only muscles it actually trains, and a
    /// non-eligible movement credits nothing at all.
    func testEveryStarterTemplateCreditsConsistently() {
        for template in ExerciseLibrary.starter {
            let credits = VolumeCredit.credits(for: template)
            if !template.volumeEligible {
                XCTAssertTrue(credits.isEmpty, "\(template.name) credits volume it should not")
                continue
            }
            XCTAssertFalse(credits.isEmpty, "\(template.name) is eligible but credits nothing")
            for (group, weight) in credits {
                XCTAssertTrue(weight == VolumeCredit.direct || weight == VolumeCredit.indirect,
                              "\(template.name) credits \(group) at \(weight)")
                XCTAssertFalse(template.stabilizerMuscles.contains(group),
                               "\(template.name) credits \(group), which only stabilises")
            }
        }
    }
}

/// The DB++ movement patterns replace name-keyword guessing where they exist.
final class MovementPatternAnnotationTests: XCTestCase {

    func testAnnotatedPatternWinsOverTheKeywordHeuristic() {
        // The name says nothing useful; the annotation does.
        let patterns = MovementPattern.patterns(
            forExerciseNamed: "Zercher Whatever", primaryMuscles: ["chest"],
            databasePatternIDs: ["conventional_deadlift"])
        XCTAssertEqual(patterns, [.hinge])
    }

    func testIsolationPatternsFallBackToTheHeuristic() {
        // `elbow_flexion` has no bucket in our coarse vocabulary, so the name and
        // muscle heuristic still decides.
        let patterns = MovementPattern.patterns(
            forExerciseNamed: "Barbell Curl", primaryMuscles: ["biceps"],
            databasePatternIDs: ["elbow_flexion"])
        XCTAssertFalse(patterns.isEmpty)
        XCTAssertNil(MovementPattern(databasePatternID: "elbow_flexion"))
        XCTAssertNil(MovementPattern(databasePatternID: "grip"))
        XCTAssertNil(MovementPattern(databasePatternID: "neck_flexion"))
    }

    func testMappedPatternsCoverTheMovementsWeProgramAround() {
        XCTAssertEqual(MovementPattern(databasePatternID: "squat"), .squat)
        XCTAssertEqual(MovementPattern(databasePatternID: "hip_hinge"), .hinge)
        XCTAssertEqual(MovementPattern(databasePatternID: "horizontal_press"), .horizontalPush)
        XCTAssertEqual(MovementPattern(databasePatternID: "horizontal_pull"), .horizontalPull)
        XCTAssertEqual(MovementPattern(databasePatternID: "vertical_press"), .verticalPush)
        XCTAssertEqual(MovementPattern(databasePatternID: "vertical_pull"), .verticalPull)
        XCTAssertEqual(MovementPattern(databasePatternID: "farmer_carry"), .carry)
        XCTAssertEqual(MovementPattern(databasePatternID: "trunk_flexion"), .core)
        XCTAssertEqual(MovementPattern(databasePatternID: "olympic_snatch"), .hinge)
        XCTAssertEqual(MovementPattern(databasePatternID: "olympic_jerk"), .verticalPush)
    }

    /// Every pattern id the shipped data actually uses is either mapped or a
    /// deliberate single-joint fall-through — never an unnoticed typo.
    func testEveryDatabasePatternIsAccountedFor() throws {
        let metadata = try XCTUnwrap(ExerciseDatabase.metadata)
        let used = Set(ExerciseDatabase.records.flatMap(\.annotation.patterns))
        XCTAssertFalse(used.isEmpty)
        for id in used {
            XCTAssertNotNil(metadata.evidence.patterns[id],
                            "pattern \(id) has no evidence entry")
        }
        let mapped = used.filter { MovementPattern(databasePatternID: $0) != nil }
        XCTAssertGreaterThan(mapped.count, 40,
                             "the mapping table has drifted away from the data")
    }
}
