import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Suggest: evaluates only the exact shared Coach snapshot; starting is an explicit action.
struct WatchSuggestReviewView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var cache = WatchSuggestResolutionCache()

    var body: some View {
        let availability = cache.resolve(envelope: watchManager.coachSuggestionEnvelope,
                                         now: watchManager.coachClock(),
                                         historyState: watchManager.coachHistoryState)
        Group {
            if case .ready(let ready, _, _) = availability {
                WatchStrengthPreview(launch: ready)
            } else if case .needsSync(let reason, let lastSyncedAt) = availability {
                List {
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
                    .accessibilityLabel(reason.accessibilityLabel)
                    .accessibilityIdentifier("watchStrength.suggest.needsSync")
                    Button { watchManager.requestSettingsSync() } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("watchStrength.suggest.syncNow")
                    .accessibilityHint("Asks iPhone for a fresh personalized workout")
                }
            }
        }
        .navigationTitle("Personalized")
    }
}

/// Previous: last five completed strength workouts, each an immutable template.
struct WatchPreviousListView: View {
    @Environment(\.modelContext) private var context
    @State private var workouts: [WatchPreviousWorkout] = []
    @State private var loaded = false

    var body: some View {
        List {
            if loaded && workouts.isEmpty {
                Text(WatchPreviousWorkout.emptyMessage)
                    .font(.footnote)
                    .accessibilityIdentifier("watchStrength.previous.empty")
            }
            ForEach(workouts) { workout in
                NavigationLink {
                    WatchPreviousDetailView(workout: workout)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.title).fontWeight(.semibold).lineLimit(1)
                        Text(workout.completedAt.formatted(.relative(presentation: .named)))
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(workout.summary).font(.caption2).foregroundStyle(.secondary)
                        Text(workout.preview).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .accessibilityIdentifier("watchStrength.previous.\(workout.id.uuidString)")
            }
        }
        .navigationTitle("Previous")
        .onAppear {
            workouts = WatchPreviousWorkout.load(from: context)
            loaded = true
        }
    }
}

private struct WatchPreviousDetailView: View {
    let workout: WatchPreviousWorkout
    var body: some View {
        WatchStrengthPreview(launch: workout.launch)
    }
}
