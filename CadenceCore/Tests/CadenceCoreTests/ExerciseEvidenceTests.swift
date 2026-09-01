import XCTest
@testable import CadenceCore

final class ExerciseEvidenceTests: XCTestCase {
    func testAllPackageReferencesBecomeCitations() {
        XCTAssertEqual(ExerciseEvidence.citations.count, 62)
    }

    func testEveryEvidenceCitationHasUrlAndYear() {
        for citation in ExerciseEvidence.citations {
            XCTAssertTrue(citation.id.hasPrefix("exdb."))
            XCTAssertFalse(citation.url.isEmpty)
            XCTAssertGreaterThan(citation.year, 1900)
        }
    }

    func testCitationRegistryResolvesExerciseEvidenceIds() {
        for citation in ExerciseEvidence.citations {
            XCTAssertEqual(CitationRegistry.citation(forId: citation.id), citation)
        }
    }

    func testCuratedRegistryIsUnchanged() {
        XCTAssertEqual(CitationRegistry.all.count, 59)
        XCTAssertEqual(CitationRegistry.usageReasons.count, CitationRegistry.all.count)
    }

    func testShortTextHandlesEmptyAuthors() {
        let citation = ExerciseEvidence.citations[0]
        XCTAssertEqual(citation.shortText, "\(citation.source) (\(citation.year))")
    }

    func testEveryPatternHasSummaryAndAtLeastOneCitation() {
        XCTAssertEqual(ExerciseEvidence.patterns.count, 89)
        for pattern in ExerciseEvidence.patterns.values {
            XCTAssertFalse(pattern.summary.isEmpty)
            if pattern.citationIDs.isEmpty {
                XCTAssertEqual(pattern.status, "provisional")
            } else {
                for id in pattern.citationIDs { XCTAssertNotNil(CitationRegistry.citation(forId: id)) }
            }
        }
    }

    func testEveryExercisePatternResolves() {
        for record in TrainingEngineBridge.exerciseRecords {
            for id in record.patterns {
                XCTAssertNotNil(ExerciseEvidence.patterns[id], "Missing pattern \(id)")
            }
        }
    }

    func testPatternDisplayNamesAreHumanReadable() {
        for pattern in ExerciseEvidence.patterns.values {
            XCTAssertFalse(pattern.displayName.contains("_"))
        }
    }
}
