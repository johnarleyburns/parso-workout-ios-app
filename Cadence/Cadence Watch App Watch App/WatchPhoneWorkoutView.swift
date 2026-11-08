import SwiftUI

struct WatchPhoneWorkoutView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var showStopConfirmation = false

    var body: some View {
        VStack(spacing: 10) {
            Label("Workout on iPhone", systemImage: "iphone.and.arrow.forward")
                .font(.headline)

            if let bpm = watchManager.currentBPM {
                Label("\(Int(bpm.rounded())) bpm", systemImage: "heart.fill")
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("watch.phoneWorkout.bpm")
            } else {
                ProgressView("Monitoring heart rate")
                    .accessibilityIdentifier("watch.phoneWorkout.monitoring")
            }

            Text("Heart rate is being recorded. Log sets and finish the workout on your iPhone.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Stop heart-rate recording", role: .destructive) {
                showStopConfirmation = true
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("watch.phoneWorkout.stop")
        }
        .padding()
        .confirmationDialog("Stop heart-rate recording?", isPresented: $showStopConfirmation, titleVisibility: .visible) {
            Button("Stop recording", role: .destructive) {
                // This is deliberately available even for a phone-owned
                // session. It is the Watch-local escape hatch if the phone
                // started one by mistake or is no longer reachable.
                watchManager.stopWorkout(save: false)
            }
        } message: {
            Text("This ends the Apple Watch workout without saving it.")
        }
        .accessibilityIdentifier("watch.phoneWorkout.active")
        .ownsWatchWorkoutSession()
    }
}
