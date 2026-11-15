import SwiftUI
import CadenceCore

/// Minimal, isolated rendering of modality-filtered coach warnings beneath a
/// request card. Citations sit behind one "The Science" link.
struct CoachWarningRow: View {
    let warnings: [CoachWarning]

    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(warnings) { warning in
                    Label(warning.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("home.warning.\(warning.id)")
                    if !warning.citationIds.isEmpty {
                        CoachSourcesLink(citationIds: warning.citationIds,
                                         identifier: "home.warning.\(warning.id).science")
                    }
                }
            }
            .padding(.top, 4)
        }
    }
}
