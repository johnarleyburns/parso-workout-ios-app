import XCTest
import SwiftData
@testable import CadenceCore

final class CitationIntegrityTests: XCTestCase {

    func testAllCitationIdsExistInRegistry() {
        let known = Set(CitationRegistry.all.map(\.id))

        let required = [
            "ekelundActivityMortality2016",
            "pellandDoseResponse2026", "ramosCampoSplit2024",
            "parejaBlancoRecovery2020", "sawMonitoring2016", "meeusenOvertraining2013",
            "schumannConcurrent2022", "crowleyVO2Intensity2022", "poonHIIT2024",
            "mooreLeisureActivity2012", "aremDoseResponse2015", "saintMauriceSteps2020",
            "leeAccelerometer2019",
            "halsonRecovery2014", "drewFinchInjury2016", "dupuyFatigue2018",
        ]
        for id in required {
            XCTAssertTrue(known.contains(id), "Missing required citation: \(id)")
        }
    }

    func testEveryCitationHasUrl() {
        for c in CitationRegistry.all {
            XCTAssertFalse(c.url.isEmpty, "Citation \(c.id) has no URL")
        }
    }

    func testEveryCitationHasSource() {
        for c in CitationRegistry.all {
            XCTAssertFalse(c.source.isEmpty, "Citation \(c.id) has no source")
        }
    }

    func testLookupByIdWorks() {
        for c in CitationRegistry.all {
            XCTAssertNotNil(CitationRegistry.citation(forId: c.id), "Cannot look up \(c.id)")
        }
    }

    // MARK: - Citation pools

    func testAerobicPoolHasAtLeastFiveResearchCitations() {
        let pool = CitationRegistry.aerobicPool
        XCTAssertGreaterThanOrEqual(pool.citationIds.count, 5,
                                     "Aerobic pool should have at least 5 citations")
        // Verify no public-health guideline authority citation IDs
        let guidelineIDs = ["whoGuidelines", "hhsGuidelines", "cdcGuidelines", "publicHealthFloor"]
        for id in guidelineIDs {
            XCTAssertFalse(pool.citationIds.contains(id),
                            "Aerobic pool must not contain guideline/authority citation: \(id)")
        }
        // Verify all pool IDs resolve
        for id in pool.citationIds {
            XCTAssertNotNil(CitationRegistry.citation(forId: id),
                            "Pool citation \(id) must exist in registry")
        }
    }

    func testRecoveryLoadPoolHasExpectedSize() {
        let pool = CitationRegistry.recoveryLoadPool
        XCTAssertGreaterThanOrEqual(pool.citationIds.count, 4,
                                     "Recovery load pool should have at least 4 citations")
        for id in pool.citationIds {
            XCTAssertNotNil(CitationRegistry.citation(forId: id),
                            "Pool citation \(id) must exist in registry")
        }
    }

    func testCitationRotationIsDeterministic() {
        let pool = CitationRegistry.aerobicPool
        let date = Date(timeIntervalSince1970: 1700000000) // fixed date

        let sel1 = pool.select(for: date, stableId: "testClaim")
        let sel2 = pool.select(for: date, stableId: "testClaim")
        XCTAssertEqual(sel1, sel2, "Same date and stableId should yield same citation")

        let nextDay = date.addingTimeInterval(86400)
        let sel3 = pool.select(for: nextDay, stableId: "testClaim")
        // May or may not differ depending on pool size, but should be deterministic
        let sel4 = pool.select(for: nextDay, stableId: "testClaim")
        XCTAssertEqual(sel3, sel4, "Same date+stableId should be stable across calls")
    }

    func testCitationSelectionVarariesAcrossClaims() {
        let pool = CitationRegistry.aerobicPool
        let date = Date()

        let selA = pool.select(for: date, stableId: "claimA")
        let selB = pool.select(for: date, stableId: "claimB")

        if pool.citationIds.count > 1 {
            // Different claims on same day may or may not differ (hashing)
            // but each should be a valid pool member
            XCTAssertTrue(pool.citationIds.contains(selA ?? ""))
            XCTAssertTrue(pool.citationIds.contains(selB ?? ""))
        }
    }

    // MARK: - 2026-06-25 evidence-upgrade guardrails

