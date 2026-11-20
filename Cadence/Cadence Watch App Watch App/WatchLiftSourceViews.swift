import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

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
            workouts = WatchLiftSources.load(from: context)
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
