import SwiftUI
import SwiftData
import CadenceCore

/// Quick-start that targets the body parts you haven't trained this week (feedback
/// batch 8 — tapping the Home "body parts" tile). It first lists your **past
/// workouts** ranked by how many of the missing parts they cover (tap → reuse it),
/// then offers a fresh session built from catalog **suggestions** that fill the gaps.
struct BodyPartQuickStartView: View {
    let missing: [BodyPart]
    /// Hands a ready-to-start session back to Home to launch (live) + dismiss.
    let onStart: (WorkoutSession) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    private var ranked: [(session: WorkoutSession, covered: [BodyPart])] {
        WorkoutRepository.workoutsByMissingCoverage(sessions, missing: missing)
    }
    private var suggestions: [ExerciseTemplate] {
        ExerciseLibrary.suggestions(forMissing: missing)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(missing.isEmpty
                         ? "You've hit every body part this week 💪"
                         : "Missing: " + missing.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("bodyQuick.missing")
                }

                if !ranked.isEmpty {
                    Section("Repeat a past workout") {
                        ForEach(ranked.prefix(5), id: \.session.id) { item in
                            Button {
                                reuse(item.session)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.session.title.isEmpty ? "Workout" : item.session.title)
                                        .font(.headline)
                                    Text("Covers: " + item.covered.map(\.displayName).joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("bodyQuick.past")
                        }
                    }
                }

                if !suggestions.isEmpty {
                    Section("Build from suggestions") {
                        ForEach(suggestions, id: \.id) { t in
                            HStack {
                                Text(t.name)
                                Spacer()
                                Text(ExerciseLibrary.bodyParts(of: t)
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
                        .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
                        .accessibilityIdentifier("bodyQuick.buildStart")
                    }
                }
            }
            .navigationTitle("Fill the Gaps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("bodyQuick.cancel")
                }
            }
        }
    }

    private func reuse(_ past: WorkoutSession) {
        guard let s = try? WorkoutRepository.reuseSession(from: past, in: context) else { return }
        Haptics.selection(); dismiss(); onStart(s)
    }

    private func buildFromSuggestions() {
        guard let s = try? WorkoutRepository.createSession(title: "Workout", in: context) else { return }
        s.plannedExerciseNames = suggestions.map(\.name)
        for name in suggestions { _ = try? WorkoutRepository.findOrCreateExercise(named: name.name, in: context) }
        try? context.save()
        Haptics.selection(); dismiss(); onStart(s)
    }
}
