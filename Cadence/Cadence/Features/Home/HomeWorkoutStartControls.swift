import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct HomeWorkoutStartControls: View {
    let recentCardio: [WorkoutType]
    let onQuickStart: () -> Void
    let onSuggested: () -> Void
    let onPreviousStart: (EditablePlan) -> Void
    let onCardio: (WorkoutType) -> Void
    let onMoreCardio: () -> Void
    @State private var strength: HomeStrengthStartChoice = .quickStart
    @State private var cardio: WorkoutType?
    @State private var showingPrevious = false

    var body: some View {
        VStack(spacing: 12) {
            Picker("Strength workout", selection: $strength) {
                ForEach(HomeStrengthStartChoice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            Button {
                switch strength {
                case .quickStart: onQuickStart()
                case .suggested: onSuggested()
                case .previous: showingPrevious = true
                }
            } label: { Label("Strength", systemImage: "dumbbell.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
            Menu {
                ForEach(HomeRecentCardioChoices.recent(recentCardio)) { type in
                    Button { cardio = type } label: {
                        if cardio == type {
                            Label(type.displayName, systemImage: "checkmark")
                        } else {
                            Text(type.displayName)
                        }
                    }
                }
                Button("More..", action: onMoreCardio)
            } label: {
                HStack {
                    Text(cardio?.displayName ?? "More..")
                    Image(systemName: "chevron.up.chevron.down")
                }
            }
            .accessibilityLabel("Cardio workout")
            Button {
                if let cardio { onCardio(cardio) } else { onMoreCardio() }
            } label: { Label("Cardio", systemImage: "figure.run").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
        }
        .onAppear { cardio = HomeRecentCardioChoices.recent(recentCardio).first }
        .sheet(isPresented: $showingPrevious) {
            NavigationStack {
                HomePreviousStrengthWorkouts { plan in
                    showingPrevious = false
                    onPreviousStart(plan)
                }
            }
        }
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
