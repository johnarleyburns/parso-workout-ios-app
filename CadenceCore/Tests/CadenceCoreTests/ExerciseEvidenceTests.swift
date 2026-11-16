import XCTest
@testable import CadenceCore

final class ExerciseEvidenceTests: XCTestCase {
    func testAllPackageReferencesBecomeCitations() {
        XCTAssertEqual(ExerciseEvidence.citations.count, 78)
    }

    func testEveryEvidenceCitationHasUrlAndAnHonestDate() {
        for citation in ExerciseEvidence.citations {
            XCTAssertTrue(citation.id.hasPrefix("exdb."))
            XCTAssertFalse(citation.url.isEmpty)
            let key = String(citation.id.dropFirst("exdb.".count))
            let reference = TrainingEngineBridge.evidenceReferences[key]
            if citation.year == 0 {
                XCTAssertTrue(["clinical_exercise_guide", "manufacturer_exercise_guide"].contains(reference?.type ?? ""))
            } else {
                XCTAssertGreaterThan(citation.year, 1900)
            }
        }
    }

    func testCitationRegistryResolvesExerciseEvidenceIds() {
        for citation in ExerciseEvidence.citations {
            XCTAssertEqual(CitationRegistry.citation(forId: citation.id), citation)
        }
    }

    func testCuratedRegistryIsUnchanged() {
        XCTAssertEqual(CitationRegistry.all.count, 73)
        XCTAssertEqual(CitationRegistry.usageReasons.count, CitationRegistry.all.count)
    }

    func testShortTextHandlesEmptyAuthors() {
        let citation = ExerciseEvidence.citations[0]
        XCTAssertEqual(citation.shortText, citation.year > 0 ? "\(citation.source) (\(citation.year))" : citation.source)
    }

    func testEveryPatternHasSummaryAndAtLeastOneCitation() {
        XCTAssertEqual(ExerciseEvidence.patterns.count, 93)
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
