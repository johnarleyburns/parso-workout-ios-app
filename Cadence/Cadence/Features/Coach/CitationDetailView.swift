import SwiftUI
import CadenceCore

struct CitationDetailView: View {
    let citation: Citation
    var context: String?

    var body: some View {
        List {
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
                    .accessibilityIdentifier("citation.detail.link")
                }
            }
        }
        .navigationTitle("Source")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("citation.detail")
    }
}
