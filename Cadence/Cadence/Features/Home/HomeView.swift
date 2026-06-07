import SwiftUI
import SwiftData
import CadenceCore

/// Action-oriented launchpad (field-testing §01). Replaces the five-tab bar:
/// the hero is **Start Workout**; stats and history are one tap away. Apple
/// Health already mirrors raw activity, so Home is for *doing*, not a dashboard.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active

    @State private var typePickerPresented = false
    /// Push target for a strength session.
    @State private var startedSession: WorkoutSession?
    /// Sheet target for an indoor/timer cardio recording.
    @State private var cardioType: CardioType?
    /// Full-screen target for an outdoor GPS workout (field-testing §05).
    @State private var outdoorType: CardioType?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let session = active.strengthSession {
                        resumeCard(session)
                    }

                    startButton

                    secondaryGrid
                }
                .padding()
            }
            .navigationTitle("Cadence")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: HomeRoute.settings) {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityIdentifier("home.settings")
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(item: $startedSession) { session in
                SessionView(session: session)
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .stats: TrendsView()
                case .history: TrainView()
                case .cardio: CardioView()
                case .activity: TodayView()
                case .settings: SettingsView()
                }
            }
            .sheet(isPresented: $typePickerPresented) {
                WorkoutTypePicker { type in
                    typePickerPresented = false
                    start(type)
                }
            }
            .sheet(item: $cardioType) { type in
                RecordCardioView(initialType: type)
            }
            .fullScreenCover(item: $outdoorType) { type in
                OutdoorCardioView(type: type)
            }
        }
    }

    // MARK: Pieces

    private var startButton: some View {
        Button {
            typePickerPresented = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill").font(.largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start Workout").font(.title2.bold())
                    Text("Pick a type").font(.subheadline).opacity(0.9)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.headline).opacity(0.7)
            }
            .padding(.vertical, 22).padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .foregroundStyle(.white)
            .background(.tint, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.startWorkout")
        .accessibilityLabel("Start a workout")
    }

    private var secondaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)], spacing: 16) {
            navCard("Stats", "chart.xyaxis.line", route: .stats, id: "home.stats")
            navCard("History", "dumbbell", route: .history, id: "home.train")
            navCard("Cardio", "figure.run", route: .cardio, id: "home.cardio")
            navCard("Activity", "sun.max", route: .activity, id: "home.today")
        }
    }

    private func navCard(_ title: String, _ symbol: String, route: HomeRoute, id: String) -> some View {
        NavigationLink(value: route) {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.title)
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .padding(.vertical, 12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func resumeCard(_ session: WorkoutSession) -> some View {
        Button {
            startedSession = session
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional").font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume \(session.title.isEmpty ? "Workout" : session.title)")
                        .font(.headline)
                    Text("\(session.orderedSets.count) sets logged")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.resume")
    }

    // MARK: Routing

    private func start(_ type: WorkoutType) {
        if type.isStrength {
            if let session = try? WorkoutRepository.createSession(title: "Workout", in: context) {
                active.startStrength(session)
                startedSession = session
            }
        } else if type.usesGPS, let cardio = type.cardioType {
            outdoorType = cardio          // Run / Walk / Cycle → GPS screen (§05)
        } else if let cardio = type.cardioType {
            cardioType = cardio           // HIIT / Boxing / Other → timer screen
        }
    }
}

/// Pushed destinations reachable from Home (field-testing §01). Re-homes the old
/// tabs as navigation destinations rather than a tab bar.
enum HomeRoute: Hashable {
    case stats, history, cardio, activity, settings
}
