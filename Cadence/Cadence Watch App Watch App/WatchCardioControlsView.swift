import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchCardioControlsView: View {
    let isSwim: Bool
    let isPaused: Bool
    let onEnd: () -> Void
    let onPause: () -> Void
    let onLock: () -> Void
    let onLap: () -> Void

    init(isSwim: Bool, isPaused: Bool = false, onEnd: @escaping () -> Void,
         onPause: @escaping () -> Void, onLock: @escaping () -> Void, onLap: @escaping () -> Void) {
        self.isSwim = isSwim
        self.isPaused = isPaused
        self.onEnd = onEnd
        self.onPause = onPause
        self.onLock = onLock
        self.onLap = onLap
    }

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                controlButton("End", "stop.fill", isDestructive: true, action: onEnd)
                controlButton(isPaused ? "Resume" : "Pause", isPaused ? "play.fill" : "pause.fill", isPause: true, action: onPause)
                controlButton("Lock", "lock.fill", action: onLock)
                controlButton(isSwim ? "Lap" : "Lap", "plus", action: onLap)
            }
        }
        .padding()
    }

    private func controlButton(_ label: String, _ icon: String, isDestructive: Bool = false, isPause: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isDestructive ? Color.red.opacity(0.3) : isPause ? Color.yellow.opacity(0.25) : Color.white.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(isDestructive ? .red : isPause ? .yellow : .white)
        }
        .buttonStyle(.plain)
    }
}
