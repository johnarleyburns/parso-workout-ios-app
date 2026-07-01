import SwiftUI

/// The contribution ask — a dismissible bottom card (never a full-screen
/// interstitial, never shown during a workout). Three actions: Support /
/// Maybe later / Don't ask again. Surfaced only from Home.
struct ContributionToast: View {
    let onSupport: () -> Void
    let onLater: () -> Void
    let onNever: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enjoying Cladiron?")
                .font(.headline)
            Text("It's free, open-source, and has no ads or subscriptions. An optional tip helps support continued development.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Maybe later", action: onLater)
                    .font(.subheadline)
                    .fixedSize()
                Spacer(minLength: 12)
                Button("Support", action: onSupport)
                    .font(.subheadline).fontWeight(.semibold)
                    .lineLimit(1)
                    .fixedSize()
                    .buttonStyle(.borderedProminent)
            }
            Button("Don't ask again", action: onNever)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
        .padding(16)
        .cadenceGlass(in: RoundedRectangle(cornerRadius: 16), fallback: .regularMaterial)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contribution.toast")
    }
}
