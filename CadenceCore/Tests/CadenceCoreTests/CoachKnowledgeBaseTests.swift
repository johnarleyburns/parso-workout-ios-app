import XCTest
@testable import CadenceCore

final class CoachKnowledgeBaseTests: XCTestCase {

    func testKnowledgeBaseLoadsFromBundle() {
        let kb = CoachKnowledgeBaseLoader.current
        XCTAssertNotEqual(kb.version, "0.0.0", "Coach KB resource failed to load")
        XCTAssertFalse(kb.entries.isEmpty, "Coach KB has no changelog entries")
    }

    func testTopVersionMatchesNewestEntry() {
        let kb = CoachKnowledgeBaseLoader.current
        XCTAssertEqual(kb.version, kb.changelog.first?.version,
                       "KB version must match the newest changelog entry")
    }

    // HARD RULE: every citation the changelog references must resolve to a real,
    // user-navigable Citation — no raw/broken IDs may surface to the user.
    func testEveryChangelogCitationResolves() {
        let kb = CoachKnowledgeBaseLoader.current
        for entry in kb.entries {
            XCTAssertFalse(entry.citationIds.isEmpty,
                           "Changelog entry \(entry.version) cites no science")
            for id in entry.citationIds {
                XCTAssertNotNil(CitationRegistry.citation(forId: id),
                                "Changelog entry \(entry.version) references missing citation: \(id)")
            }
            XCTAssertEqual(entry.citations.count, entry.citationIds.count,
                           "Entry \(entry.version) has unresolved citations")
        }
    }
}
