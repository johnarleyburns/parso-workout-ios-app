import SwiftUI
import SwiftData
import CadenceCore

/// Strength home / history (FR-1.1, 1.7; field-testing §04). Start a new workout,
/// reuse a past one fresh (decision #16 — templates retired), and review/delete
/// past sessions.
struct TrainView: View {
    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var startedSession: WorkoutSession?
    @State private var sessionToDelete: WorkoutSession?

    var body: some View {
        List {
            Section {
                Button {
                    startEmptySession()
                } label: {
                    Label("New Workout", systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("train.newWorkout")
            }

            Section("History") {
                if sessions.isEmpty {
                    Text("No workouts yet — tap New Workout.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions) { session in
                    Button { startedSession = session } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title.isEmpty ? "Workout" : session.title)
                            Text(session.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(session.orderedSets.count) sets · \(Format.weightValue(session.totalVolume, unit: .kilograms)) kg volume")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("session.row")
                    .swipeActions(edge: .leading) {
                        Button {
                            reuse(session)
                        } label: { Label("Reuse", systemImage: "arrow.clockwise") }
                            .tint(.blue)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            sessionToDelete = session
                        } label: { Label("Delete", systemImage: "trash") }
                    }
                }
            }
        }
        .navigationTitle("Train")
        .navigationDestination(item: $startedSession) { session in
            SessionView(session: session)
        }
        .confirmationDialog("Delete this workout?",
                            isPresented: Binding(get: { sessionToDelete != nil },
                                                 set: { if !$0 { sessionToDelete = nil } }),
                            presenting: sessionToDelete) { session in
            Button("Delete", role: .destructive) {
                try? WorkoutRepository.deleteSession(session, in: context)
                sessionToDelete = nil
            }
        } message: { _ in Text("This removes the session and its sets.") }
    }

    private func startEmptySession() {
        if let s = try? WorkoutRepository.createSession(title: "Workout", in: context) {
            active.startStrength(s)
            startedSession = s
        }
    }

    /// Start a fresh session pre-loaded with a past workout's exercises
    /// (field-testing §04, decision #16).
    private func reuse(_ past: WorkoutSession) {
        if let s = try? WorkoutRepository.reuseSession(from: past, in: context) {
            active.startStrength(s)
            startedSession = s
        }
    }
}
