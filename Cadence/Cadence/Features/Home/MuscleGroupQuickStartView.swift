import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Muscle-coverage suggestion (Home "muscle groups" tile): offers a fresh session
/// built from catalog suggestions that fill this week's gaps and hands it back as a
/// transient `EditablePlan`. It never reads or writes `PlanningDraft`.
struct MuscleGroupQuickStartView: View {
    let tiers: HomeDashboardPresenter.GapTiers
    private var missing: [MuscleGroup] { tiers.all }
    /// Hands a ready-to-start session back to Home to launch (live) + dismiss.
    let onStart: (WorkoutSession) -> Void
    /// Hands a draft plan back to Home so "Start with these" opens the Workout
    /// Plan editor instead of launching the session immediately.
    let onPlan: (EditablePlan) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @Query(filter: #Predicate<ExerciseSuggestionExclusion> { $0.isActive }) private var exclusions: [ExerciseSuggestionExclusion]

    /// Already exclusion-filtered; computed off the main actor in `.task`.
    @State private var allowedSuggestions: [ExerciseTemplate] = []

    var body: some View {
        NavigationStack {
            List {
                if allowedSuggestions.isEmpty {
                    Section {
                        Text("You've hit every muscle group this week 💪")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("groupQuick.missing")
                    }
                }

                if !allowedSuggestions.isEmpty {
                    Section("Build from suggestions") {
                        ForEach(allowedSuggestions, id: \.id) { t in
                            HStack {
                                Text(t.name)
                                Spacer()
                                Text(ExerciseLibrary.muscleGroups(of: t)
                                        .filter { missing.contains($0) }
                                        .map(\.displayName).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            buildFromSuggestions()
                        } label: {
                            Label("Start with these", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .cadenceGlassButton(prominent: true, tint: .green)
                        .accessibilityIdentifier("groupQuick.buildStart")
                    }
                }
            }
            .navigationTitle("Strength Workout")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: sessions.count) { await refresh() }
            .task(id: exclusions.count) { await refresh() }
        }
    }

    /// Snapshots the few main-actor inputs, then runs the catalog cover off the
    /// main actor so opening the sheet never blocks the UI.
    private func refresh() async {
        let missing = self.missing
        let lastWorkoutIDs = RecentSuggestionExclusion.candidateIDs(
            sessions: sessions, candidates: ExerciseLibrary.starter.map { SuggestedExerciseCandidate(template: $0) })
        let keys = Set(exclusions.map(\.exerciseKey)).union(lastWorkoutIDs)
        let picks = await Task.detached(priority: .userInitiated) {
            ExerciseLibrary.suggestions(forMissing: missing, limit: max(6, missing.count)) {
                SuggestedExerciseFilter.allows($0, keys: keys)
            }
        }.value
        allowedSuggestions = picks
    }

    private func buildFromSuggestions() {
        guard !allowedSuggestions.isEmpty else { return }
        var plan = EditablePlan.empty(warmup: settings.warmupMinutes, cooldown: settings.cooldownMinutes)
        plan.title = String(localized: "Workout")
        plan.exercises = allowedSuggestions.map { template in
            EditableExercise(
                name: template.name,
                sets: Array(repeating: EditableSet(targetReps: 10, targetWeight: nil), count: 3),
                notes: "")
        }
        Haptics.selection()
        dismiss()
        Task { @MainActor in
            await Task.yield()
            onPlan(plan)
        }
    }
}
