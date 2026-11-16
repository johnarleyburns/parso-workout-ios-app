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
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Strength").font(.headline).accessibilityAddTraits(.isHeader)
                Menu {
                    Picker("Strength workout", selection: $strength) {
                        ForEach(HomeStrengthStartChoice.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    sourceLabel(strength.title)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Strength workout")
                .accessibilityValue(strength.title)
                .accessibilityIdentifier("home.start.strengthSource")

                Button {
                    switch strength {
                    case .quickStart: onQuickStart()
                    case .suggested: onSuggested()
                    case .previous: showingPrevious = true
                    }
                } label: {
                    Label("Start strength", systemImage: "dumbbell.fill")
                        .cadenceActionLabel(alignment: .center)
                }
                .cadenceGlassButton(prominent: true, tint: CadenceTheme.accent)
                .accessibilityIdentifier("home.start.strength")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Cardio").font(.headline).accessibilityAddTraits(.isHeader)
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
                    Button("More…", action: onMoreCardio)
                } label: {
                    sourceLabel(cardio?.displayName ?? String(localized: "More…"))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cardio workout")
                .accessibilityValue(cardio?.displayName ?? String(localized: "More…"))
                .accessibilityIdentifier("home.start.cardioSource")

                Button {
                    if let cardio { onCardio(cardio) } else { onMoreCardio() }
                } label: {
                    Label("Start cardio", systemImage: "figure.run")
                        .cadenceActionLabel(alignment: .center)
                }
                .cadenceGlassButton(prominent: true, tint: CadenceTheme.accent)
                .accessibilityIdentifier("home.start.cardio")
            }
        }
        .glassGroup(spacing: 12)
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
