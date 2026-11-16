import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct HomeWorkoutStartControls: View {
    let onQuickStart: () -> Void
    let onSuggested: () -> Void
    let onPreviousStart: (EditablePlan) -> Void
    let onCardio: (WorkoutType) -> Void
    let onCustomCardio: (String, Bool) -> Void
    @State private var selection: Selection = .strength(.suggested)
    @State private var showingPrevious = false
    @State private var showingCustomCardio = false

    private enum Selection: Hashable {
        case strength(HomeStrengthStartChoice)
        case cardio(WorkoutType)

        var title: String {
            switch self {
            case .strength(.suggested): return String(localized: "Suggested Strength")
            case .strength(.previous): return String(localized: "Previous Strength")
            case .strength(.quickStart): return String(localized: "Custom Strength")
            case .cardio(.other): return String(localized: "Custom Cardio")
            case .cardio(let type): return type.displayName
            }
        }

        var symbol: String {
            switch self {
            case .strength(.suggested): return "wand.and.stars"
            case .strength(.previous): return "clock.arrow.circlepath"
            case .strength(.quickStart): return "dumbbell.fill"
            case .cardio(let type): return type.symbol
            }
        }
    }

    private var cardioChoices: [WorkoutType] {
        [.hiit] + WorkoutType.allCases.filter { $0 != .weights && $0 != .hiit }
    }

    var body: some View {
        VStack(spacing: 12) {
            Menu {
                Section {
                    choice(.strength(.suggested))
                    choice(.strength(.previous))
                    choice(.strength(.quickStart))
                }
                Section {
                    ForEach(cardioChoices) { type in choice(.cardio(type)) }
                }
            } label: {
                sourceLabel(selection.title)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Workout type")
            .accessibilityValue(selection.title)
            .accessibilityIdentifier("home.start.workoutSource")

            Button {
                switch selection {
                case .strength(.suggested): onSuggested()
                case .strength(.previous): showingPrevious = true
                case .strength(.quickStart): onQuickStart()
                case .cardio(.other): showingCustomCardio = true
                case .cardio(let type): onCardio(type)
                }
            } label: {
                Label("Start Workout", systemImage: "activity.exercise")
                    .cadenceActionLabel(alignment: .center)
            }
            .cadenceGlassButton(prominent: true, tint: CadenceTheme.accent)
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

    private func choice(_ option: Selection) -> some View {
        Button { selection = option } label: {
            Label(option.title, systemImage: option.symbol)
        }
        .accessibilityAddTraits(selection == option ? .isSelected : [])
    }

    private func sourceLabel(_ title: String) -> some View {
        HStack(spacing: 12) {
            Text(title)
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
    let onStart: (EditablePlan) -> Void
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    var body: some View {
        List {
            let previous = Array(sessions.lazy.filter(\.countsAsStrengthHistory).prefix(20))
            if previous.isEmpty { Text("No previous strength workouts yet.") }
            ForEach(previous) { session in
                NavigationLink {
                    WorkoutPlanEditor(plan: .from(session: session), onStart: onStart)
                } label: {
                    VStack(alignment: .leading) {
                        Text(session.title.isEmpty ? "Workout" : session.title)
                        Text(session.date.formatted(date: .abbreviated, time: .omitted)).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Previous")
    }
}
