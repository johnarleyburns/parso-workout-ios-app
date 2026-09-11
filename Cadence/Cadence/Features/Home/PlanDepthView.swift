import SwiftUI
import CadenceCore
import CadenceFeatures

/// The Phase 3 self-planning controls. Operations materialize ordinary plan
/// weeks and sessions through `UnifiedPlanAuthoring`; there is no second plan
/// representation and no hidden automatic mutation.
struct PlanDepthView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var plan: Plan
    let onApply: (Plan) -> Void

    @State private var mesocycleWeeks = 4
    @State private var periodization: PeriodizationModel = .accumulationIntensificationDeload
    @State private var progression: ProgressionIntent = .doubleProgression
    @State private var repeatCount = 1
    @State private var selectedSourceID: UUID?
    @State private var selectedWeekdays: Set<Weekday> = []
    @State private var message: String?

    init(plan: Plan, onApply: @escaping (Plan) -> Void) {
        self._plan = State(initialValue: plan)
        self.onApply = onApply
    }

    private var sessions: [SessionChoice] {
        plan.weeks.first?.days.flatMap { day in
            day.sessions.map { SessionChoice(session: $0, weekday: day.weekday) }
        } ?? []
    }

    private var selectedSource: SessionChoice? {
        sessions.first { $0.id == selectedSourceID } ?? sessions.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Weeks: \(mesocycleWeeks)", value: $mesocycleWeeks, in: 2...12)
                    Picker("Periodization", selection: $periodization) {
                        ForEach(periodizationOptions, id: \.0.rawValue) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    Picker("Progression", selection: $progression) {
                        ForEach(progressionOptions, id: \.0.rawValue) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    Button("Build \(mesocycleWeeks)-week mesocycle") {
                        buildMesocycle()
                    }
                    .accessibilityIdentifier("planDepth.buildMesocycle")
                } header: {
                    Text("Mesocycle")
                } footer: {
                    Text("The source week is copied with fresh session, item, and set identities. The final week becomes a deload for the accumulation/intensification/deload model.")
                }

                Section {
                    if sessions.isEmpty {
                        Text("Add a session before repeating it.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Source", selection: Binding(
                            get: { selectedSourceID ?? sessions[0].id },
                            set: { selectedSourceID = $0 })) {
                            ForEach(sessions) { choice in
                                Text("\(choice.weekday.displayName) · \(choice.session.title)")
                                    .tag(choice.id)
                            }
                        }

                        Text("Target days")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(ManualPlanBuilder.mondayFirst, id: \.self) { weekday in
                            Button {
                                toggle(weekday)
                            } label: {
                                HStack {
                                    Text(weekday.displayName)
                                    Spacer()
                                    if selectedWeekdays.contains(weekday) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Repeat on selected days") {
                            repeatSession()
                        }
                        .disabled(selectedWeekdays.isEmpty)
                        .accessibilityIdentifier("planDepth.repeatSession")
                    }
                } header: {
                    Text("Repeat a session")
                } footer: {
                    Text("Each copy gets fresh execution identity. The existing two-sessions-per-day safety limit remains enforced.")
                }

                Section {
                    Stepper("Additional weeks: \(repeatCount)", value: $repeatCount, in: 1...12)
                    Button("Append repeated weeks") {
                        repeatWeek()
                    }
                    .accessibilityIdentifier("planDepth.repeatWeek")
                } header: {
                    Text("Repeat a week")
                } footer: {
                    Text("Repeated weeks preserve the source prescription and apply the selected progression where the model supports it.")
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Plan depth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if selectedSourceID == nil { selectedSourceID = sessions.first?.id }
                if selectedWeekdays.isEmpty, let source = sessions.first {
                    selectedWeekdays = [nextWeekday(after: source.weekday)]
                }
            }
        }
    }

    private var periodizationOptions: [(PeriodizationModel, String)] {
        [
            (.accumulationIntensificationDeload, "Accumulation → intensification → deload"),
            (.linear, "Linear"),
            (.dailyUndulating, "Daily undulating"),
            (.block, "Block"),
            (.none, "None")
        ]
    }

    private var progressionOptions: [(ProgressionIntent, String)] {
        [
            (.doubleProgression, "Double progression"),
            (.linearLoad, "Linear load"),
            (.percentageBased, "Percentage-based"),
            (.autoregulated, "Autoregulated"),
            (.volume, "Volume")
        ]
    }

    private func buildMesocycle() {
        do {
            plan = try UnifiedPlanAuthoring.mesocycle(
                from: plan, weeks: mesocycleWeeks,
                periodization: periodization, progression: progression)
            onApply(plan)
            message = "Saved \(mesocycleWeeks)-week mesocycle."
        } catch {
            message = "Could not build mesocycle: \(error.localizedDescription)"
        }
    }

    private func repeatSession() {
        guard let source = selectedSource else { return }
        do {
            try UnifiedPlanAuthoring.repeatSession(
                id: source.session.id, on: selectedWeekdays, in: &plan)
            onApply(plan)
            message = "Repeated \(source.session.title) on the selected days."
        } catch {
            message = "Could not repeat session: \(error.localizedDescription)"
        }
    }

    private func repeatWeek() {
        do {
            try UnifiedPlanAuthoring.repeatWeek(
                count: repeatCount, in: &plan, progression: progression)
            onApply(plan)
            message = "Appended \(repeatCount) repeated week\(repeatCount == 1 ? "" : "s")."
        } catch {
            message = "Could not repeat week: \(error.localizedDescription)"
        }
    }

    private func toggle(_ weekday: Weekday) {
        if selectedWeekdays.contains(weekday) {
            selectedWeekdays.remove(weekday)
        } else {
            selectedWeekdays.insert(weekday)
        }
    }

    private func nextWeekday(after weekday: Weekday) -> Weekday {
        let ordered = ManualPlanBuilder.mondayFirst
        guard let index = ordered.firstIndex(of: weekday) else { return .tuesday }
        return ordered[(index + 1) % ordered.count]
    }
}

private struct SessionChoice: Identifiable {
    let session: Session
    let weekday: Weekday
    var id: UUID { session.id }
}
