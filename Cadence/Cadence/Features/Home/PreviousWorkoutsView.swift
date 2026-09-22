import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct PreviousWorkoutsView: View {
    let onEditorStart: (EditablePlan) -> Void

    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    private var previous: [WorkoutSession] {
        Array(sessions.filter { !$0.orderedSets.isEmpty && $0.deletedAt == nil }.prefix(20))
    }

    var body: some View {
        List {
            if previous.isEmpty {
                ContentUnavailableView("No previous workouts", systemImage: "clock.arrow.circlepath",
                                       description: Text("Complete a strength workout to reuse it as a template."))
            } else {
                ForEach(previous) { session in
                    NavigationLink {
                        WorkoutPlanEditor(plan: .from(session: session), onStart: onEditorStart)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title.isEmpty ? "Previous Workout" : session.title)
                                .font(.headline)
                            Text("\(session.date.formatted(date: .abbreviated, time: .omitted)) · \(session.exercisesInOrder.count) exercises · \(session.orderedSets.count) sets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("selectWorkout.previous")
                    .accessibilityValue(session.id.uuidString)
                }
            }
        }
        .navigationTitle("Previous Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("selectWorkout.previousList")
    }
}
