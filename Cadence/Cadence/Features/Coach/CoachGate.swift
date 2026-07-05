import SwiftUI
import CadenceCore

/// The single entitlement gate for Coach surfaces. When Pro, shows `content`;
/// otherwise shows `locked` (the preview funnel). Every Coach entry point routes
/// through this so free ↔ Pro behaviour lives in exactly one place
/// (monetization plan §4.3). Never gate logging, history, Progress, or export.
struct CoachGate<Content: View, Locked: View>: View {
    @Environment(StoreService.self) private var store
    @ViewBuilder var content: () -> Content
    @ViewBuilder var locked: () -> Locked

    var body: some View {
        if store.isPro {
            content()
        } else {
            locked()
        }
    }
}

/// A full-screen locked stub for pushed Coach destinations reached without Pro.
struct CoachLockedView: View {
    var title: String = "Coaching is a Pro feature"
    var message: String = "Unlock the Coach to see today's prescription, autoregulation, and adaptation guidance — all cited."
    var onUnlock: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.mind.and.body")
                .scaledSystemFont(46, relativeTo: .largeTitle)
                .foregroundStyle(.green)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button { onUnlock() } label: {
                Label("Unlock the Coach", systemImage: "lock.open.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .cadenceGlassButton(prominent: true, tint: .green)
            .accessibilityIdentifier("coach.locked.unlock")
            Text("Everything else in Cladiron is free forever.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { CadenceGlassBackdrop(tint: .green) }
        .accessibilityIdentifier("coach.locked")
    }
}
