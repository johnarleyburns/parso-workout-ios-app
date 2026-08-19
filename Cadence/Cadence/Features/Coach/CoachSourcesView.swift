import SwiftUI
import CadenceCore
import CadenceFeatures

/// Every study behind one coaching output, listed vertically on one scrolling
/// screen (field test 2026-08-18 #10, decision **D9**). Reached from a single
/// `The science ›` row however many sources there are.
struct CoachSourcesView: View {
    let citations: [Citation]
    /// Optional per-citation "How this applies" copy, keyed by citation id.
    var contexts: [String: String] = [:]

    var body: some View {
        List {
            ForEach(citations) { citation in
                CitationDetailBody(citation: citation,
                                   context: context(for: citation),
                                   idPrefix: "coach.sources.\(citation.id)")
                    .accessibilityIdentifier("coach.sources.\(citation.id)")
            }
        }
        .navigationTitle(CitationPresenter.sourcesTitle(count: citations.count))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach.sources")
    }

    /// Caller-supplied context wins; otherwise the registry's own usage reason,
    /// so a source never lands on this screen without saying why it is cited.
    private func context(for citation: Citation) -> String? {
        contexts[citation.id] ?? CitationRegistry.usageReason(forId: citation.id)
    }
}
