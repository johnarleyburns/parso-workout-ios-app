import Foundation

/// One entry in the Coach knowledge-base changelog. Each quarterly "protocol pack"
/// (monetization plan §4.6, §6) appends an entry describing what programming logic
/// changed and which citations back it. `citationIds` MUST resolve via
/// `CitationRegistry` (enforced by tests) — the HARD RULE applies to the changelog
/// as much as to any other coaching surface.
public struct CoachKBChangeEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: String { version }
    public let version: String
    public let date: String
    public let title: String
    public let summary: String
    public let citationIds: [String]

    public init(version: String, date: String, title: String, summary: String, citationIds: [String]) {
        self.version = version
        self.date = date
        self.title = title
        self.summary = summary
        self.citationIds = citationIds
    }

    /// Resolved, user-navigable citations (never expose raw IDs).
    public var citations: [Citation] {
        citationIds.compactMap { CitationRegistry.citation(forId: $0) }
    }
}

/// The versioned, in-repo Coach knowledge base. Ships with the app; quarterly
/// packs bump `version` and add a changelog entry via an app update.
public struct CoachKnowledgeBase: Codable, Equatable, Sendable {
    public let version: String
    public let releaseDate: String
    public let entries: [CoachKBChangeEntry]

    public init(version: String, releaseDate: String, entries: [CoachKBChangeEntry]) {
        self.version = version
        self.releaseDate = releaseDate
        self.entries = entries
    }

    /// Changelog newest-first for display.
    public var changelog: [CoachKBChangeEntry] {
        entries.sorted { $0.version > $1.version }
    }
}

public enum CoachKnowledgeBaseLoader {
    /// The knowledge base bundled with this build. Falls back to an empty KB if the
    /// resource is missing/corrupt, so the app never crashes over content.
    public static let current: CoachKnowledgeBase = load()

    static func load() -> CoachKnowledgeBase {
        guard let url = Bundle.module.url(forResource: "coach-kb-version", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let kb = try? JSONDecoder().decode(CoachKnowledgeBase.self, from: data) else {
            return CoachKnowledgeBase(version: "0.0.0", releaseDate: "", entries: [])
        }
        return kb
    }
}
