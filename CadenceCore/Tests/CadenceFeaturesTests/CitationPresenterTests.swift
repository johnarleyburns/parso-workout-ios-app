import Foundation
import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

/// Field test 2026-08-18 #10: one "The science" row per coaching output, so the
/// id → citation resolution it depends on is tested once, here.
struct CitationPresenterTests {
    private var knownIds: [String] { CitationRegistry.all.prefix(3).map(\.id) }

    @Test func resolvesKnownIdsInOrder() {
        let ids = knownIds
        #expect(CitationPresenter.citations(forIds: ids).map(\.id) == ids)
    }

    @Test func dropsUnknownIds() {
        let ids = knownIds
        let mixed = [ids[0], "definitelyNotACitationId", ids[1]]
        #expect(CitationPresenter.citations(forIds: mixed).map(\.id) == [ids[0], ids[1]])
        #expect(CitationPresenter.unresolvedIds(mixed) == ["definitelyNotACitationId"])
    }

    @Test func deDuplicatesRepeatedIds() {
        let ids = knownIds
        let repeated = [ids[0], ids[1], ids[0]]
        #expect(CitationPresenter.citations(forIds: repeated).map(\.id) == [ids[0], ids[1]])
    }

    @Test func personalizedWorkoutUsesOneScienceLinkForAllSources() {
        let presentation = CitationPresenter.scienceLinkPresentation(
            forIds: SuggestedWorkoutPresenter.citationIDs)

        #expect(presentation.citations.map(\.id) == SuggestedWorkoutPresenter.citationIDs)
        #expect(presentation.citations.count == 5)
        #expect(presentation.linkCount == 1,
                       "A multi-reference personalized workout must render one science link")
    }

    @Test func cardioIntensityPolicyIdsDeduplicateInOrderWithUnknownIds() {
        let ids = CardioIntensityPolicy.citationIDs
        let presentation = CitationPresenter.scienceLinkPresentation(
            forIds: ids + [ids[0], "unknownStaleId"])

        #expect(presentation.citations.map(\.id) == ids)
        #expect(presentation.linkCount == 1)
    }

    @Test func hasScienceIsFalseForEmptyAndForAllUnknownIds() {
        #expect(!CitationPresenter.hasScience([]))
        #expect(!CitationPresenter.hasScience(["nope", "alsoNope"]))
        #expect(CitationPresenter.hasScience(knownIds))
    }

    @Test func sourcesTitleIsSingularForOneAndPluralForMany() {
        #expect(CitationPresenter.sourcesTitle(count: 1) == "Source")
        #expect(CitationPresenter.sourcesTitle(count: 2) == "Sources")
        #expect(CitationPresenter.sourcesTitle(count: 0) == "Sources")
    }

    // MARK: HARD RULE enforcement — every coaching output resolves its science
    //
    // The equivalent registry-level checks live in `CitationIntegrityTests`
    // (CadenceCoreTests). These assert the same rule through the presenter the
    // UI actually calls, which is only visible from this target.

    @Test func everyCoachSessionCitationIdResolves() {
        for experience in [ExperienceLevel.beginner, .intermediate, .advanced] {
            let facts = CoachFacts.make(from: [], goal: .strength, experience: experience, now: Date())
            for candidate in CoachSession.candidates(for: facts) {
                #expect(CitationPresenter.unresolvedIds(candidate.citationIds).isEmpty,
                              "Candidate \(candidate.id) cites ids the UI cannot render: \(CitationPresenter.unresolvedIds(candidate.citationIds).joined(separator: ", "))")
                if candidate.kind != .rest, !candidate.launchPayload.isEmpty {
                    #expect(CitationPresenter.hasScience(candidate.citationIds),
                                  "Candidate \(candidate.id) would render no science link")
                }
            }
        }
    }

    @Test func everyDecisionWarningCitationIdResolves() {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: Date())
        for hasPain in [false, true] {
            let decision = CoachDecisionEngine.run(facts, hasPainConcern: hasPain)
            var ids = decision.citationIds + decision.primary.citationIds
            ids += decision.alternatives.flatMap(\.citationIds)
            ids += decision.warnings.flatMap(\.citationIds)
            ids += decision.deferred.flatMap { $0.reason.citationIds }
            let unresolved = CitationPresenter.unresolvedIds(ids.filter { !$0.isEmpty })
            #expect(unresolved.isEmpty,
                          "Decision surfaced ids the UI cannot render: \(unresolved.joined(separator: ", "))")
        }
    }
}
