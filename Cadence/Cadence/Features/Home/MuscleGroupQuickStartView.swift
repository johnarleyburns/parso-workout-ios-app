import SwiftUI
import SwiftData
import CadenceCore

/// Quick-start that targets the muscle groups you haven't trained this week (feedback
/// batch 8 — tapping the Home "muscle groups" tile). It first lists your **past
/// workouts** ranked by how many of the missing groups they cover (tap → reuse it),
/// then offers a fresh session built from catalog **suggestions** that fill the gaps.
struct MuscleGroupQuickStartView: View {
    let missing: [MuscleGroup]
    /// Hands a ready-to-start session back to Home to launch (live) + dismiss.
    let onStart: (WorkoutSession) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    /// Computed once per history change, not on every body pass. Ranking walks
    /// every set of every past session, and the list used to evaluate it twice
    /// per render (the `isEmpty` check and the `ForEach`).
    @State private var ranked: [(session: WorkoutSession, covered: [MuscleGroup])] = []
    @State private var suggestions: [ExerciseTemplate] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(missing.isEmpty
                         ? String(localized: "You've hit every muscle group this week 💪")
                         : String(localized: "Missing: ") + missing.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("groupQuick.missing")
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
                                    Text(String(localized: "Covers: ") + item.covered.map(\.displayName).joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("groupQuick.past")
                        }
                    }
                }

                if !suggestions.isEmpty {
                    Section("Build from suggestions") {
                        ForEach(suggestions, id: \.id) { t in
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
            .navigationTitle("Fill the Gaps")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: sessions.count) {
                ranked = WorkoutRepository.workoutsByMissingCoverage(sessions, missing: missing)
                suggestions = ExerciseLibrary.suggestions(forMissing: missing)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("groupQuick.cancel")
                }
            }
        }
    }

    private func reuse(_ past: WorkoutSession) {
        guard let s = try? WorkoutRepository.reuseSession(from: past, in: context) else { return }
        startAfterDismiss(s)
    }

    private func buildFromSuggestions() {
        guard let s = try? WorkoutRepository.createSession(title: String(localized: "Workout"), in: context) else { return }
        s.plannedExerciseNames = suggestions.map(\.name)
        for name in suggestions { _ = try? WorkoutRepository.findOrCreateExercise(named: name.name, in: context) }
        try? context.save()
        startAfterDismiss(s)
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
