import SwiftUI
import CadenceCore
import CadenceFeatures

/// Watch redesign §5 P3 — the Plan page (swipe left): today's exercises with their progress, tap to
/// jump to one, and Add exercise. Removing an exercise: long-press a row (or Set Card's More); row swipe
/// actions can't be reached on a page of a horizontal pager (the swipe turns the page).
struct WatchStrengthHomeView: View {
    let model: WatchStrengthFlowModel
    let onSelect: () -> Void
    @State private var pendingExerciseID: UUID?
    @State private var exerciseToRemove: Exercise?

    var body: some View {
        List {
            ForEach(model.exerciseList, id: \.exercise.persistentModelID) { item in
                Button {
                    WatchHaptics.tap()
                    pendingExerciseID = item.exercise.id
                    DispatchQueue.main.async {
                        model.startLogSet(for: item.exercise)
                        pendingExerciseID = nil
                        onSelect()
                    }
                } label: {
                    row(item.exercise, logged: item.setCount)
                }
                .buttonStyle(.plain)
                .listRowBackground(RoundedRectangle(cornerRadius: 12).fill(isCurrent(item.exercise) ? WatchTone.accentSoft : WatchTone.surface))
                .accessibilityIdentifier("watchStrength.exercise.\(item.exercise.name)")
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in
                    WatchHaptics.tap()
                    exerciseToRemove = item.exercise
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
        .navigationTitle(model.session?.title ?? String(localized: "Plan"))
        .alert("Remove \(exerciseToRemove?.name ?? "")?", isPresented: removeAlertBinding, presenting: exerciseToRemove) { exercise in
            Button("Remove", role: .destructive) {
                WatchHaptics.delete()
                if let payload = model.deleteExercise(exercise) { WatchSyncSender.send(payload) }
                exerciseToRemove = nil
            }
            Button("Keep", role: .cancel) { exerciseToRemove = nil }
        } message: { _ in
            Text("Its sets in this workout are removed too.")
        }
    }

    private var removeAlertBinding: Binding<Bool> {
        Binding(get: { exerciseToRemove != nil }, set: { if !$0 { exerciseToRemove = nil } })
    }

    private func row(_ exercise: Exercise, logged: Int) -> some View {
        let planned = model.plannedWorkingSets(for: exercise).count
        let done = model.completedWorkingSets(for: exercise)
        return HStack(spacing: 8) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.18), lineWidth: 3)
                if planned > 0 {
                    Circle().trim(from: 0, to: min(1, Double(done) / Double(planned)))
                        .stroke(WatchTone.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if planned > 0 && done >= planned {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(WatchTone.accent)
                }
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(exercise.name).font(.body).lineLimit(1)
                    if pendingExerciseID == exercise.id { ProgressView().controlSize(.mini) }
                }
                Text(detail(planned: planned, done: done, logged: logged)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func detail(planned: Int, done: Int, logged: Int) -> String {
        if planned > 0 { return String(localized: "\(done) of \(planned)") }
        return logged > 0 ? String(localized: "\(logged) logged") : String(localized: "Not started")
    }

    private func isCurrent(_ exercise: Exercise) -> Bool {
        if case .keypad(let current) = model.stage { return current.id == exercise.id }
        return false
    }
}