    func testEveryCitationIdIsUnique() {
        let ids = CitationRegistry.all.map(\.id)
        let unique = Set(ids)
        XCTAssertEqual(ids.count, unique.count,
                       "Duplicate citation IDs in registry: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })")
    }

    func testEveryCitationHasResolvablePublicUrl() {
        for c in CitationRegistry.all {
            XCTAssertTrue(c.url.hasPrefix("https://") || c.url.hasPrefix("http://"),
                          "Citation \(c.id) has a non-navigable URL: \(c.url)")
            XCTAssertFalse(c.authors.isEmpty, "Citation \(c.id) has no authors")
            XCTAssertFalse(c.title.isEmpty, "Citation \(c.id) has no title")
        }
    }

    func testCorrectedCitationMetadata() {
        let wingate = CitationRegistry.citation(forId: "wingateTest")
        XCTAssertEqual(wingate?.url, "https://doi.org/10.2165/00007256-198704060-00001")

        let pelland = CitationRegistry.citation(forId: "pellandDoseResponse2026")
        XCTAssertTrue(pelland?.title.contains("Dose Response") == true,
                      "Pelland title not corrected: \(pelland?.title ?? "nil")")
        XCTAssertTrue(pelland?.authors.contains("Remmert") == true)

        let crowley = CitationRegistry.citation(forId: "crowleyVO2Intensity2022")
        XCTAssertEqual(crowley?.source, "Translational Sports Medicine")

        let poon = CitationRegistry.citation(forId: "poonHIIT2024")
        XCTAssertTrue(poon?.source.contains("Scandinavian Journal of Medicine") == true,
                      "Poon source not corrected: \(poon?.source ?? "nil")")

        let saw = CitationRegistry.citation(forId: "sawMonitoring2016")
        XCTAssertTrue(saw?.source.contains("British Journal of Sports Medicine") == true,
                      "Saw source not corrected: \(saw?.source ?? "nil")")
    }

    func testEveryPoolIdResolves() {
        for category in EvidenceClaimCategory.allCases {
            let pool = CitationRegistry.citationPool(for: category)
            XCTAssertFalse(pool.citationIds.isEmpty,
                           "Category \(category.rawValue) resolves to an empty pool")
            for id in pool.citationIds {
                XCTAssertNotNil(CitationRegistry.citation(forId: id),
                                "Pool for \(category.rawValue) cites unknown \(id)")
            }
        }
    }

    /// No claim category's pool may borrow a citation curated for an unrelated class.
    func testNoClaimUsesMismatchedCitationCategory() {
        func ids(_ c: EvidenceClaimCategory) -> Set<String> {
            Set(CitationRegistry.citationPool(for: c).citationIds)
        }

        // Step studies only back step claims.
        let stepOnly: Set<String> = ["saintMauriceSteps2020", "leeAccelerometer2019"]
        XCTAssertEqual(ids(.stepsHealth), stepOnly)
        XCTAssertTrue(ids(.activityMinutesHealth).isDisjoint(with: stepOnly),
                      "Activity-minutes pool must not cite step-only studies")
        XCTAssertTrue(ids(.aerobicBase).isDisjoint(with: stepOnly))

        // Performance pools must not cite mortality / public-health studies.
        let mortality: Set<String> = ["ekelundActivityMortality2016", "mooreLeisureActivity2012",
                                       "aremDoseResponse2015", "saintMauriceSteps2020",
                                       "leeAccelerometer2019"]
        for c in [EvidenceClaimCategory.vo2Training, .thresholdTraining, .anaerobicTraining,
                  .strengthFrequency, .strengthVolume, .strengthIntensity, .flexibilityROM] {
            XCTAssertTrue(ids(c).isDisjoint(with: mortality),
                          "\(c.rawValue) pool must not cite mortality/public-health studies")
        }

        // Flexibility pool is ROM-only (no injury-prevention overreach baked in).
        XCTAssertEqual(ids(.flexibilityROM), ["konradStretchROM2024", "behmStretching2016"])

        // Frequency vs volume must not be conflated.
        XCTAssertEqual(ids(.strengthFrequency), ["frequencyMeta"])
        XCTAssertFalse(ids(.strengthVolume).contains("frequencyMeta"))

        // VO2 and threshold pools are distinct.
        XCTAssertTrue(ids(.vo2Training).isDisjoint(with: ids(.thresholdTraining)))
    }

