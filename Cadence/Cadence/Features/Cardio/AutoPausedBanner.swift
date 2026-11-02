import SwiftUI

/// Visible, accessible explanation for an automatic inactivity pause. The workout is
/// never discarded; the user can resume (or end) at any time.
struct AutoPausedBanner: View {
    let idPrefix: String
    var body: some View {
        Label {
            Text("\(AppModel.autoPausedMessage). Tap Resume to continue, or End to save it.")
        } icon: {
            Image(systemName: "pause.circle.fill")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(idPrefix).autoPaused")
    }
}
