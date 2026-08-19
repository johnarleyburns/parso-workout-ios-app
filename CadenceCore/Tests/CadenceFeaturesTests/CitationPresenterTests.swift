import XCTest
import CadenceCore
@testable import CadenceFeatures

/// Field test 2026-08-18 #10: one "The science" row per coaching output, so the
/// id → citation resolution it depends on is tested once, here.
final class CitationPresenterTests: XCTestCase {
    private var knownIds: [String] { CitationRegistry.all.prefix(3).map(\.id) }

    func testResolvesKnownIdsInOrder() {
        let ids = knownIds
        XCTAssertEqual(CitationPresenter.citations(forIds: ids).map(\.id), ids)
    }

    func testDropsUnknownIds() {
        let ids = knownIds
        let mixed = [ids[0], "definitelyNotACitationId", ids[1]]
        XCTAssertEqual(CitationPresenter.citations(forIds: mixed).map(\.id), [ids[0], ids[1]])
        XCTAssertEqual(CitationPresenter.unresolvedIds(mixed), ["definitelyNotACitationId"])
    }

    func testDeDuplicatesRepeatedIds() {
        let ids = knownIds
        let repeated = [ids[0], ids[1], ids[0]]
        XCTAssertEqual(CitationPresenter.citations(forIds: repeated).map(\.id), [ids[0], ids[1]])
    }

    func testHasScienceIsFalseForEmptyAndForAllUnknownIds() {
        XCTAssertFalse(CitationPresenter.hasScience([]))
        XCTAssertFalse(CitationPresenter.hasScience(["nope", "alsoNope"]))
        XCTAssertTrue(CitationPresenter.hasScience(knownIds))
    }

    func testSourcesTitleIsSingularForOneAndPluralForMany() {
        XCTAssertEqual(CitationPresenter.sourcesTitle(count: 1), "Source")
        XCTAssertEqual(CitationPresenter.sourcesTitle(count: 2), "Sources")
        XCTAssertEqual(CitationPresenter.sourcesTitle(count: 0), "Sources")
    }

    // MARK: HARD RULE enforcement — every coaching output resolves its science
    //
    // The equivalent registry-level checks live in `CitationIntegrityTests`
    // (CadenceCoreTests). These assert the same rule through the presenter the
    // UI actually calls, which is only visible from this target.

    func testEveryCoachSessionCitationIdResolves() {
        for experience in [ExperienceLevel.beginner, .intermediate, .advanced] {
            let facts = CoachFacts.make(from: [], goal: .strength, experience: experience, now: Date())
            for candidate in CoachSession.candidates(for: facts) {
                XCTAssertTrue(CitationPresenter.unresolvedIds(candidate.citationIds).isEmpty,
                              "Candidate \(candidate.id) cites ids the UI cannot render: "
                                + CitationPresenter.unresolvedIds(candidate.citationIds).joined(separator: ", "))
                if candidate.kind != .rest, !candidate.launchPayload.isEmpty {
                    XCTAssertTrue(CitationPresenter.hasScience(candidate.citationIds),
                                  "Candidate \(candidate.id) would render no science link")
                }
            }
        }
    }

    func testEveryDecisionWarningCitationIdResolves() {
        let facts = CoachFacts.make(from: [], goal: .strength, experience: .intermediate, now: Date())
        for hasPain in [false, true] {
            let decision = CoachDecisionEngine.run(facts, hasPainConcern: hasPain)
            var ids = decision.citationIds + decision.primary.citationIds
            ids += decision.alternatives.flatMap(\.citationIds)
            ids += decision.warnings.flatMap(\.citationIds)
            ids += decision.deferred.flatMap { $0.reason.citationIds }
            let unresolved = CitationPresenter.unresolvedIds(ids.filter { !$0.isEmpty })
            XCTAssertTrue(unresolved.isEmpty,
                          "Decision surfaced ids the UI cannot render: " + unresolved.joined(separator: ", "))
        }
    }
}
