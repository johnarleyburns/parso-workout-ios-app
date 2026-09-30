import SwiftUI

/// One-time teaching surface for a new user's first live set. It is deliberately
/// a small overlay so it never steals the tap target from the real set row.
struct FirstSetCoachMark: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Your first set", systemImage: "hand.tap.fill")
                    .font(.headline)
                Spacer()
                Button("Dismiss", action: onDismiss)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("session.firstSetCoachMark.dismiss")
            }
            Text("Tap the next set to edit it, or hold Log set to talk. Your first clear voice command is reviewed before it is saved.")
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlass(in: RoundedRectangle(cornerRadius: 16), fallback: .regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("session.firstSetCoachMark")
    }
}
