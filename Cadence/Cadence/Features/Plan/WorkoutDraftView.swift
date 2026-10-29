import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

private struct RootTabSelectionKey: EnvironmentKey {
    static var defaultValue: Binding<RootTabView.Tab> { .constant(.home) }
}

extension EnvironmentValues {
    /// App-level tab selection, so Draft can return to Find without a nested sheet.
    var rootTabSelection: Binding<RootTabView.Tab> {
        get { self[RootTabSelectionKey.self] }
        set { self[RootTabSelectionKey.self] = newValue }
    }
}

extension Notification.Name {
    /// Carries an `EditablePlan` from the Workout Draft to Today's start flow.
    static let cadenceStartPlanningDraft = Notification.Name("cadence.startPlanningDraft")
}

/// The persistent, unscheduled Workout Draft. Every edit goes through
/// `PlanningDraftEditorModel`, which saves before publishing.
struct WorkoutDraftView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.rootTabSelection) private var rootTabSelection
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Person.name) private var people: [Person]
    @State private var model: PlanningDraftEditorModel?
    @State private var loadError: String?
    @State private var confirmDiscard = false
    @State private var schedulePresented = false
    /// Stable per sheet presentation so a retried or double-tapped save is idempotent.
    @State private var scheduleOperationID = UUID()
    @State private var titleText = ""

    var body: some View {
        Group {
            if let model { content(model) } else if let loadError {
                ContentUnavailableView("Couldn't open the draft", systemImage: "exclamationmark.triangle",
                                       description: Text(loadError))
            } else { ProgressView() }
        }
        .navigationTitle("Workout draft")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("planningDraft.root")
        .task {
            guard model == nil else { return }
            do {
                let created = try PlanningDraftEditorModel(drafts: PlanningDraftCoordinator.makeStore(),
                                                           context: context)
                titleText = created.plan.title
                model = created
            } catch { loadError = error.localizedDescription }
        }
        .onDisappear { model?.flush() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model?.flush() } }
    }

    private func content(_ model: PlanningDraftEditorModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(PlanningDraftEditorModel.statusText, systemImage: "checkmark.icloud")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("planningDraft.status")
                if let error = model.saveError { saveFailure(error, model) }
                titleField(model)
                partnerCard(model)
                if model.isEmpty {
                    ContentUnavailableView("No exercises yet", systemImage: "list.bullet.rectangle",
                                           description: Text(PlanningDraftEditorModel.emptyMessage))
                        .accessibilityIdentifier("planningDraft.empty")
                } else {
                    ForEach(Array(model.plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                        exerciseCard(exercise, index: index, model: model)
                    }
                }
                Button {
                    model.flush()
                    rootTabSelection.wrappedValue = .search
                    dismiss()
                } label: {
                    Label("Find exercises", systemImage: "plus.magnifyingglass")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("planningDraft.findExercises")
                Button("Discard draft", role: .destructive) {
                    if model.needsDiscardConfirmation { confirmDiscard = true } else { discard(model) }
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("planningDraft.discard")
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { actions(model) }
        .confirmationDialog("Discard this draft?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive) { discard(model) }
            Button("Keep draft", role: .cancel) {}
        } message: {
            Text("This removes \(model.exerciseCountText) from your unscheduled draft. It can't be undone.")
        }
        .sheet(isPresented: $schedulePresented) {
            ScheduleWorkoutSheet(title: model.plan.title) { date in
                _ = try PlanningDraftCoordinator.makeStore().schedule(
                    draftID: model.draft.id, for: date, operationID: scheduleOperationID, in: context)
                NotificationCenter.default.post(name: .scheduledWorkoutCreated, object: nil)
                dismiss()
            }
        }
    }

    private func saveFailure(_ error: String, _ model: PlanningDraftEditorModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Couldn't save your last change", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
            Text(error).font(.caption)
            Button("Retry save") { model.retrySave() }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                .accessibilityIdentifier("planningDraft.retrySave")
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planningDraft.saveError")
    }

    private func titleField(_ model: PlanningDraftEditorModel) -> some View {
        TextField("Workout title", text: $titleText)
            .textFieldStyle(.roundedBorder).font(.title3.weight(.semibold))
            .frame(minHeight: 44)
            .submitLabel(.done)
            .onChange(of: titleText) { _, text in
                if text != model.displayTitle { model.editTitle(text) }
            }
            .onSubmit { model.flush() }
            .accessibilityLabel("Workout title")
            .accessibilityIdentifier("planningDraft.title")
    }

    private func partnerCard(_ model: PlanningDraftEditorModel) -> some View {
        let partners = people.filter { !$0.isMe }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Training partners").font(.headline)
            if partners.isEmpty {
                Text("Solo. Add partners from the workout editor's roster.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(partners) { person in
                Toggle(person.name, isOn: Binding(
                    get: { model.plan.partnerIDs.contains(person.id) },
                    set: { on in setPartner(person, on: on, model) }))
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("planningDraft.partner.\(person.name)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planningDraft.partners")
    }

    private func setPartner(_ person: Person, on: Bool, _ model: PlanningDraftEditorModel) {
        var ids = model.plan.partnerIDs.filter { $0 != person.id }
        if on { ids.append(person.id) }
        let byID = Dictionary(people.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var roster = ids.compactMap { id -> PartnerPlanResolver.RosterMember? in
            guard let p = byID[id], !p.isMe else { return nil }
            return .init(performerID: p.id, name: p.name)
        }
        roster.insert(.init(performerID: nil, name: "Me"), at: 0)
        let index = WorkoutPlanPartnerHistory.Index(context: context)
        let all = people
        model.setPartners(ids, roster: roster) { name, performerID in
            index.history(forExerciseNamed: name, performerID: performerID, people: all)
        }
    }

    private func exerciseCard(_ exercise: EditableExercise, index: Int,
                              model: PlanningDraftEditorModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(exercise.name).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                iconButton("chevron.up", "Move \(exercise.name) up", "planningDraft.moveUp.\(index)",
                           enabled: model.canMove(id: exercise.id, by: -1)) {
                    model.moveExercise(id: exercise.id, by: -1)
                }
                iconButton("chevron.down", "Move \(exercise.name) down", "planningDraft.moveDown.\(index)",
                           enabled: model.canMove(id: exercise.id, by: 1)) {
                    model.moveExercise(id: exercise.id, by: 1)
                }
                iconButton("trash", "Remove \(exercise.name)", "planningDraft.remove.\(index)", enabled: true) {
                    model.removeExercise(id: exercise.id)
                }
            }
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { setIndex, set in
                DraftSetRow(set: set, number: setIndex + 1, unit: settings.unit,
                            canRemove: exercise.sets.count > 1,
                            identifier: "planningDraft.set.\(index).\(setIndex)",
                            onReps: { model.setReps(exerciseID: exercise.id, setID: set.id, reps: $0) },
                            onWeight: { model.setWeight(exerciseID: exercise.id, setID: set.id, weight: $0) },
                            onRemove: { model.removeSet(exerciseID: exercise.id, setID: set.id) })
            }
            Button { model.addSet(to: exercise.id) } label: {
                Label("Add set", systemImage: "plus").frame(minHeight: 44)
            }
            .accessibilityIdentifier("planningDraft.addSet.\(index)")
        }
        .padding().frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planningDraft.exercise.\(index)")
    }

    private func iconButton(_ symbol: String, _ label: String, _ id: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless).disabled(!enabled)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func actions(_ model: PlanningDraftEditorModel) -> some View {
        HStack(spacing: 12) {
            Button { model.flush(); scheduleOperationID = UUID(); schedulePresented = true } label: {
                Text("Schedule workout").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered).disabled(!model.canStartOrSchedule)
            .accessibilityIdentifier("planningDraft.schedule")
            Button { start(model) } label: {
                Text("Start now").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).disabled(!model.canStartOrSchedule)
            .accessibilityIdentifier("planningDraft.startNow")
        }
        .padding(.horizontal).padding(.vertical, 8).background(.bar)
    }

    /// Hands the plan to Today's start flow (HR gate, warm-up), then clears the
    /// draft because the plan is now the live workout.
    private func start(_ model: PlanningDraftEditorModel) {
        model.flush()
        let plan = model.plan
        rootTabSelection.wrappedValue = .home
        discard(model)
        Task { @MainActor in
            await Task.yield()
            NotificationCenter.default.post(name: .cadenceStartPlanningDraft, object: plan)
        }
    }

    private func discard(_ model: PlanningDraftEditorModel) {
        if model.discard() { dismiss() }
    }
}

/// One set's reps and load. Weight text is committed on submit/blur, not per keystroke.
private struct DraftSetRow: View {
    let set: EditableSet
    let number: Int
    let unit: MeasurementUnitPreference
    let canRemove: Bool
    let identifier: String
    let onReps: (Int) -> Void
    let onWeight: (Double?) -> Void
    let onRemove: () -> Void
    @State private var weightText = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            Stepper("Set \(number): \(set.targetReps) reps", value: Binding(
                get: { set.targetReps }, set: { onReps($0) }), in: 1...100)
            TextField(unit.abbreviation, text: $weightText)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(minWidth: 72, maxWidth: 96, minHeight: 44)
                .focused($focused)
                .onSubmit(commit)
                .accessibilityLabel("Set \(number) weight in \(unit.abbreviation)")
                .accessibilityIdentifier("\(identifier).weight")
            Button(role: .destructive, action: onRemove) {
                Image(systemName: "minus.circle.fill").frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless).disabled(!canRemove)
            .accessibilityLabel("Remove set \(number)")
            .accessibilityIdentifier("\(identifier).remove")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .onAppear(perform: load)
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .onDisappear(perform: commit)
    }

    private func load() {
        weightText = set.targetWeight.map { String(format: "%g", WorkoutMath.display($0, in: unit)) } ?? ""
    }

    private func commit() {
        let value = Double(weightText).map { WorkoutMath.canonical($0, from: unit) }
        let current = set.targetWeight
        guard value != current, !(value == nil && !weightText.isEmpty) else { return }
        onWeight(value)
    }
}
