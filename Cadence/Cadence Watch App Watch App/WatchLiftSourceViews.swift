import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Suggest: reviews the phone-synced strength suggestion; starting is an explicit action.
struct WatchSuggestReviewView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(\.modelContext) private var context
    @State private var launch: WatchLiftLaunch?
    @Query(sort: \WorkoutSession.date, order: .reverse) private var localSessions: [WorkoutSession]

    var body: some View {
        let review: WatchSuggestReview? = WatchSuggestReview.make(plan: watchManager.todayPlan)
            ?? WatchSuggestReview.makeLocal(sessions: localSessions)
        List {
            if let review {
                Section {
                    Text(review.heading).font(.caption).foregroundStyle(.secondary)
                    Text(review.title).font(.headline)
                    if review.isStale {
                        Text("Last synced \(review.syncedAt.formatted(date: .abbreviated, time: .shortened)). This suggestion may be out of date.")
                            .font(.caption2).foregroundStyle(.secondary)
                            .accessibilityIdentifier("watchStrength.suggest.stale")
                    }
                }
                Section("Exercises") {
                    ForEach(Array(review.exerciseLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption)
                    }
                    if !review.prescriptionDetail.isEmpty {
                        Text(review.prescriptionDetail).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if review.canStart {
                Section {
                    if watchManager.isActive {
                        Text("Finish or resume your current workout first.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Button {
                        WatchHaptics.success()
                        launch = review.launch
                    } label: {
                        Label("Start suggested workout", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(watchManager.isActive)
                    .accessibilityIdentifier("watchStrength.suggest.start")
                    .accessibilityHint("Creates a new workout from the suggestion")
                }
                }
            } else {
                Text(WatchSuggestReview.emptyMessage)
                    .font(.footnote)
                    .accessibilityIdentifier("watchStrength.suggest.empty")
            }
        }
        .navigationTitle("Suggest")
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
