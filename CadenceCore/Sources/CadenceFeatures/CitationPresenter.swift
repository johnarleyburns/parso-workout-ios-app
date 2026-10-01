import Foundation
import CadenceCore

/// Resolves a coaching output's citation ids into the ordered, de-duplicated
/// citations a single "The science" link opens (field test 2026-08-18 #10).
/// Pure, so the HARD RULE — every coaching output cites navigable science — is
/// unit-tested rather than asserted by eye in a view.
public enum CitationPresenter {

    /// The UI contract for a citation-bearing surface: zero links when no
    /// citations resolve, otherwise one link that opens the complete source
    /// list. This keeps multi-reference surfaces from rendering one identical
    /// "The Science" affordance per study.
    public struct ScienceLinkPresentation: Equatable, Sendable {
        public let citations: [Citation]

        public init(citations: [Citation]) {
            self.citations = citations
        }

        public var linkCount: Int {
            citations.isEmpty ? 0 : 1
        }
    }

    /// Ordered, de-duplicated citations for `ids`. Unknown ids are dropped: a raw
    /// id must never reach the UI.
    public static func citations(forIds ids: [String]) -> [Citation] {
        var seen: Set<String> = []
        return ids.compactMap { id in
            guard let citation = CitationRegistry.citation(forId: id) else { return nil }
            return seen.insert(citation.id).inserted ? citation : nil
        }
    }

    /// Resolves one science-link presentation for all of `ids`.
    public static func scienceLinkPresentation(forIds ids: [String]) -> ScienceLinkPresentation {
        ScienceLinkPresentation(citations: citations(forIds: ids))
    }

    /// Ids that did not resolve. Non-empty means the registry and the engines
    /// have drifted, which `CitationIntegrityTests` fails on.
    public static func unresolvedIds(_ ids: [String]) -> [String] {
        ids.filter { CitationRegistry.citation(forId: $0) == nil }
    }

    /// Whether a science link should be shown at all.
    public static func hasScience(_ ids: [String]) -> Bool {
        !citations(forIds: ids).isEmpty
    }

    /// Screen title: "Source" for one, "Sources" for several.
    public static func sourcesTitle(count: Int) -> String {
        count == 1 ? String(localized: "Source", bundle: .module) : String(localized: "Sources", bundle: .module)
    }
}
