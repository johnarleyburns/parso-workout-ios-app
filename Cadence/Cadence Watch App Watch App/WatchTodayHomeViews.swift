import SwiftUI
import CadenceCore
import CadenceFeatures

/// Today-home "Ready when you are" card shown when nothing is planned.
struct WatchReadyCard: View {
    let syncReminder: String?
    let onStrength: () -> Void
    let onCardio: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "dumbbell.fill")
                .font(.headline)
                .foregroundStyle(WatchTone.accentInk)
                .frame(width: 32, height: 32)
                .background(Circle().fill(WatchTone.accentGradient))
                .accessibilityHidden(true)
            Text("Ready when you are").font(.headline)
            Text("Choose how you want to train.").font(.caption2).foregroundStyle(.secondary)
            Button { onStrength() } label: { Label("Start strength", systemImage: "dumbbell.fill") }
                .buttonStyle(WatchPillStyle(kind: .primary))
                .accessibilityHint(Text("Opens suggested, previous, or custom strength choices"))
                .accessibilityIdentifier("watch.startStrength")
            Text("Suggested, previous, or custom").font(.caption2).foregroundStyle(.secondary)
            Button { onCardio() } label: { Label("Cardio", systemImage: "figure.run") }
                .buttonStyle(WatchCardioPillStyle())
                .accessibilityHint(Text("Opens cardio workout choices"))
                .accessibilityIdentifier("watch.cardio")
            if let reminder = syncReminder {
                Text(reminder).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WatchTone.readyGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("watch.todayReady")
    }
}

/// Cool secondary pill for cardio actions.
struct WatchCardioPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 6)
            .background(Capsule().fill(LinearGradient(colors: [WatchTone.cardio.opacity(0.55), WatchTone.cardioDeep],
                                                      startPoint: .top, endPoint: .bottom)))
            .overlay(Capsule().strokeBorder(WatchTone.cardio.opacity(0.8), lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Rest-day alternate workout chooser: exactly Strength and Cardio.
struct WatchWorkoutChoiceView: View {
    let onStrength: () -> Void
    let onCardio: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Button(action: onStrength) { Label("Strength", systemImage: "dumbbell.fill") }
                    .buttonStyle(WatchPillStyle(kind: .primary))
                    .accessibilityIdentifier("watch.workoutChoice.strength")
                Button(action: onCardio) { Label("Cardio", systemImage: "figure.run") }
                    .buttonStyle(WatchCardioPillStyle())
                    .accessibilityIdentifier("watch.workoutChoice.cardio")
            }
        }
        .navigationTitle("Start workout")
    }
}

/// Two tiles in one row: plain Buttons with their own destinations, because a List row
/// with two NavigationLinks activates as one (tapping Lift opened Cardio).
struct WatchQuickStartTiles: View {
    let onLift: () -> Void
    let onCardio: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onLift) { tile(title: "Lift", systemImage: "dumbbell.fill") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch.startStrength")
            Button(action: onCardio) { tile(title: "Cardio", systemImage: "figure.run") }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watch.cardio")
        }
    }

    private func tile(title: LocalizedStringKey, systemImage: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(height: 22, alignment: .center)
            Text(title)
                .font(.caption2.weight(.semibold))
                .frame(height: 16, alignment: .center)
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .center)
        .background(RoundedRectangle(cornerRadius: 14).fill(WatchTone.surface))
    }
}
