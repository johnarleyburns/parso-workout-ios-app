import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceApp: App {
    let container: ModelContainer = {
        do { return try CadenceStore.makeModelContainer() }
        catch { fatalError("Failed to create ModelContainer: \(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            SessionListView()
        }
        .modelContainer(container)
    }
}

// Phone = review hub (read-only for MVP). FR-5 / UC-8 build on this later.
struct SessionListView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    var body: some View {
        NavigationStack {
            List(sessions) { session in
                NavigationLink {
                    SessionDetailView(session: session)
                } label: {
                    VStack(alignment: .leading) {
                        Text(session.title.isEmpty ? "Workout" : session.title)
                        Text(session.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Cadence")
            .overlay {
                if sessions.isEmpty {
                    ContentUnavailableView("No workouts yet",
                                           systemImage: "dumbbell",
                                           description: Text("Log a set on your Watch — it'll appear here."))
                }
            }
        }
    }
}

struct SessionDetailView: View {
    let session: WorkoutSession

    var body: some View {
        List(session.orderedSets) { set in
            HStack {
                Text(set.exercise?.name ?? "Exercise")
                Spacer()
                Text("\(set.weight, specifier: "%.1f") × \(set.reps)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .omitted))
    }
}
