import SwiftUI

/// First-launch permission boundary for the Watch app. Keeping this out of the
/// launcher prevents health permission from being buried below workout rows.
struct WatchHealthAuthorizationView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var requesting = false
    @State private var failed = false
    @State private var authorizationReturned = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "heart.text.square.fill")
                .font(.title2)
                .foregroundStyle(.red)
            Text("Heart Rate Access")
                .font(.headline)
            Text("Allow access first so Cladiron can show live heart rate and save cardio workouts.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if authorizationReturned {
                Text(watchManager.hrAuthorized || watchManager.workoutShareAuthorized
                     ? "Access is ready. Continue when you are ready to open Cladiron."
                     : "Access was not granted. You can retry or continue without heart rate.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(watchManager.hrAuthorized || watchManager.workoutShareAuthorized
                                     ? .green : .orange)
                if !watchManager.hrAuthorized && !watchManager.workoutShareAuthorized {
                    Button {
                        requesting = true
                        authorizationReturned = false
                        failed = false
                        Task {
                            let granted = await watchManager.requestWorkoutAuthorization()
                            await MainActor.run {
                                requesting = false
                                authorizationReturned = true
                                failed = !granted && !watchManager.hrAuthorized
                            }
                        }
                    } label: {
                        Label(requesting ? "Requesting…" : "Try Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(requesting)
                    .accessibilityIdentifier("watch.healthAuthorization.retry")
                }
                Button("Continue") {
                    watchManager.finishInitialHealthAuthorization()
                }
                .accessibilityIdentifier("watch.healthAuthorization.done")
            } else {
                Button {
                    requesting = true
                    failed = false
                    Task {
                        let granted = await watchManager.requestWorkoutAuthorization()
                        await MainActor.run {
                            requesting = false
                            authorizationReturned = true
                            failed = !granted && !watchManager.hrAuthorized
                        }
                    }
                } label: {
                    Label(requesting ? "Requesting…" : "Allow Heart Rate Access",
                          systemImage: "heart.fill")
                }
                .disabled(requesting)
                .accessibilityIdentifier("watch.healthAuthorization.allow")
            }

            Button("Continue without heart rate") {
                watchManager.continueWithoutHealthAuthorization()
            }
            .font(.caption2)
            .accessibilityIdentifier("watch.healthAuthorization.continue")

            if failed && !authorizationReturned {
                Text("Access was not granted. You can try again or continue without heart rate.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .accessibilityIdentifier("watch.healthAuthorization")
    }
}
