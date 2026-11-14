import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Create & Add form for a custom exercise (explicit creation, never implicit).
struct WatchCustomExerciseForm: View {
    @Binding var name: String
    @Binding var attribution: WatchCustomExerciseMuscleAttribution
    let feedback: String?
    let onCreate: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Exercise name", text: $name)
                    .accessibilityIdentifier("watchCustom.name")

                muscleSection(title: "Primary Muscles", role: .primary, idPrefix: "primaryMuscleGroup")
                muscleSection(title: "Secondary Muscles", role: .secondary, idPrefix: "secondaryMuscleGroup")

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
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attribution.hasPrimaryMuscle)
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

extension WatchCustomExerciseForm {
    @ViewBuilder
    fileprivate func muscleSection(title: LocalizedStringKey,
                                   role: WatchCustomExerciseMuscleAttribution.Role,
                                   idPrefix: String) -> some View {
        let roleName = role == .primary ? "primary" : "secondary"
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
            ForEach(WatchCustomExerciseMuscleAttribution.availableGroups) { group in
                let selected = attribution.contains(group, as: role)
                Button {
                    WatchHaptics.tap()
                    attribution.toggle(group, as: role)
                } label: {
                    Text(group.displayName)
                        .font(.caption2.bold())
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(selected ? Color.green.opacity(0.35) : Color.white.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(group.displayName), \(roleName) \(selected ? "selected" : "not selected")")
                .accessibilityIdentifier("watchCustom.\(idPrefix).\(group.rawValue)")
            }
        }
    }
}

/// Exercise info screen: chevron + two-line title, Add, then a stable detail toggle.
struct WatchAddExercisePreview: View {
    let entry: ExerciseCatalogEntry
    let feedback: String?
    @Binding var showingDetail: Bool
    let onBack: () -> Void
    let onAdd: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header
                if let feedback {
                    Text(feedback)
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("watchAddExercise.feedback")
                }
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .accessibilityIdentifier("watchAddExercise.previewAdd")

                Button {
                    WatchHaptics.tap()
                    showingDetail.toggle()
                } label: {
                    Text(WatchAddExercisePresentation.detailToggleTitle(isExpanded: showingDetail))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(WatchAddExercisePresentation.detailToggleTitle(isExpanded: showingDetail))
                .accessibilityIdentifier("watchAddExercise.showDetail")

                if showingDetail,
                   let exercise = ExerciseCatalogSnapshot.exercise(id: entry.id, in: context) {
                    WatchExerciseDetailContent(exercise: exercise)
                }
            }
            .padding(.horizontal)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 4) {
            Button {
                WatchHaptics.tap()
                showingDetail = false
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: WatchAddExercisePresentation.minimumTouchHeight,
                           minHeight: WatchAddExercisePresentation.minimumTouchHeight,
                           alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WatchAddExercisePresentation.backAccessibilityLabel)
            .accessibilityIdentifier("watchAddExercise.previewChevron")

            Text(entry.name)
                .font(.headline)
                .lineLimit(WatchAddExercisePresentation.exerciseNameMaxLines)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: WatchAddExercisePresentation.minimumTouchHeight, alignment: .center)
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
