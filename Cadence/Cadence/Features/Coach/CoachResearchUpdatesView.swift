import SwiftUI
import CadenceCore

/// The Coach knowledge-base changelog ("Coach research updates"). Both free and Pro
/// users see it — for free users it reinforces the value of the coaching layer
/// (monetization plan §4.6). Every entry renders its citations tappably.
struct CoachResearchUpdatesView: View {
    @Environment(AppSettings.self) private var settings

    private let kb = CoachKnowledgeBaseLoader.current

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coach v\(kb.version)")
                        .font(.headline)
                    Text("The coaching engine is updated quarterly as new strength and hypertrophy research is published. Each update lists what changed and the studies behind it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            ForEach(kb.changelog) { entry in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entry.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("v\(entry.version)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(entry.date).font(.caption2).foregroundStyle(.secondary)
                        Text(entry.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(entry.citations) { citation in
                            CitationLink(citation: citation, compact: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ForEach(CitationRegistry.bibliography) { citation in
                    BibliographyRow(citation: citation)
                }
            } header: {
                Text("Bibliography")
            } footer: {
                Text("Every study the coaching engine cites, ordered by author. Tap any entry to read why the Coach uses it and open the paper.")
            }
        }
        .navigationTitle("Coach Research Updates")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach.researchUpdates")
        .onAppear {
            // Mark the current pack as seen — clears the "new" badge.
            settings.lastSeenCoachKBVersion = kb.version
        }
    }
}

/// True when the bundled KB is newer than what the user last viewed.
enum CoachKBBadge {
    static func hasUnseenUpdate(lastSeen: String) -> Bool {
        let current = CoachKnowledgeBaseLoader.current.version
        return current != "0.0.0" && current != lastSeen
    }
}

/// One bibliography entry: author + year, title, source, and a tappable link to the
/// full `CitationDetailView` (which shows the usage reason + "Read the paper" link).
private struct BibliographyRow: View {
    let citation: Citation

    private var usageReason: String? {
        CitationRegistry.usageReason(forId: citation.id)
    }

    var body: some View {
        NavigationLink {
            CitationDetailView(citation: citation, context: usageReason)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(citation.shortText)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(citation.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let usageReason {
                    Text(usageReason)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(citation.authors), \(String(citation.year)). \(citation.title). \(usageReason ?? "")")
        .accessibilityIdentifier("coach.bibliography.\(citation.id)")
    }
}
