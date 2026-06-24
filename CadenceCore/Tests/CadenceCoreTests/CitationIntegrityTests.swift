import XCTest
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
}
