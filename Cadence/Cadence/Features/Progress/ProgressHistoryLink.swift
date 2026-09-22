import SwiftUI

struct ProgressHistoryLink: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("View full history")
                Spacer()
                Image(systemName: "chevron.right").font(.caption)
            }
            .foregroundStyle(.tint).padding(.vertical, 6).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("progress.fullHistory")
    }
}
