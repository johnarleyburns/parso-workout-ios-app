import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct ManualSessionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session: Session
    let onSave: (Session) -> Void
    let onStart: (Session) -> Void
    @State private var itemRoute: ItemRoute?

    init(session: Session, onSave: @escaping (Session) -> Void,
         onStart: @escaping (Session) -> Void) {
        self._session = State(initialValue: session)
        self.onSave = onSave
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Session name", text: $session.title)
                        .accessibilityIdentifier("manualSession.title")
                }

                Section("Items") {
                    if session.orderedItems.isEmpty {
                        Text("Add items to build this session.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.orderedItems, id: \.id) { item in
                        Button { itemRoute = ItemRoute(item: item) } label: {
                            HStack {
                                Image(systemName: itemIcon(item)).foregroundStyle(.tint)
                                Text(itemTitle(item))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { index in
                            session.orderedItems.indices.contains(index) ? session.orderedItems[index].id : nil
                        }
                        session.items.removeAll { ids.contains($0.id) }
                    }
                    Button { addStrengthItem() } label: {
                        Label("Add strength", systemImage: "dumbbell.fill")
                    }
                    .accessibilityIdentifier("manualSession.addStrength")
                    Button { addCardioItem() } label: {
                        Label("Add cardio", systemImage: "figure.run")
                    }
                    .accessibilityIdentifier("manualSession.addCardio")
                    Button { addMobilityItem() } label: {
                        Label("Add mobility", systemImage: "figure.flexibility")
                    }
                    .accessibilityIdentifier("manualSession.addMobility")
                    Button { addInstructionItem() } label: {
                        Label("Add instruction", systemImage: "text.alignleft")
                    }
                    .accessibilityIdentifier("manualSession.addInstruction")
                }

                Section {
                    Button {
                        onStart(session)
                    } label: {
                        Label("Start this session", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canStart)
                    .accessibilityIdentifier("manualSession.start")
                } footer: {
                    Text(session.executionBoundary.userFacingDescription)
                }
            }
            .navigationTitle("Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(session)
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("manualSession.done")
                }
            }
            .sheet(item: $itemRoute) { route in
                switch route.item {
                case let .strength(item):
                    ManualStrengthItemEditor(item: item) { edited in
                        replace(edited)
                        itemRoute = nil
                    }
                case let .cardio(item):
                    ManualCardioItemEditor(item: item) { edited in
                        replace(edited)
                        itemRoute = nil
                    }
                case let .mobility(item):
                    ManualMobilityItemEditor(item: item) { edited in
                        replace(edited)
                        itemRoute = nil
                    }
                case let .instruction(item):
                    ManualInstructionItemEditor(item: item) { edited in
                        replace(edited)
                        itemRoute = nil
                    }
                }
            }
        }
    }

    private var canStart: Bool {
        session.executionBoundary.canStartStrengthRunner ||
            session.executionBoundary.canStartCombinedRunner
    }

    private func itemIcon(_ item: WorkoutItem) -> String {
        switch item {
        case .strength: return "dumbbell.fill"
        case .cardio: return "figure.run"
        case .mobility: return "figure.flexibility"
        case .instruction: return "text.alignleft"
        }
    }

    private func itemTitle(_ item: WorkoutItem) -> String {
        switch item {
        case let .strength(value):
            return value.exerciseKey.raw.replacingOccurrences(of: "_", with: " ").capitalized
        case let .cardio(value):
            switch value.prescription {
            case let .steadyState(details): return cardioActivityName(details.activity)
            case let .intervals(details): return "\(cardioActivityName(details.activity)) intervals"
            case let .open(details): return cardioActivityName(details.activity)
            }
        case let .mobility(value):
            return value.name
        case let .instruction(value):
            return value.text
        }
    }

    private func addStrengthItem() {
        let order = nextItemOrder
        let item = ManualPlanBuilder.strengthItem(exerciseKey: "back_squat", order: order)
        session.items.append(.strength(item))
        itemRoute = ItemRoute(item: .strength(item))
    }

    private func addCardioItem() {
        let item = CardioItem(
            order: nextItemOrder,
            prescription: .steadyState(SteadyState(
                activity: .run,
                durationSeconds: 20 * 60,
                intensity: .heartRateZone(2))))
        session.items.append(.cardio(item))
        itemRoute = ItemRoute(item: .cardio(item))
    }

    private func addMobilityItem() {
        let item = MobilityItem(order: nextItemOrder,
                                name: "Mobility flow",
                                rounds: 2,
                                perRound: .duration(seconds: 30))
        session.items.append(.mobility(item))
        itemRoute = ItemRoute(item: .mobility(item))
    }

    private func addInstructionItem() {
        let item = InstructionItem(order: nextItemOrder,
                                   text: "Add a note for this session.")
        session.items.append(.instruction(item))
        itemRoute = ItemRoute(item: .instruction(item))
    }

    private func replace(_ item: WorkoutItem) {
        guard let index = session.items.firstIndex(where: { $0.id == item.id }) else { return }
        session.items[index] = item
    }

    private var nextItemOrder: Int {
        (session.items.map(\.order).max() ?? -1) + 1
    }
}

struct ItemRoute: Identifiable {
    let item: WorkoutItem
    var id: UUID { item.id }

}
