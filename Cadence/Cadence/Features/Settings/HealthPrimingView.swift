import SwiftUI
import CadenceCore

/// In-context priming before the HealthKit system sheet (FR-4.1, NFR-3).
struct HealthPrimingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let onResult: (HealthAuthorizationStatus) -> Void
    @State private var requesting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.pink)
                    .padding(.top, 24)
                Text("Connect Apple Health")
                    .font(.title2.bold())
                VStack(alignment: .leading, spacing: 16) {
                    primingRow("figure.walk", "Read your steps and daily activity to show them on Today.")
                    primingRow("figure.run", "Import workouts and heart rate recorded by your Apple Watch.")
                    primingRow("square.and.arrow.up", "Save a summary of your strength workouts back to Health.")
                }
                .padding(.horizontal)
                Text("Cadence requests only what it needs, and your health data never leaves your device.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Spacer()
                Button {
                    Task {
                        requesting = true
                        let status = await model.health.requestAuthorization()
                        requesting = false
                        onResult(status)
                        dismiss()
                    }
                } label: {
                    Text(requesting ? "Requesting…" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(requesting)
                .padding(.horizontal)
                .accessibilityIdentifier("health.priming.continue")
            }
            .padding(.bottom)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
            }
        }
    }

    private func primingRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 28)
            Text(text)
            Spacer()
        }
    }
}
