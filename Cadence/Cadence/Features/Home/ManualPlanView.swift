import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Compact athlete-facing weekly planner. It intentionally owns a unified
/// value graph rather than adapting the legacy workout-plan presets into a
/// second persistence model.
struct ManualPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var appModel
    @State private var plan: Plan
    let onStart: (Session) -> Void

    @State private var sessionRoute: SessionRoute?
    @State private var didSave = false

    init(plan: Plan, onStart: @escaping (Session) -> Void) {
        self._plan = State(initialValue: plan)
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Plan name", text: $plan.title)
                        .accessibilityIdentifier("manualPlan.title")
                } header: {
                    Text("Plan")
                } footer: {
                    Text("Self-authored plans stay editable and sync through your private iCloud.")
                }

                Section("This week") {
                    ForEach(ManualPlanBuilder.mondayFirst, id: \.self) { weekday in
                        dayRow(weekday)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Build your week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        savePlan()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { savePlan() }
                        .fontWeight(.semibold)
                        .accessibilityIdentifier("manualPlan.save")
                }
            }
            .sheet(item: $sessionRoute) { route in
                ManualSessionEditorView(
                    session: route.session,
                    onSave: { edited in
                        replace(edited)
                        sessionRoute = nil
                        savePlan()
                    },
                    onStart: { edited in
                        replace(edited)
                        savePlan()
                        sessionRoute = nil
                        onStart(edited)
                    })
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ weekday: Weekday) -> some View {
        let sessions = plan.weeks.first?.days.first(where: { $0.weekday == weekday })?.sessions ?? []
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(weekday.displayName).font(.headline)
                Spacer()
                Button {
                    addSession(to: weekday)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add session on \(weekday.displayName)")
                .accessibilityIdentifier("manualPlan.addSession.\(weekday.rawValue)")
                .disabled(sessions.count >= 2)
            }

            if sessions.isEmpty {
                Text("Rest")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    Button { sessionRoute = SessionRoute(session: session) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: session.orderedItems.isEmpty ? "square.and.pencil" : "dumbbell.fill")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                    .foregroundStyle(.primary)
                                Text(sessionSummary(session))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("manualPlan.session.\(session.id.uuidString)")
                    .swipeActions {
                        Button(role: .destructive) { remove(session) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func sessionSummary(_ session: Session) -> String {
        let strength = session.orderedItems.compactMap { item -> StrengthItem? in
            guard case let .strength(value) = item else { return nil }
            return value
        }
        let sets = strength.reduce(0) { $0 + $1.sets.count }
        if strength.isEmpty { return "No items yet" }
        return "\(strength.count) exercise\(strength.count == 1 ? "" : "s") · \(sets) sets"
    }

    private func addSession(to weekday: Weekday) {
        var updated = plan
        let session = ManualPlanBuilder.strengthSession()
        guard (try? ManualPlanBuilder.addSession(session, to: weekday, in: &updated)) != nil else { return }
        plan = updated
        sessionRoute = SessionRoute(session: session)
    }

    private func replace(_ session: Session) {
        var updated = plan
        guard (try? ManualPlanBuilder.replaceSession(session, in: &updated)) != nil else { return }
        plan = updated
    }

    private func remove(_ session: Session) {
        var updated = plan
        guard (try? ManualPlanBuilder.removeSession(id: session.id, from: &updated)) != nil else { return }
        plan = updated
        savePlan()
    }

    private func savePlan() {
        guard !plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        plan.authoredOnIdiom = .compact
        plan.status = .active
        plan.updatedAt = Date()
        _ = try? UnifiedPlanStore.upsert(plan, originDevice: "iphone", in: context)
        _ = try? NormalizedPlanStore.upsert(plan, originDevice: "iphone", in: context)
        appModel.updateWatchTodayPlan(ManualPlanWatchBridge.todayPlan(
            from: plan,
            date: Date(),
            exerciseNameByKey: exerciseNamesByKey()))
        didSave = true
    }

    private func exerciseNamesByKey() -> [String: String] {
        ExerciseLibrary.starter.reduce(into: [:]) { result, exercise in
            if let sourceID = exercise.sourceExerciseID {
                result[sourceID] = exercise.name
            }
            result[ExerciseLibrary.lookupKey(exercise.name)] = exercise.name
        }
    }
}

private struct SessionRoute: Identifiable {
    let session: Session
    var id: UUID { session.id }
}
