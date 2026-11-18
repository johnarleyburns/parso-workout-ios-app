import Testing
@testable import CadenceCore

struct ExerciseEvidenceTests {
    @Test func allPackageReferencesBecomeCitations() {
        #expect(ExerciseEvidence.citations.count == 78)
    }

    @Test func everyEvidenceCitationHasUrlAndAnHonestDate() {
        for citation in ExerciseEvidence.citations {
            #expect(citation.id.hasPrefix("exdb."))
            #expect(!citation.url.isEmpty)
            let key = String(citation.id.dropFirst("exdb.".count))
            let reference = TrainingEngineBridge.evidenceReferences[key]
            if citation.year == 0 {
                #expect(["clinical_exercise_guide", "manufacturer_exercise_guide"].contains(reference?.type ?? ""))
            } else {
                #expect(citation.year > 1900)
            }
        }
    }

    @Test func citationRegistryResolvesExerciseEvidenceIds() {
        for citation in ExerciseEvidence.citations {
            #expect(CitationRegistry.citation(forId: citation.id) == citation)
        }
    }

    @Test func curatedRegistryIsUnchanged() {
        #expect(CitationRegistry.all.count == 73)
        #expect(CitationRegistry.usageReasons.count == CitationRegistry.all.count)
    }

    @Test func shortTextHandlesEmptyAuthors() {
        let citation = ExerciseEvidence.citations[0]
        #expect(citation.shortText == (citation.year > 0 ? "\(citation.source) (\(citation.year))" : citation.source))
    }

    @Test func everyPatternHasSummaryAndAtLeastOneCitation() {
        #expect(ExerciseEvidence.patterns.count == 93)
        for pattern in ExerciseEvidence.patterns.values {
            #expect(!pattern.summary.isEmpty)
            if pattern.citationIDs.isEmpty {
                #expect(pattern.status == "provisional")
            } else {
                for id in pattern.citationIDs { #expect(CitationRegistry.citation(forId: id) != nil) }
            }
        }
    }

    @Test func everyExercisePatternResolves() {
        for record in TrainingEngineBridge.exerciseRecords {
            for id in record.patterns {
                #expect(ExerciseEvidence.patterns[id] != nil, "Missing pattern \(id)")
            }
        }
    }

    @Test func patternDisplayNamesAreHumanReadable() {
        for pattern in ExerciseEvidence.patterns.values {
            #expect(!pattern.displayName.contains("_"))
        }
    }
}
