import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Quick-start that targets the muscle groups you haven't trained this week (feedback
/// batch 8 — tapping the Home "muscle groups" tile). It first lists your **past
/// workouts** ranked by how many of the missing groups they cover (tap → reuse it),
/// then offers a fresh session built from catalog **suggestions** that fill the gaps.
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

    /// Computed once per history change, not on every body pass. Ranking walks
    /// every set of every past session, and the list used to evaluate it twice
    /// per render (the `isEmpty` check and the `ForEach`).
    @State private var ranked: [(session: WorkoutSession, covered: [MuscleGroup])] = []
    /// Already exclusion-filtered; computed off the main actor in `.task`.
    @State private var allowedSuggestions: [ExerciseTemplate] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if missing.isEmpty {
                        Text("You've hit every muscle group this week 💪")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("groupQuick.missing")
                    } else {
                        tierRow(String(localized: "Missing: "), tiers.missing, id: "groupQuick.missing")
                        tierRow(String(localized: "Below minimum: "), tiers.belowMinimum, id: "groupQuick.belowMinimum")
                        tierRow(String(localized: "Below recommended: "), tiers.belowRecommended, id: "groupQuick.belowRecommended")
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

                if !ranked.isEmpty {
                    Section("Repeat a past workout") {
                        ForEach(ranked.prefix(5), id: \.session.id) { item in
                            Button {
                                reuse(item.session)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.session.title.isEmpty ? String(localized: "Workout") : item.session.title)
                                        .font(.headline)
                                    Text(item.session.date.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(item.session.exercisesInOrder.map(\.name).joined(separator: ", "))
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Text(String(localized: "Covers: ") + item.covered.map(\.displayName).joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("groupQuick.past")
                        }
                    }
                }
            }
            .navigationTitle("Fill the Gaps")
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
        ranked = WorkoutRepository.workoutsByMissingCoverage(sessions, missing: missing)
        let picks = await Task.detached(priority: .userInitiated) {
            ExerciseLibrary.suggestions(forMissing: missing, limit: max(6, missing.count)) {
                SuggestedExerciseFilter.allows($0, keys: keys)
            }
        }.value
        allowedSuggestions = picks
    }

    @ViewBuilder
    private func tierRow(_ label: String, _ groups: [MuscleGroup], id: String) -> some View {
        if !groups.isEmpty {
            Text(label + groups.map(\.displayName).joined(separator: ", "))
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier(id)
        }
    }

    private func reuse(_ past: WorkoutSession) {
        guard let s = try? WorkoutRepository.reuseSession(from: past, in: context) else { return }
        startAfterDismiss(s)
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

    /// The destination is inside a NavigationStack. Starting the root
    /// full-screen cover in the same transaction as dismissing this destination
    /// can leave the new session active but the cover unapplied; Home then only
    /// shows it after a later navigation. Defer the start one main-actor turn.
    private func startAfterDismiss(_ session: WorkoutSession) {
        Haptics.selection()
        dismiss()
        Task { @MainActor in
            await Task.yield()
            onStart(session)
        }
    }
}
