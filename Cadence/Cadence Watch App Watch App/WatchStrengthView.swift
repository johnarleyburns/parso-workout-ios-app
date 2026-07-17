import SwiftUI
import SwiftData
import WatchConnectivity
import CadenceCore
import CadenceFeatures

/// Standalone wrist strength-logging flow for the Cladiron Watch App.
///
/// Phase 3: exercise selection, weight+reps keypad (Crown for fine, chips for
/// coarse), rest timer, and `transferUserInfo` sync to phone.
struct WatchStrengthView: View {
    @Environment(\.modelContext) private var context
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(\.dismiss) private var dismiss

    @State private var session: WorkoutSession?
    @State private var activeExercise: Exercise?
    @State private var step: Step = .pickExercise
    @State private var weight: Double = 20
    @State private var reps: Double = 8
    @State private var restTimer = RestTimerModel()
    @State private var exerciseQuery: String = ""

    enum Step { case pickExercise, logSet, rest, addExercise, summary }

    var body: some View {
        Group {
            switch step {
            case .pickExercise: exercisePicker
            case .addExercise: addExerciseScreen
            case .logSet: setLogger
            case .rest: restScreen
            case .summary: summaryScreen
            }
        }
        .onAppear { startSession() }
        .toolbar {
            if step == .pickExercise {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { finishWorkout() }
                }
            }
        }
    }

    // MARK: - Exercise picker

    private var exercisePicker: some View {
        List {
            Section("Exercises") {
                if let session {
                    let exercises = session.exercisesInOrder
                    if exercises.isEmpty {
                        Text("Tap + to add an exercise")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(exercises, id: \.persistentModelID) { ex in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name)
                                    .lineLimit(1)
                                if let sets = ex.sets, !sets.isEmpty {
                                    Text("\(sets.count) set" + (sets.count == 1 ? "" : "s"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selectExercise(ex) }
                    }
                }
            }

            Section {
                Button(action: { step = .addExercise }) {
                    Label("Add Exercise", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Lift")
    }

    private var addExerciseScreen: some View {
        List {
            ForEach(commonExercises, id: \.self) { name in
                Button(action: { addExercise(named: name) }) {
                    Text(name)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Add Exercise")
    }

    private let commonExercises: [String] = [
        "Bench Press", "Squat", "Deadlift", "Overhead Press", "Row",
        "Pull-Up", "Bicep Curl", "Tricep Extension", "Lunges", "Leg Press",
        "Lat Pulldown", "Shoulder Press", "Dumbbell Fly", "Calf Raise", "Plank"
    ]

    // MARK: - Set logger

    private var setLogger: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(activeExercise?.name ?? "")
                    .font(.headline)

                if let lastSet = previousSetInfo {
                    Text(lastSet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                weightControl
                repsControl

                Button(action: logSet) {
                    Label("Log Set", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding()
        }
        .navigationTitle("Log Set")
    }

    private var weightControl: some View {
        VStack(spacing: 4) {
            Text("Weight")
                .font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("-5") { weight = max(0, weight - 5) }.buttonStyle(.bordered)
                Text(String(format: "%.0f kg", weight))
                    .font(.title2.monospaced())
                    .focusable()
                    .digitalCrownRotation($weight, from: 0, through: 300, by: 2.5,
                                          sensitivity: .medium, isContinuous: false)
                Button("+5") { weight += 5 }.buttonStyle(.bordered)
            }
        }
    }

    private var repsControl: some View {
        VStack(spacing: 4) {
            Text("Reps")
                .font(.caption.bold()).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button("-1") { reps = max(1, reps - 1) }.buttonStyle(.bordered)
                Text("\(Int(reps))")
                    .font(.title2.monospaced())
                    .focusable()
                    .digitalCrownRotation($reps, from: 1, through: 30, by: 1,
                                          sensitivity: .medium, isContinuous: false)
                Button("+1") { reps += 1 }.buttonStyle(.bordered)
            }
        }
    }

    private var previousSetInfo: String? {
        guard let ex = activeExercise else { return nil }
        let workingSets = (ex.sets ?? []).filter { !$0.isWarmup }
        guard let last = workingSets.last else { return nil }
        return "Previous: \(String(format: "%.0f", last.effectiveLoadKg)) × \(last.reps)"
    }

    private func logSet() {
        guard let session, let exercise = activeExercise else { return }
        do {
            let set = try WorkoutRepository.addSet(
                to: session, exercise: exercise, weightKg: weight, reps: Int(reps),
                in: context
            )
            enqueueSetSync(
                sessionID: session.id,
                exercise: exercise.name,
                weight: set.effectiveLoadKg,
                reps: Int(reps)
            )
            restTimer.start(seconds: 90)
            step = .rest
        } catch {
            return
        }
    }

    // MARK: - Rest timer

    private var restScreen: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("REST")
                .font(.caption.bold()).foregroundStyle(.secondary)

            Text(formatTime(TimeInterval(restTimer.remaining)))
                .font(.system(size: 52, weight: .heavy, design: .monospaced))

            if restTimer.isRunning {
                ProgressView(value: restTimer.progress)
                    .tint(.green)
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 12) {
                Button("+30s") { restTimer.add(30) }.buttonStyle(.bordered)
                Button("Next Set") {
                    restTimer.skip()
                    step = .logSet
                }
                .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .onAppear { if !restTimer.isRunning { restTimer.start(seconds: 90) } }
        // Tick the timer
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            restTimer.tick()
        }
    }

    // MARK: - Summary

    private var summaryScreen: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40)).foregroundStyle(.green)
            Text("Done")
                .font(.headline)
            if let session {
                Text("\(session.exercisesInOrder.count) exercise" +
                     (session.exercisesInOrder.count == 1 ? "" : "s"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Helpers

    private func startSession() {
        do {
            session = try WorkoutRepository.createSession(title: "Lift", in: context)
            watchManager.startWorkout(type: "strength")
        } catch {
            dismiss()
        }
    }

    private func selectExercise(_ exercise: Exercise) {
        activeExercise = exercise
        // Pre-fill weight from last set
        let lastWork = (exercise.sets ?? []).last(where: { !$0.isWarmup })
        if let lastWork { weight = lastWork.effectiveLoadKg }
        step = .logSet
    }

    private func addExercise(named name: String) {
        guard let session else { return }
        do {
            let exercise = try WorkoutRepository.findOrCreateExercise(named: name, in: context)
            activeExercise = exercise
            step = .logSet
        } catch {
            return
        }
    }

    private func finishWorkout() {
        session?.endedAt = Date()
        watchManager.stopWorkout()
        // Sync the complete session
        if let session {
            enqueueSessionSync(session)
        }
        step = .summary
    }

    private func enqueueSetSync(sessionID: UUID, exercise: String, weight: Double, reps: Int) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([
            "action": "log_set",
            "session_id": sessionID.uuidString,
            "exercise": exercise,
            "weight": weight,
            "reps": reps,
            "timestamp": Date().timeIntervalSince1970
        ])
    }

    private func enqueueSessionSync(_ session: WorkoutSession) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([
            "action": "end_session",
            "session_id": session.id.uuidString,
            "ended_at": (session.endedAt ?? Date()).timeIntervalSince1970,
            "exercises": session.exercisesInOrder.map { $0.name }
        ])
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
