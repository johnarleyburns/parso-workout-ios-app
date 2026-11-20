import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// The inline workout list on Today. Field testing moved this out of a popup
/// and removed its Start button: tapping a row starts that workout directly,
/// exactly like the Watch launcher. Rows use a warm, semantic palette instead
/// of the previous all-grey treatment.
struct HomeWorkoutStartControls: View {
    let onSuggested: () -> Void
    let onCardio: (WorkoutType) -> Void
    let onCustomCardio: (String, Bool) -> Void
    let onSuggestedCardio: () -> Void
    @State private var showingCustomCardio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start a workout")
                .font(.headline)
            VStack(spacing: 0) {
                ForEach(Array(HomeWorkoutStartChoice.allChoices.enumerated()), id: \.element.id) { index, option in
                    if index > 0 { Divider().padding(.leading, 52) }
                    row(option)
                }
            }
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard()
        .sheet(isPresented: $showingCustomCardio) {
            NavigationStack {
                OtherCardioEntryView { description, gps in
                    showingCustomCardio = false
                    onCustomCardio(description, gps)
                }
            }
        }
        .accessibilityIdentifier("home.start.workoutList")
    }

    private func row(_ option: HomeWorkoutStartChoice) -> some View {
        Button {
            Haptics.selection()
            start(option)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: option.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint(for: option))
                    .frame(width: 34, height: 34)
                    .background(tint(for: option).opacity(0.14), in: Circle())
                Text(LocalizedStringKey(option.title))
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 48)
            .background(tint(for: option).opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.start.\(option.id)")
        .accessibilityHint("Starts \(option.title)")
    }

    private func start(_ option: HomeWorkoutStartChoice) {
        switch option {
        case .strength(.suggested):
            onSuggested()
        case .cardio(.other):
            showingCustomCardio = true
        case .cardio(let type):
            onCardio(type)
        case .suggestedCardio:
            onSuggestedCardio()
        }
    }

    /// Warm strength green, cardio coral/teal, and suggestion amber. These are
    /// intentional role colors, all backed by system colors for dark mode and
    /// Increase Contrast.
    private func tint(for option: HomeWorkoutStartChoice) -> Color {
        switch option {
        case .strength, .cardio(.weights): return .green
        case .suggestedCardio: return .orange
        case .cardio(.hiit), .cardio(.boxing): return .red
        case .cardio(.swim): return .teal
        case .cardio(.rowing): return .blue
        case .cardio(.cycle), .cardio(.elliptical), .cardio(.stairClimber): return .indigo
        case .cardio(.run), .cardio(.walk): return .orange
        case .cardio(.other): return .pink
        }
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
        .navigationTitle("Previous")
        .sheet(item: $selectedPlan) { plan in
            NavigationStack {
                WorkoutPlanEditor(plan: plan, onStart: onStart)
            }
        }
    }
}
