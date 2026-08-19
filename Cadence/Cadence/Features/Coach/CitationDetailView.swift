import SwiftUI
import CadenceCore

struct CitationDetailView: View {
    let citation: Citation
    var context: String?

    var body: some View {
        List {
            CitationDetailBody(citation: citation, context: context)
        }
        .navigationTitle("Source")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("citation.detail")
    }
}

/// The sections that describe one study — title/authors/year/journal, how it
/// applies, and the link out. Shared so a single-source screen and the
/// multi-source `CoachSourcesView` can never drift apart (field test
/// 2026-08-18 #10).
struct CitationDetailBody: View {
    let citation: Citation
    var context: String?
    /// Prefix for this study's accessibility identifiers. The single-source
    /// screen keeps its historical `citation.detail.link` id.
    var idPrefix: String = "citation.detail"

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(citation.title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(citation.authors)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Label(String(citation.year), systemImage: "calendar")
                    Label(citation.source, systemImage: "book.closed")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }

        if let context {
            Section("How this applies") {
                Text(context)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let url = URL(string: citation.url) {
            Section {
                Link(destination: url) {
                    Label("Read the paper", systemImage: "arrow.up.right.square")
                }
                .accessibilityIdentifier("\(idPrefix).link")
            }
        }
    }
}
