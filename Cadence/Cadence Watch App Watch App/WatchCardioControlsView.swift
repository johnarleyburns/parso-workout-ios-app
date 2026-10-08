import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchCardioControlsView: View {
    let isSwim: Bool
    let isPaused: Bool
    let automaticallyTracksLaps: Bool
    let onEnd: () -> Void
    let onPause: () -> Void
    let onLock: () -> Void
    let onLap: () -> Void

    init(isSwim: Bool, isPaused: Bool = false, automaticallyTracksLaps: Bool = false, onEnd: @escaping () -> Void,
         onPause: @escaping () -> Void, onLock: @escaping () -> Void, onLap: @escaping () -> Void) {
        self.isSwim = isSwim
        self.isPaused = isPaused
        self.automaticallyTracksLaps = automaticallyTracksLaps
        self.onEnd = onEnd
        self.onPause = onPause
        self.onLock = onLock
        self.onLap = onLap
    }

    /// I2 — Controls page, the same tiles as strength and intervals (red End, surface others).
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            controlButton(isPaused ? "Resume" : "Pause", isPaused ? "play.fill" : "pause.fill",
                          identifier: "watchCardio.pause", action: onPause)
            controlButton("End", "xmark", isDestructive: true, identifier: "watchCardio.end", action: onEnd)
            controlButton("Water Lock", "drop.fill", identifier: "watchCardio.lock", action: onLock)
            if automaticallyTracksLaps {
                Label("Auto laps", systemImage: "figure.pool.swim")
                    .font(.caption2).foregroundStyle(.secondary)
            } else if isSwim {
                Label("GPS distance", systemImage: "location.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                controlButton("Lap", "plus", identifier: "watchCardio.lap", action: onLap)
            }
        }
        .padding(.horizontal, 2)
    }

    private func controlButton(_ label: LocalizedStringKey, _ icon: String, isDestructive: Bool = false,
                               identifier: String, action: @escaping () -> Void) -> some View {
        Button {
            WatchHaptics.tap()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(RoundedRectangle(cornerRadius: 14).fill(isDestructive ? Color.red.opacity(0.18) : WatchTone.surface))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
