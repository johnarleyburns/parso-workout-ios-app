import SwiftUI
import CadenceFeatures

/// Marks a workout screen as the owner of the running `HKWorkoutSession` while it is showing.
struct WatchWorkoutScreenPresence: ViewModifier {
    @Environment(WatchWorkoutManager.self) private var watchManager

    func body(content: Content) -> some View {
        content
            .onAppear { watchManager.workoutScreenAppeared() }
            .onDisappear { watchManager.workoutScreenDisappeared() }
    }
}

extension View {
    func ownsWatchWorkoutSession() -> some View { modifier(WatchWorkoutScreenPresence()) }
}

/// Today's notice for a workout session that is recording with nothing on screen using it, or one
/// that was ended for having been left running (field test 2026-10-03).
struct WatchSessionOwnershipCard: View {
    let verdict: WatchSessionOwnership.Verdict
    @Environment(WatchWorkoutManager.self) private var watchManager

    var body: some View {
        if case .unowned(let startedAt) = verdict {
            VStack(alignment: .leading, spacing: 4) {
                Label("Still recording", systemImage: "waveform.path.ecg")
                    .font(.caption2.weight(.bold)).foregroundStyle(WatchTone.attention)
                Text("A workout session started \(startedAt, style: .relative) ago is still running, but no workout is open.")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("End session") { watchManager.stopWorkout(save: false) }
                    .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                    .accessibilityIdentifier("watch.orphanSession.end")
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchTone.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("watch.orphanSession")
        } else if let notice = watchManager.abandonedSessionNotice {
            Button { watchManager.abandonedSessionNotice = nil } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Ended a forgotten session", systemImage: "checkmark.circle")
                        .font(.caption2.weight(.bold))
                    Text("It had been recording since \(notice, format: .dateTime.weekday().hour().minute()) with no workout open. Nothing was saved. Tap to dismiss.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("watch.orphanSession.notice")
        }
    }
}
