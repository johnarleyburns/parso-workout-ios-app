import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Generates today's personalized cardio locally from the phone-built 12-week
/// mirror. Starting remains an explicit action.
struct WatchCardioSuggestReviewView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var suggestion: CardioSuggestion?
    @State private var finished = false
    @State private var needsSync = false
    let onStart: (CardioSuggestion) -> Void

    var body: some View {
        Group {
            if let suggestion {
                List {
                    Section {
                        Text(suggestion.protocolName ?? suggestion.type.displayName)
                            .font(.headline)
                        Text("\(suggestion.durationMinutes) min · \(suggestion.intensity.rawValue.capitalized)")
                            .font(.caption)
                        if let observation = suggestion.observation {
                            Text(observation).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("watchCardio.suggest.ready")
                    Section {
                        if watchManager.isActive {
                            Text("Finish your current workout first.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Button {
                            WatchHaptics.success()
                            onStart(suggestion)
                        } label: {
                            Label("Start", systemImage: "play.fill").frame(minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(watchManager.isActive)
                        .accessibilityIdentifier("watchCardio.suggest.start")
                        .accessibilityHint("Starts the locally generated cardio workout")
                    }
                }
            } else if finished && needsSync {
                List {
                    Section {
                        Label("Sync with iPhone", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                            .font(.headline)
                        Text("Open Cladiron on your iPhone once to send your 12-week training history.")
                            .font(.footnote)
                    }
                    .accessibilityIdentifier("watchCardio.suggest.needsSync")
                }
            } else if finished {
                Text("No personalized cardio workout is available right now.")
                    .font(.footnote)
                    .accessibilityIdentifier("watchCardio.suggest.unavailable")
            } else {
                ProgressView("Preparing personalized cardio…")
            }
        }
        .navigationTitle("Personalized")
        .task(id: watchManager.mesocycleMirrorRevision) {
            await generate()
        }
    }

    @MainActor
    private func generate() async {
        suggestion = nil
        needsSync = false
        finished = false
        guard let envelope = WatchMesocycleMirrorStore().load() else {
            needsSync = true
            finished = true
            return
        }
        let mirror = envelope.mirror
        let result = await Task.detached(priority: .userInitiated) {
            WatchMesocycleInputBuilder.cardioSuggestion(from: mirror, now: mirror.generatedAt)
        }.value
        guard !Task.isCancelled else { return }
        suggestion = result
        finished = true
    }
}
