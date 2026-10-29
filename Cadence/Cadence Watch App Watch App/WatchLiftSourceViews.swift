import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Suggest: evaluates only the exact shared Coach snapshot; starting is an explicit action.
struct WatchSuggestReviewView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @State private var launch: WatchLiftLaunch?
    @State private var cache = WatchSuggestResolutionCache()

    var body: some View {
        let availability = cache.resolve(envelope: watchManager.coachSuggestionEnvelope,
                                         now: watchManager.coachClock(),
                                         historyState: watchManager.coachHistoryState)
        List {
            switch availability {
            case .ready(let ready, let heading, let syncedAt):
                let review = WatchSuggestReview(launch: ready)
                Section {
                    Text(heading).font(.caption).foregroundStyle(.secondary)
                    Text(review.title).font(.headline)
                    Text("Synced \(syncedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(WatchSuggestResolver.readyAccessibilityLabel)
                .accessibilityIdentifier("watchStrength.suggest.ready")
                Section("Exercises") {
                    ForEach(Array(review.exerciseLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption)
                    }
                    if !review.prescriptionDetail.isEmpty {
                        Text(review.prescriptionDetail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section {
                    if watchManager.isActive {
                        Text("Finish or resume your current workout first.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Button {
                        WatchHaptics.success()
                        launch = ready
                    } label: {
                        Label("Start suggested workout", systemImage: "play.fill")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(watchManager.isActive)
                    .accessibilityIdentifier("watchStrength.suggest.start")
                    .accessibilityHint("Creates a new workout from the suggestion")
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
                .accessibilityLabel(reason.accessibilityLabel)
                .accessibilityIdentifier("watchStrength.suggest.needsSync")
                Section {
                    Button {
                        watchManager.requestSettingsSync()
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("watchStrength.suggest.syncNow")
                    .accessibilityHint("Asks iPhone for a fresh suggestion")
                }
            }
        }
        .navigationTitle("Suggest")
        .onChange(of: availability) { _, new in
            if new.launch == nil { launch = nil }
        }
        .navigationDestination(isPresented: Binding(get: { launch != nil }, set: { if !$0 { launch = nil } })) {
            if let config = launch {
                WatchStrengthView(title: config.title, plannedExerciseNames: config.exerciseNames,
                                  repLadder: config.repLadder, planPayload: config.planPayload)
            }
        }
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
    @Environment(WatchWorkoutManager.self) private var watchManager
    let workout: WatchPreviousWorkout
    @State private var launch: WatchLiftLaunch?

    var body: some View {
        List {
            Section {
                Text("Starts a new workout from this template. Your original workout is not changed.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Section("Exercises") {
                ForEach(Array(workout.structureLines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption)
                }
            }
            Section {
                if watchManager.isActive {
                    Text("Finish or resume your current workout first.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button {
                    WatchHaptics.success()
                    launch = workout.launch
                } label: {
                    Label("Start new workout", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(watchManager.isActive)
                .accessibilityIdentifier("watchStrength.previous.start")
                .accessibilityHint("Creates a new workout from this template")
            }
        }
        .navigationTitle(workout.title)
        .navigationDestination(isPresented: Binding(get: { launch != nil }, set: { if !$0 { launch = nil } })) {
            if let config = launch {
            WatchStrengthView(title: config.title, plannedExerciseNames: config.exerciseNames,
                              repLadder: config.repLadder, planPayload: config.planPayload)
            }
        }
    }
}
