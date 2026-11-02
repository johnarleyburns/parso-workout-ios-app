import SwiftUI

struct WatchPhoneWorkoutView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager

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
        }
        .padding()
        .accessibilityIdentifier("watch.phoneWorkout.active")
        .ownsWatchWorkoutSession()
    }
}
