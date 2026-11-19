import Testing
@testable import CadenceCore

struct CoachKnowledgeBaseTests {

    @Test func knowledgeBaseLoadsFromBundle() {
        let kb = CoachKnowledgeBaseLoader.current
        #expect(kb.version != "0.0.0", "Coach KB resource failed to load")
        #expect(!kb.entries.isEmpty, "Coach KB has no changelog entries")
    }

    @Test func topVersionMatchesNewestEntry() {
        let kb = CoachKnowledgeBaseLoader.current
        #expect(kb.version == kb.changelog.first?.version,
                       "KB version must match the newest changelog entry")
    }

    // HARD RULE: every citation the changelog references must resolve to a real,
    // user-navigable Citation — no raw/broken IDs may surface to the user.
    @Test func everyChangelogCitationResolves() {
        let kb = CoachKnowledgeBaseLoader.current
        for entry in kb.entries {
            #expect(!entry.citationIds.isEmpty,
                           "Changelog entry \(entry.version) cites no science")
            for id in entry.citationIds {
                #expect(CitationRegistry.citation(forId: id) != nil,
                                "Changelog entry \(entry.version) references missing citation: \(id)")
            }
            #expect(entry.citations.count == entry.citationIds.count,
                           "Entry \(entry.version) has unresolved citations")
        }
    }

    @Test func newKBEntryLoads() {
        let kb = CoachKnowledgeBaseLoader.current
        #expect(kb.version == "2026.5.0",
                       "Bundled KB should be bumped to the passive-readiness release")
        guard let entry = kb.entries.first(where: { $0.version == "2026.5.0" }) else {
            Issue.record("Missing v2026.5.0 passive-readiness changelog entry")
            return
        }
        #expect(entry.title.localizedCaseInsensitiveContains("readiness"),
                      "v2026.5.0 entry should announce passive readiness")
        #expect(!entry.citationIds.isEmpty)
        for id in entry.citationIds {
            #expect(CitationRegistry.citation(forId: id) != nil,
                            "v2026.5.0 cites unknown \(id)")
        }
        // Newest entry drives the displayed version.
        #expect(kb.changelog.first?.version == "2026.5.0")

        // The prior bibliography pack must still be present.
        #expect(kb.entries.first(where: { $0.version == "2026.4.0" }) != nil,
                        "v2026.4.0 bibliography entry should remain in the changelog")
    }
}
