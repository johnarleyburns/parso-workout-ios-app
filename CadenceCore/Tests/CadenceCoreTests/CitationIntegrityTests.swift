#if canImport(SwiftData)
import Foundation
import Testing
import SwiftData
@testable import CadenceCore

struct CitationIntegrityTests {

    @Test func allCitationIdsExistInRegistry() {
        let known = Set(CitationRegistry.all.map(\.id))

        let required = [
            "ekelundActivityMortality2016",
            "iversenTimeEfficient2021", "pellandDoseResponse2026",
            "acsmResistanceTraining2002", "acsmResistanceTraining2026",
            "ramosCampoSplit2024",
            "parejaBlancoRecovery2020", "sawMonitoring2016", "meeusenOvertraining2013",
            "schumannConcurrent2022", "crowleyVO2Intensity2022", "poonHIIT2024",
            "mooreLeisureActivity2012", "aremDoseResponse2015", "saintMauriceSteps2020",
            "leeAccelerometer2019",
            "halsonRecovery2014", "drewFinchInjury2016", "dupuyFatigue2018",
            // Passive readiness (revenue Phase 4, D4) — a science claim with any of
            // these missing must fail CI (HARD RULE, mechanically enforced).
            "javaloyesHRVGuided2019", "vesterinenHRVGuided2016",
            "buchheitMonitoring2014", "cravenSleep2022",
        ]
        for id in required {
            #expect(known.contains(id), "Missing required citation: \(id)")
        }
    }

    @Test func catalogReferencesResolveWithReasonsOutsideCoachingPools() {
        let citations = ExerciseCatalogEvidence.citations
        #expect(citations.count == 15)
        #expect(Set(citations.map(\.id)).count == citations.count)
        #expect(Set(citations.map(\.id)) == Set(ExerciseCatalogEvidence.usageReasons.keys))
        for citation in citations {
            #expect(CitationRegistry.citation(forId: citation.id) == citation)
            let databaseID = "exdb." + String(citation.id.dropFirst("catalog.".count))
            #expect(CitationRegistry.citation(forId: databaseID)?.url == citation.url)
            #expect(CitationRegistry.usageReason(forId: databaseID) ==
                           CitationRegistry.usageReason(forId: citation.id))
            let usageReason = CitationRegistry.usageReason(forId: citation.id) ?? ""
            #expect(!usageReason.isEmpty)
            #expect(citation.url.hasPrefix("https://"))
            #expect(!CitationRegistry.all.contains { $0.id == citation.id })
            if citation.year == 0 { #expect(!citation.shortText.contains("(0)")) }
        }
    }

    @Test func everyCitationHasUrl() {
        for c in CitationRegistry.all {
            #expect(!c.url.isEmpty, "Citation \(c.id) has no URL")
        }
    }

