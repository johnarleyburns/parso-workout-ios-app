import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct HomeWorkoutStartControls: View {
    let onQuickStart: () -> Void
    let onSuggested: () -> Void
    let onPreviousStart: (EditablePlan) -> Void
    let onCardio: (WorkoutType) -> Void
    let onCustomCardio: (String, Bool) -> Void
    let onSuggestedCardio: () -> Void
    @AppStorage(HomeWorkoutStartChoice.selectionStorageKey)
    private var selectedChoiceID = HomeWorkoutStartChoice.defaultChoice.id

    private var selection: HomeWorkoutStartChoice {
        get { HomeWorkoutStartChoice.restored(from: selectedChoiceID) }
        nonmutating set { selectedChoiceID = newValue.id }
    }
    @State private var showingPrevious = false
    @State private var showingCustomCardio = false

    var body: some View {
        VStack(spacing: 12) {
            Menu {
                Section {
                    ForEach(HomeWorkoutStartChoice.strengthChoices) { choice($0) }
                }
                Section {
                    ForEach(HomeWorkoutStartChoice.cardioChoices) { choice($0) }
                }
            } label: {
                sourceLabel(selection.title)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Workout type")
            .accessibilityValue(Text(LocalizedStringKey(selection.title)))
            .accessibilityIdentifier("home.start.workoutSource")

            Button {
                switch selection {
                case .strength(.suggested): onSuggested()
                case .strength(.previous): showingPrevious = true
                case .strength(.quickStart): onQuickStart()
                case .cardio(.other): showingCustomCardio = true
                case .cardio(let type): onCardio(type)
                case .suggestedCardio: onSuggestedCardio()
                }
            } label: {
                Label("Start Workout", systemImage: "activity.exercise")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .cadenceGlassButton(prominent: true, tint: Color(red: 0.08, green: 0.38, blue: 0.16))
            .accessibilityIdentifier("home.start.workout")
        }
        .glassGroup(spacing: 12)
        .sheet(isPresented: $showingPrevious) {
            NavigationStack {
                HomePreviousStrengthWorkouts { plan in
                    showingPrevious = false
                    onPreviousStart(plan)
                }
            }
        }
        .sheet(isPresented: $showingCustomCardio) {
            NavigationStack {
                OtherCardioEntryView { description, gps in
                    showingCustomCardio = false
                    onCustomCardio(description, gps)
                }
            }
        }
    }

    private func choice(_ option: HomeWorkoutStartChoice) -> some View {
        Button { selection = option } label: {
            Label(LocalizedStringKey(option.title), systemImage: option.symbol)
        }
        .accessibilityAddTraits(selection == option ? .isSelected : [])
    }

    private func sourceLabel(_ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: selection.symbol)
            Text(LocalizedStringKey(title))
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.up.chevron.down")
                .foregroundStyle(.secondary)
        }
        .font(.body.weight(.semibold))
        .padding(.horizontal, 20)
        .frame(minHeight: CGFloat(LayoutMetrics.actionButtonHeight))
        .contentShape(Capsule())
        .cadenceGlass(in: Capsule(), interactive: true)
    }

}

struct HomePreviousStrengthWorkouts: View {
    @State private var selectedPlan: EditablePlan?
    let onStart: (EditablePlan) -> Void
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    var body: some View {
        List {
            let previous = Array(sessions.lazy.filter(\.countsAsStrengthHistory).prefix(20))
            if previous.isEmpty { Text("No previous strength workouts yet.") }
            ForEach(previous) { session in
                Button { selectedPlan = .from(session: session) } label: {
                    VStack(alignment: .leading) {
                        Text(session.title.isEmpty ? "Workout" : session.title)
                        Text(session.date.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Repeat Lifts")
        .sheet(item: $selectedPlan) { plan in
            NavigationStack {
                WorkoutPlanEditor(plan: plan, onStart: onStart)
            }
        }
    }
}
