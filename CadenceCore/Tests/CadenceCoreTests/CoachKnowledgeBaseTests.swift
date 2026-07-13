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

    func testNewKBEntryLoads() {
        let kb = CoachKnowledgeBaseLoader.current
        XCTAssertEqual(kb.version, "2026.5.0",
                       "Bundled KB should be bumped to the passive-readiness release")
        guard let entry = kb.entries.first(where: { $0.version == "2026.5.0" }) else {
            return XCTFail("Missing v2026.5.0 passive-readiness changelog entry")
        }
        XCTAssertTrue(entry.title.localizedCaseInsensitiveContains("readiness"),
                      "v2026.5.0 entry should announce passive readiness")
        XCTAssertFalse(entry.citationIds.isEmpty)
        for id in entry.citationIds {
            XCTAssertNotNil(CitationRegistry.citation(forId: id),
                            "v2026.5.0 cites unknown \(id)")
        }
        // Newest entry drives the displayed version.
        XCTAssertEqual(kb.changelog.first?.version, "2026.5.0")

        // The prior bibliography pack must still be present.
        XCTAssertNotNil(kb.entries.first(where: { $0.version == "2026.4.0" }),
                        "v2026.4.0 bibliography entry should remain in the changelog")
    }
}
