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
}