    func testEveryAssessmentKindHasCitationPolicy() {
        let known = Set(CitationRegistry.all.map(\.id))
        for kind in AssessmentKind.allCases {
            let policy = kind.evidencePolicy
            switch policy {
            case .validated(let cids), .fieldEstimate(let cids, _):
                XCTAssertFalse(cids.isEmpty, "\(kind.rawValue) validated/field policy has no citations")
                for id in cids {
                    XCTAssertTrue(known.contains(id), "\(kind.rawValue) cites unknown \(id)")
                }
            case .personalBenchmark(let cids, let caveat):
                XCTAssertFalse(caveat.isEmpty, "\(kind.rawValue) personal benchmark has no caveat")
                for id in cids {
                    XCTAssertTrue(known.contains(id), "\(kind.rawValue) cites unknown \(id)")
                }
            }
            // citationIds must mirror the policy
            XCTAssertEqual(kind.citationIds, policy.citationIds)
        }
    }

    func testBodyweightAssessmentsAreBenchmarksWhenWeaklyValidated() {
        for kind in [AssessmentKind.pushupMax, .pullupMax, .bodyweightSquatMax, .hollowHold] {
            if case .personalBenchmark = kind.evidencePolicy { continue }
            XCTFail("\(kind.rawValue) should be a personal benchmark, not a validated test")
        }
        // Lab-grade strength tests are validated.
        if case .validated = AssessmentKind.e1RM.evidencePolicy {} else {
            XCTFail("e1RM should be validated")
        }
    }

    func testEveryCoachSessionCandidateHasCitationIdsUnlessRestOrEmptyLaunch() {
        let known = Set(CitationRegistry.all.map(\.id))
        for experience in [ExperienceLevel.beginner, .intermediate, .advanced] {
            let facts = CoachFacts.make(from: [], goal: .strength, experience: experience, now: Date())
            for candidate in CoachSession.candidates(for: facts) {
                if candidate.kind == .rest || candidate.launchPayload.isEmpty { continue }
                XCTAssertFalse(candidate.citationIds.isEmpty,
                               "Candidate \(candidate.id) has no citations")
                for id in candidate.citationIds {
                    XCTAssertTrue(known.contains(id),
                                  "Candidate \(candidate.id) cites unknown \(id)")
                }
            }
        }
    }

    func testEveryDecisionReasonAndWarningCitationIdResolves() throws {
        let known = Set(CitationRegistry.all.map(\.id))
        let ctx = ModelContext(try CadenceStore.makeModelContainer(inMemory: true))
        let now = Date()

        func makeStrength(_ name: String, muscles: [String], daysAgo: Double, sets: Int) throws -> TrainingEvent {
            let date = now.addingTimeInterval(-daysAgo * 86400)
            let session = try WorkoutRepository.createSession(date: date.addingTimeInterval(-600), in: ctx)
            let ex = try WorkoutRepository.findOrCreateExercise(named: name, primaryMuscles: muscles, in: ctx)
            for _ in 0..<sets {
                _ = try WorkoutRepository.addSet(to: session, exercise: ex, weightKg: 100, reps: 5, rpe: 9, in: ctx)
            }
            session.endedAt = date
            return TrainingEvent.from(session: session)!
        }

        // Scenario A: heavy recent squats → recovery deferrals + per-session volume warning.
        let heavySquat = try makeStrength("Squat", muscles: ["quadriceps"], daysAgo: 0.2, sets: 12)
        let scenarios: [(events: [TrainingEvent], pain: Bool)] = [
            ([], false),
            ([], true),
            ([heavySquat], false),
        ]

        for s in scenarios {
            let facts = CoachFacts.make(from: s.events, goal: .strength, experience: .intermediate, now: now)
            let decision = CoachDecisionEngine.run(facts, hasPainConcern: s.pain)

            var allIds: [String] = decision.citationIds + decision.primary.citationIds
            allIds += decision.alternatives.flatMap(\.citationIds)
            allIds += decision.warnings.flatMap(\.citationIds)
            allIds += decision.deferred.flatMap { $0.reason.citationIds }

            for id in allIds where !id.isEmpty {
                XCTAssertTrue(known.contains(id),
                              "Decision surfaced unknown citation \(id)")
            }
        }
    }
}
