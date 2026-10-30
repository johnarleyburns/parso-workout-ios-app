import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Create & Add form for a custom exercise (explicit creation, never implicit).
struct WatchCustomExerciseForm: View {
    @Binding var name: String
    @Binding var groups: Set<MuscleGroup>
    let feedback: String?
    let onCreate: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Exercise name", text: $name)
                    .accessibilityIdentifier("watchCustom.name")

                Text("Muscle groups")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(MuscleGroup.canonicalOrder) { group in
                        Button {
                            WatchHaptics.tap()
                            if groups.contains(group) { groups.remove(group) } else { groups.insert(group) }
                        } label: {
                            Text(group.displayName)
                                .font(.caption2.bold())
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(groups.contains(group) ? Color.green.opacity(0.35) : Color.white.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(group.displayName) \(groups.contains(group) ? "selected" : "not selected")")
                        .accessibilityIdentifier("watchCustom.muscleGroup.\(group.rawValue)")
                    }
                }

                if let feedback {
                    Text(feedback)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("watchAddExercise.feedback")
                }

                Button(action: onCreate) {
                    Label("Create & Add", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || groups.isEmpty)
                .accessibilityIdentifier("watchCustom.create")

                Button("Back") {
                    WatchHaptics.tap()
                    onBack()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("watchCustom.back")
            }
            .padding()
        }
    }
}

/// Explicit Details for a result row; its Add uses the same path as the row.
struct WatchAddExercisePreview: View {
    let entry: ExerciseCatalogEntry
    let feedback: String?
    @Binding var showingDetail: Bool
    let onBack: () -> Void
    let onAdd: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: showingDetail ? .leading : .center, spacing: 10) {
                if showingDetail {
                    if let exercise = ExerciseCatalogSnapshot.exercise(id: entry.id, in: context) {
                        WatchExerciseDetailContent(exercise: exercise)
                    }
                } else {
                    WatchMarqueeText(text: entry.name)
                        .padding(.top, 12)
                }
                quickActions
            }
            .padding(.horizontal)
            .padding(.bottom, showingDetail ? 0 : 28)
        }
    }

    private var quickActions: some View {
        VStack(spacing: 8) {
            if let feedback {
                Text(feedback)
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("watchAddExercise.feedback")
            }
            Button {
                WatchHaptics.tap()
                showingDetail = false
                onBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("watchAddExercise.previewBack")

            Button(action: onAdd) {
                Label("Add", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityIdentifier("watchAddExercise.previewAdd")

            Button {
                WatchHaptics.tap()
                showingDetail = true
            } label: {
                Text("Show Detail")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("watchAddExercise.showDetail")
        }
    }
}

/// Native Add/Cancel dialog plus the prominent outcome alert for Add Exercise.
struct WatchAddConfirmationModifier: ViewModifier {
    @Binding var confirmation: WatchAddConfirmation
    let onAdd: () -> Void
    let onViewWorkout: () -> Void
    let onRefresh: () -> Void

    private var outcomeTitle: String {
        switch confirmation.outcome {
        case .alreadyPresent: return String(localized: "Already in this workout")
        case .unavailable: return String(localized: "Exercise unavailable")
        case .saveFailed: return String(localized: "Couldn't save")
        case nil: return ""
        }
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Add \(confirmation.pending?.name ?? "exercise")?",
                isPresented: Binding(
                    get: { confirmation.pending != nil },
                    set: { if !$0 { confirmation.cancel() } }
                ),
                titleVisibility: .visible,
                presenting: confirmation.pending
            ) { _ in
                Button("Add") { onAdd() }
                    .accessibilityIdentifier("watchAddExercise.confirm.add")
                Button("Cancel", role: .cancel) { confirmation.cancel() }
                    .accessibilityIdentifier("watchAddExercise.confirm.cancel")
            } message: { target in
                Text("Add \(target.name) to this workout?")
            }
            .accessibilityIdentifier("watchAddExercise.confirm")
            .alert(
                outcomeTitle,
                isPresented: Binding(
                    get: { confirmation.outcome != nil },
                    set: { if !$0 { confirmation.dismissOutcome() } }
                ),
                presenting: confirmation.outcome
            ) { outcome in
                switch outcome {
                case .alreadyPresent:
                    Button("View workout") { confirmation.dismissOutcome(); onViewWorkout() }
                        .accessibilityIdentifier("watchAddExercise.viewWorkout")
                    Button("Choose another", role: .cancel) { confirmation.dismissOutcome() }
                case .unavailable:
                    Button("Refresh results") { onRefresh() }
                        .accessibilityIdentifier("watchAddExercise.refresh")
                    Button("Choose another", role: .cancel) { confirmation.dismissOutcome() }
                case .saveFailed:
                    Button("Try again") { confirmation.retry() }
                        .accessibilityIdentifier("watchAddExercise.retry")
                    Button("Cancel", role: .cancel) { confirmation.dismissOutcome() }
                }
            } message: { outcome in
                Text(outcome.message)
            }
    }
}
