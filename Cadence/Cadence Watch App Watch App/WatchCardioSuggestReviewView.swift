import SwiftUI
import CadenceCore
import CadenceFeatures

/// Cardio "Suggest": renders only the phone-generated cardio snapshot; starting is an explicit action.
struct WatchCardioSuggestReviewView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var cache = WatchCardioSuggestResolutionCache()
    let onStart: (CardioSuggestion) -> Void

    var body: some View {
        let availability = cache.resolve(envelope: watchManager.cardioSuggestionEnvelope,
                                         now: watchManager.coachClock())
        List {
            switch availability {
            case .ready(let suggestion, let heading, _):
                Section {
                    Text(suggestion.protocolName ?? suggestion.type.displayName).font(.headline)
                    Text("\(suggestion.durationMinutes) min · \(suggestion.intensity.rawValue.capitalized)")
                        .font(.caption)
                    Text(heading).font(.caption2).foregroundStyle(.secondary)
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
                    .accessibilityHint("Starts a new cardio workout from the personalized workout")
                }
            case .needsSync(let reason, let lastSyncedAt):
                Section {
                    Label("Needs refresh", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.headline)
                    Text(reason.message).font(.footnote)
                    if let lastSyncedAt {
                        Text("Last synced \(lastSyncedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("watchCardio.suggest.needsSync")
                Section {
                    Button {
                        watchManager.requestSettingsSync()
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("watchCardio.suggest.syncNow")
                    .accessibilityHint("Asks iPhone for a fresh personalized cardio workout")
                }
            }
        }
        .navigationTitle("Personalized")
    }
}
