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
