import SwiftUI
import SwiftData
import CadenceCore

@main
struct CadenceWatchApp: App {
    let container: ModelContainer = {
        do { return try CadenceStore.makeModelContainer() }
        catch { fatalError("Failed to create ModelContainer: \(error)") }
    }()

    var body: some Scene {
        WindowGroup {
            QuickLogView()
        }
        .modelContainer(container)
    }
}

// Watch = primary in-workout surface. MVP version of FR-8.2 / UC-10.
// Deliberately crude: Steppers now, Digital Crown polish later.
struct QuickLogView: View {
    @Environment(\.modelContext) private var context
    @Query private var sessions: [WorkoutSession]

    @State private var exerciseName = "Bench Press"
    @State private var weight: Double = 60
    @State private var reps: Int = 5
    @State private var justLogged = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text(exerciseName).font(.headline)

                Stepper(value: $weight, in: 0...500, step: 2.5) {
                    Text("\(weight, specifier: "%.1f") kg").monospacedDigit()
                }
                Stepper(value: $reps, in: 1...50) {
                    Text("\(reps) reps").monospacedDigit()
                }

                Button(action: logSet) {
                    Label(justLogged ? "Logged ✓" : "Log Set", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(justLogged ? .green : .accentColor)
            }
            .padding()
        }
    }

    private func logSet() {
        let session = currentSession()
        let exercise = exercise(named: exerciseName)
        let order = session.sets?.count ?? 0
        let set = SetEntry(weight: weight, reps: reps, order: order, exercise: exercise)
        set.session = session
        context.insert(set)
        try? context.save()

        justLogged = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { justLogged = false }
    }

    // MVP: reuse today's session if one exists, else create one.
    // TODO(UC-10): explicit "start/finish session" flow + exercise picker.
    private func currentSession() -> WorkoutSession {
        let today = Calendar.current.startOfDay(for: Date())
        if let existing = sessions.first(where: {
            Calendar.current.startOfDay(for: $0.date) == today
        }) { return existing }
        let session = WorkoutSession(title: "Workout", date: Date())
        context.insert(session)
        return session
    }

    private func exercise(named name: String) -> Exercise {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
        if let found = try? context.fetch(descriptor).first { return found }
        let exercise = Exercise(name: name)
        context.insert(exercise)
        return exercise
    }
}
