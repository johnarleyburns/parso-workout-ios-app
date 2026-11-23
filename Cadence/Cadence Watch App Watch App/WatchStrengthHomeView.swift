import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Watch redesign §5 P3 — the Plan page (swipe left): today's exercises with their progress, tap to
/// jump to one, and Add exercise. Removing an exercise: long-press a row (or Set Card's More); row swipe
/// actions can't be reached on a page of a horizontal pager (the swipe turns the page).
struct WatchStrengthHomeView: View {
    let model: WatchStrengthFlowModel
    let onSelect: () -> Void
    @State private var pendingExerciseID: UUID?
    @State private var exerciseToRemove: Exercise?
    /// Set when a long-press fires so the button's tap on finger-lift doesn't also navigate away.
    @State private var longPressHandled = false
    @State private var toastAddedName: String?

    var body: some View {
        planList
    }

    private var planList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Exercises")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .accessibilityAddTraits(.isHeader)
            planItems
        }
        .navigationBarHidden(true)
        // Transient toast instead of a List row: a conditionally-inserted row
        // shifted the whole exercise list up/down whenever an exercise was
        // added, which read as a layout "flash." Mirrors the Set Card's
        // "last time" toast (WatchSetKeypadView.swift).
        .overlay(alignment: .top) {
            if let toastAddedName {
                Button {
                    model.lastAddedExerciseName = nil
                    withAnimation { self.toastAddedName = nil }
                } label: {
                    Label("Added \(toastAddedName)", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.regularMaterial))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
                .accessibilityIdentifier("watchStrength.exerciseAdded")
                .accessibilityHint("Double tap to dismiss")
            }
        }
        .task(id: model.lastAddedExerciseName) {
            guard let added = model.lastAddedExerciseName else { toastAddedName = nil; return }
            withAnimation { toastAddedName = added }
            AccessibilityNotification.Announcement("Added \(added)").post()
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            model.lastAddedExerciseName = nil
            withAnimation { toastAddedName = nil }
        }
    }

    private var planItems: some View {
        List {
            ForEach(model.exerciseList, id: \.exercise.persistentModelID) { item in
                Button {
                    if longPressHandled { longPressHandled = false; return }
                    WatchHaptics.tap()
                    pendingExerciseID = item.exercise.id
                    DispatchQueue.main.async {
                        model.startLogSet(for: item.exercise)
                        pendingExerciseID = nil
                        onSelect()
                    }
                } label: {
                    row(item.exercise)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("watchStrength.exercise.\(item.exercise.name)")
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                    WatchHaptics.tap()
                    longPressHandled = true
                    exerciseToRemove = item.exercise
                    // If no tap follows the long-press, don't swallow the user's next real tap.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { longPressHandled = false }
                })
                .accessibilityAction(named: Text("Remove exercise")) { exerciseToRemove = item.exercise }
            }

            Button {
                WatchHaptics.tap()
                model.goToAddExercise()
                onSelect()
            } label: {
                Label("Add exercise", systemImage: "plus")
            }
            .accessibilityIdentifier("watchStrength.addExercise")
        }
        .alert("Remove \(exerciseToRemove?.name ?? "")?", isPresented: removeAlertBinding, presenting: exerciseToRemove) { exercise in
            Button("Remove exercise and its sets", role: .destructive) {
                WatchHaptics.delete()
                if let payload = model.deleteExercise(exercise) { WatchSyncSender.send(payload) }
                exerciseToRemove = nil
            }
            Button("Keep", role: .cancel) { exerciseToRemove = nil }
        }
    }

    private var removeAlertBinding: Binding<Bool> {
        Binding(get: { exerciseToRemove != nil }, set: { if !$0 { exerciseToRemove = nil } })
    }

    private func row(_ exercise: Exercise) -> some View {
        let presentation = WatchWorkoutExerciseRowPresentation(
            exerciseName: exercise.name,
            completedSetCount: model.completedWorkingSets(for: exercise),
            plannedSetCount: model.plannedWorkingSets(for: exercise).count
        )
        return HStack(spacing: 8) {
            WatchExerciseProgressRing(presentation: presentation)
            HStack(spacing: 4) {
                Text(exercise.name.localizedExerciseName)
                    .font(.body)
                    .lineLimit(presentation.exerciseNameMaxLines, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if pendingExerciseID == exercise.id { ProgressView().controlSize(.mini) }
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 12)
            .fill(isCurrent(exercise) ? WatchTone.accentSoft : WatchTone.surface))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func isCurrent(_ exercise: Exercise) -> Bool {
        if case .keypad(let current) = model.stage { return current.id == exercise.id }
        return false
    }
}