    @Test func passiveReadinessClaimCitationsResolve() {
        #expect(!PassiveReadinessAnalyzer.claimCitationIds.isEmpty)
        for id in PassiveReadinessAnalyzer.claimCitationIds {
            #expect(CitationRegistry.citation(forId: id) != nil,
                            "passive-readiness claim cites unknown \(id)")
        }
        // The fusion rule itself must remain backed by sawMonitoring2016.
        #expect(CitationRegistry.citation(forId: "sawMonitoring2016") != nil)
        // And the recovery-monitoring pool must include the new evidence.
        let pool = Set(CitationRegistry.recoveryMonitoringPool.citationIds)
        for id in PassiveReadinessAnalyzer.claimCitationIds {
            #expect(pool.contains(id),
                          "recoveryMonitoringPool should include passive-readiness citation \(id)")
        }
    }

    @Test func everyCitationHasSource() {
        for c in CitationRegistry.all {
            #expect(!c.source.isEmpty, "Citation \(c.id) has no source")
        }
    }

    @Test func lookupByIdWorks() {
        for c in CitationRegistry.all {
            #expect(CitationRegistry.citation(forId: c.id) != nil, "Cannot look up \(c.id)")
        }
    }

    // MARK: - Bibliography + usage reasons (2026-07-07)

    @Test func everyUsageReasonResolves() {
        let known = Set(CitationRegistry.all.map(\.id))
        // Every id in usageReasons maps to a real citation.
        for id in CitationRegistry.usageReasons.keys {
            #expect(known.contains(id),
                          "usageReasons references unknown citation id: \(id)")
        }
        // Every citation in the registry has a non-empty usage reason.
        for c in CitationRegistry.all {
            let reason = CitationRegistry.usageReason(forId: c.id)
            #expect(reason != nil, "Citation \(c.id) has no usage reason")
            let nonNilReason = reason ?? ""
            #expect(!nonNilReason.isEmpty, "Citation \(c.id) has an empty usage reason")
        }
        // No orphan usage reasons and a 1:1 mapping with the registry.
        #expect(CitationRegistry.usageReasons.count == CitationRegistry.all.count,
                       "usageReasons and registry must be the same size (1:1 mapping)")
    }

    @Test func bibliographySortedByAuthor() {
        let bib = CitationRegistry.bibliography
        #expect(bib.count == CitationRegistry.all.count,
                       "Bibliography must contain every citation")
        for (a, b) in zip(bib, bib.dropFirst()) {
            #expect(a.authors.localizedCaseInsensitiveCompare(b.authors) != .orderedDescending,
                          "Bibliography not sorted by author: \(a.authors) before \(b.authors)")
        }
    }

    // MARK: - Citation pools

    @Test func aerobicPoolHasAtLeastFiveResearchCitations() {
        let pool = CitationRegistry.aerobicPool
        #expect(pool.citationIds.count >= 5,
                                     "Aerobic pool should have at least 5 citations")
        // Verify no public-health guideline authority citation IDs
        let guidelineIDs = ["whoGuidelines", "hhsGuidelines", "cdcGuidelines", "publicHealthFloor"]
        for id in guidelineIDs {
            #expect(!pool.citationIds.contains(id),
                            "Aerobic pool must not contain guideline/authority citation: \(id)")
        }
        // Verify all pool IDs resolve
        for id in pool.citationIds {
            #expect(CitationRegistry.citation(forId: id) != nil,
                            "Pool citation \(id) must exist in registry")
        }
    }

    @Test func recoveryLoadPoolHasExpectedSize() {
        let pool = CitationRegistry.recoveryLoadPool
        #expect(pool.citationIds.count >= 4,
                                     "Recovery load pool should have at least 4 citations")
        for id in pool.citationIds {
            #expect(CitationRegistry.citation(forId: id) != nil,
                            "Pool citation \(id) must exist in registry")
        }
    }

    @Test func citationRotationIsDeterministic() {
        let pool = CitationRegistry.aerobicPool
        let date = Date(timeIntervalSince1970: 1700000000) // fixed date

        let sel1 = pool.select(for: date, stableId: "testClaim")
        let sel2 = pool.select(for: date, stableId: "testClaim")
        #expect(sel1 == sel2, "Same date and stableId should yield same citation")

        let nextDay = date.addingTimeInterval(86400)
        let sel3 = pool.select(for: nextDay, stableId: "testClaim")
        // May or may not differ depending on pool size, but should be deterministic
        let sel4 = pool.select(for: nextDay, stableId: "testClaim")
        #expect(sel3 == sel4, "Same date+stableId should be stable across calls")
    }

    @Test func citationSelectionVarariesAcrossClaims() {
        let pool = CitationRegistry.aerobicPool
        let date = Date()

        let selA = pool.select(for: date, stableId: "claimA")
        let selB = pool.select(for: date, stableId: "claimB")

        if pool.citationIds.count > 1 {
            // Different claims on same day may or may not differ (hashing)
            // but each should be a valid pool member
            #expect(pool.citationIds.contains(selA ?? ""))
            #expect(pool.citationIds.contains(selB ?? ""))
        }
    }

    // MARK: - 2026-06-25 evidence-upgrade guardrails

    @Test func everyCitationIdIsUnique() {
        let ids = CitationRegistry.all.map(\.id)
        let unique = Set(ids)
        #expect(ids.count == unique.count,
                       "Duplicate citation IDs in registry: \(ids.filter { id in ids.filter { $0 == id }.count > 1 })")
    }

    @Test func everyCitationHasResolvablePublicUrl() {
        for c in CitationRegistry.all {
            #expect(c.url.hasPrefix("https://") || c.url.hasPrefix("http://"),
                          "Citation \(c.id) has a non-navigable URL: \(c.url)")
            #expect(!c.authors.isEmpty, "Citation \(c.id) has no authors")
            #expect(!c.title.isEmpty, "Citation \(c.id) has no title")
        }
    }

    @Test func correctedCitationMetadata() {
        let wingate = CitationRegistry.citation(forId: "wingateTest")
        #expect(wingate?.url == "https://doi.org/10.2165/00007256-198704060-00001")

        let pelland = CitationRegistry.citation(forId: "pellandDoseResponse2026")
        #expect(pelland?.title.contains("Dose Response") == true,
                      "Pelland title not corrected: \(pelland?.title ?? "nil")")
        #expect(pelland?.authors.contains("Remmert") == true)

        let crowley = CitationRegistry.citation(forId: "crowleyVO2Intensity2022")
        #expect(crowley?.source == "Translational Sports Medicine")

        let poon = CitationRegistry.citation(forId: "poonHIIT2024")
        #expect(poon?.source.contains("Scandinavian Journal of Medicine") == true,
                      "Poon source not corrected: \(poon?.source ?? "nil")")

        let saw = CitationRegistry.citation(forId: "sawMonitoring2016")
        #expect(saw?.source.contains("British Journal of Sports Medicine") == true,
                      "Saw source not corrected: \(saw?.source ?? "nil")")

        let iversen = CitationRegistry.citation(forId: "iversenTimeEfficient2021")
        #expect(iversen?.url == "https://pmc.ncbi.nlm.nih.gov/articles/PMC8449772/")
        #expect(CitationRegistry.usageReason(forId: "iversenTimeEfficient2021")?.contains("4-to-12") == true)

        let fractional = CitationRegistry.citation(forId: "pellandDoseResponse2026")
        #expect(fractional?.url == "https://doi.org/10.1007/s40279-025-02344-w")
        let reason = CitationRegistry.usageReason(forId: "pellandDoseResponse2026") ?? ""
        #expect(reason.contains("1.0") && reason.contains("0.5"))
    }

    @Test func everyPoolIdResolves() {
        for category in EvidenceClaimCategory.allCases {
            let pool = CitationRegistry.citationPool(for: category)
            #expect(!pool.citationIds.isEmpty,
                           "Category \(category.rawValue) resolves to an empty pool")
            for id in pool.citationIds {
                #expect(CitationRegistry.citation(forId: id) != nil,
                                "Pool for \(category.rawValue) cites unknown \(id)")
            }
        }
    }

    /// No claim category's pool may borrow a citation curated for an unrelated class.
    @Test func noClaimUsesMismatchedCitationCategory() {
        func ids(_ c: EvidenceClaimCategory) -> Set<String> {
            Set(CitationRegistry.citationPool(for: c).citationIds)
        }

        // Step studies only back step claims.
        let stepOnly: Set<String> = ["saintMauriceSteps2020", "leeAccelerometer2019"]
        #expect(ids(.stepsHealth) == stepOnly)
        #expect(ids(.activityMinutesHealth).isDisjoint(with: stepOnly),
                      "Activity-minutes pool must not cite step-only studies")
        #expect(ids(.aerobicBase).isDisjoint(with: stepOnly))

        // Performance pools must not cite mortality / public-health studies.
        let mortality: Set<String> = ["ekelundActivityMortality2016", "mooreLeisureActivity2012",
                                       "aremDoseResponse2015", "saintMauriceSteps2020",
                                       "leeAccelerometer2019"]
        for c in [EvidenceClaimCategory.vo2Training, .thresholdTraining, .anaerobicTraining,
                  .strengthFrequency, .strengthVolume, .strengthIntensity, .flexibilityROM] {
            #expect(ids(c).isDisjoint(with: mortality),
                          "\(c.rawValue) pool must not cite mortality/public-health studies")
        }

        // Flexibility pool is ROM-only (no injury-prevention overreach baked in).
        #expect(ids(.flexibilityROM) == ["konradStretchROM2024", "behmStretching2016"])

        // Frequency vs volume must not be conflated.
        #expect(ids(.strengthFrequency) == ["frequencyMeta"])
        #expect(!ids(.strengthVolume).contains("frequencyMeta"))

        // VO2 and threshold pools are distinct.
        #expect(ids(.vo2Training).isDisjoint(with: ids(.thresholdTraining)))
    }

    @Test func everyAssessmentKindHasCitationPolicy() {
        let known = Set(CitationRegistry.all.map(\.id))
        for kind in AssessmentKind.allCases {
            let policy = kind.evidencePolicy
            switch policy {
            case .validated(let cids), .fieldEstimate(let cids, _):
                #expect(!cids.isEmpty, "\(kind.rawValue) validated/field policy has no citations")
                for id in cids {
                    #expect(known.contains(id), "\(kind.rawValue) cites unknown \(id)")
                }
            case .personalBenchmark(let cids, let caveat):
                #expect(!caveat.isEmpty, "\(kind.rawValue) personal benchmark has no caveat")
                for id in cids {
                    #expect(known.contains(id), "\(kind.rawValue) cites unknown \(id)")
                }
            }
            // citationIds must mirror the policy
            #expect(kind.citationIds == policy.citationIds)
        }
    }

    @Test func bodyweightAssessmentsAreBenchmarksWhenWeaklyValidated() {
        for kind in [AssessmentKind.pushupMax, .pullupMax, .bodyweightSquatMax, .hollowHold] {
            if case .personalBenchmark = kind.evidencePolicy { continue }
            Issue.record("\(kind.rawValue) should be a personal benchmark, not a validated test")
        }
        // Lab-grade strength tests are validated.
        if case .validated = AssessmentKind.e1RM.evidencePolicy {} else {
            Issue.record("e1RM should be validated")
        }
    }

    @Test func everyCoachSessionCandidateHasCitationIdsUnlessRestOrEmptyLaunch() {
        let known = Set(CitationRegistry.all.map(\.id))
        for experience in [ExperienceLevel.beginner, .intermediate, .advanced] {
            let facts = CoachFacts.make(from: [], goal: .strength, experience: experience, now: Date())
            for candidate in CoachSession.candidates(for: facts) {
                if candidate.kind == .rest || candidate.launchPayload.isEmpty { continue }
                #expect(!candidate.citationIds.isEmpty,
                               "Candidate \(candidate.id) has no citations")
                for id in candidate.citationIds {
                    #expect(known.contains(id),
                                  "Candidate \(candidate.id) cites unknown \(id)")
                }
            }
        }
    }

    @Test func everyDecisionReasonAndWarningCitationIdResolves() throws {
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
                #expect(known.contains(id),
                              "Decision surfaced unknown citation \(id)")
            }
        }
    }

    // MARK: - No health-organization citations (2026-06-29)

    @Test func noHealthOrganizationCitationsInRegistry() {
        let healthOrgAuths: Set<String> = [
            "U.S. Department of Health and Human Services",
            "World Health Organization",
            "Centers for Disease Control",
        ]
        for c in CitationRegistry.all {
            #expect(!healthOrgAuths.contains(c.authors),
                           "Citation \(c.id) has a health-org author: \(c.authors). Only published scientific studies allowed.")
        }
    }

    @Test func cDCActivityGuidelinesNotInRegistry() {
        #expect(CitationRegistry.citation(forId: "cdcActivityGuidelines2018") == nil,
                     "cdcActivityGuidelines2018 must not be in the registry")
    }

    @Test func publicHealthGuidelinePoolContainsOnlyPeerReviewedStudies() {
        let pool = CitationRegistry.publicHealthGuidelinePool
        #expect(!pool.citationIds.isEmpty,
                       "publicHealthGuidelinePool must not be empty")
        #expect(!pool.citationIds.contains("cdcActivityGuidelines2018"),
                       "publicHealthGuidelinePool must not cite CDC/HHS guidelines")
        for id in pool.citationIds {
            guard let c = CitationRegistry.citation(forId: id) else {
                Issue.record("Pool cites unknown citation \(id)"); continue
            }
            // Verify it's a published study (has a DOI or PubMed URL, not a .gov page)
            let url = c.url.lowercased()
            #expect(!(url.contains("health.gov") || url.contains("who.int")),
                           "Citation \(id) has an organization URL, not a published study: \(url)")
        }
    }
}
#endif
