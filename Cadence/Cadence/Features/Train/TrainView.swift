import SwiftUI
import SwiftData
import CadenceCore

/// Strength home (FR-1.1, 1.6, 1.7): start a new workout, start from a template,
/// and review/delete past sessions.
struct TrainView: View {
    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutModel.self) private var active
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \SessionTemplate.name) private var templates: [SessionTemplate]

    @State private var startedSession: WorkoutSession?
    @State private var templatesPresented = false
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

                    Button {
                        templatesPresented = true
                    } label: {
                        Label("Templates", systemImage: "square.stack.3d.up")
                    }
                    .accessibilityIdentifier("train.templates")
                }

                if !templates.isEmpty {
                    Section("Quick Start") {
                        ForEach(templates) { template in
                            Button {
                                startFromTemplate(template)
                            } label: {
                                HStack {
                                    Image(systemName: "bolt.fill").foregroundStyle(.orange)
                                    Text(template.name)
                                    Spacer()
                                    Text("\(template.orderedExercises.count) exercises")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("template.start.\(template.name)")
                        }
                    }
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
        .sheet(isPresented: $templatesPresented) {
            TemplatesView()
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

    private func startFromTemplate(_ template: SessionTemplate) {
        if let s = try? WorkoutRepository.startSession(from: template, in: context) {
            active.startStrength(s)
            startedSession = s
        }
    }
}
