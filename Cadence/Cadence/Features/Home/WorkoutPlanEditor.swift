import SwiftUI
import SwiftData
import CadenceCore

struct EditablePlan {
    var title: String = "Workout"
    var warmupMinutes: Int
    var cooldownMinutes: Int
    var exercises: [EditableExercise]

    static func empty(warmup: Int, cooldown: Int) -> EditablePlan {
        EditablePlan(warmupMinutes: warmup, cooldownMinutes: cooldown, exercises: [])
    }

    static func from(session: WorkoutSession) -> EditablePlan {
        let exercises = session.exercisesInOrder.map { ex -> EditableExercise in
            let sets = session.orderedSets.filter { $0.exercise?.id == ex.id && $0.isOwnerSet }
            return EditableExercise(
                name: ex.name,
                sets: sets.map { EditableSet(targetReps: $0.reps, targetWeight: $0.weight > 0 ? $0.weight : nil) },
                notes: ""
            )
        }
        return EditablePlan(
            title: session.title,
            warmupMinutes: 0,
            cooldownMinutes: 0,
            exercises: exercises
        )
    }

    static func from(plan: WorkoutPlan, ladder: [Int]?, unit: MeasurementUnitPreference) -> EditablePlan {
        let reps = ladder ?? []
        let exercises = plan.items.map { item -> EditableExercise in
            let setsCount = max(item.targetSets ?? reps.count, reps.isEmpty ? 3 : reps.count)
            let sets = (0..<setsCount).map { i -> EditableSet in
                let r = i < reps.count ? reps[i] : (item.reps ?? 5)
                return EditableSet(targetReps: r, targetWeight: nil)
            }
            return EditableExercise(name: item.movement, sets: sets, notes: item.note ?? "")
        }
        return EditablePlan(
            title: plan.name,
            warmupMinutes: 0,
            cooldownMinutes: 0,
            exercises: exercises
        )
    }

    static func from(recommendation: Recommendation) -> EditablePlan {
        let prescribed = recommendation.prescribedSession()
        let ladder = prescribed.repLadder
        let names = prescribed.exerciseNames
        let exercises = names.map { name -> EditableExercise in
            let sets = ladder.isEmpty
                ? [EditableSet(targetReps: 5, targetWeight: prescribed.loadKg)]
                : ladder.map { EditableSet(targetReps: $0, targetWeight: prescribed.loadKg) }
            return EditableExercise(name: name, sets: sets, notes: "")
        }
        return EditablePlan(
            title: prescribed.title,
            warmupMinutes: 0,
            cooldownMinutes: 0,
            exercises: exercises
        )
    }
}

struct EditableExercise: Identifiable {
    let id = UUID()
    var name: String
    var sets: [EditableSet]
    var notes: String
}

struct EditableSet: Identifiable {
    let id = UUID()
    var targetReps: Int
    var targetWeight: Double?
}

struct WorkoutPlanEditor: View {
    @State var plan: EditablePlan
    let onStart: (EditablePlan) -> Void

    @Environment(AppSettings.self) private var settings
    @State private var showingExercisePicker = false

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    Stepper("Warm-up: \(plan.warmupMinutes) min", value: $plan.warmupMinutes, in: 0...30)
                        .accessibilityIdentifier("editor.warmup")
                }

                ForEach($plan.exercises) { $exercise in
                    exerciseSection($exercise)
                }
                .onMove { plan.exercises.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { plan.exercises.remove(atOffsets: $0) }

                Section {
                    Button {
                        showingExercisePicker = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("editor.addExercise")
                }

                Section {
                    Stepper("Cool-down: \(plan.cooldownMinutes) min", value: $plan.cooldownMinutes, in: 0...30)
                        .accessibilityIdentifier("editor.cooldown")
                }

                Section {
                    @Bindable var settings = settings
                    Toggle("Use HR monitoring", isOn: $settings.useHRMonitoring)
                        .accessibilityIdentifier("editor.hrToggle")
                }
            }
            .environment(\.editMode, .constant(.active))

            Button(action: { onStart(plan) }) {
                Label("Start", systemImage: "play.fill")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .padding()
            .accessibilityIdentifier("editor.start")
        }
        .navigationTitle("Workout Plan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingExercisePicker) {
            NavigationStack {
                ExercisePickerView { exercise in
                    plan.exercises.append(
                        EditableExercise(name: exercise.name, sets: [EditableSet(targetReps: 10, targetWeight: nil)], notes: "")
                    )
                    showingExercisePicker = false
                }
            }
        }
    }

    @ViewBuilder
    private func exerciseSection(_ exercise: Binding<EditableExercise>) -> some View {
        Section {
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                Text(exercise.wrappedValue.name).font(.headline)
                Spacer()
            }
            .accessibilityIdentifier("editor.exercise.\(exercise.wrappedValue.name)")

            ForEach(exercise.sets) { $set in
                setRow($set, unit: settings.unit)
            }
            .onDelete { exercise.wrappedValue.sets.remove(atOffsets: $0) }

            Button {
                let lastReps = exercise.wrappedValue.sets.last?.targetReps ?? 10
                let lastWeight = exercise.wrappedValue.sets.last?.targetWeight
                exercise.wrappedValue.sets.append(EditableSet(targetReps: lastReps, targetWeight: lastWeight))
            } label: {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline)
            }
            .accessibilityIdentifier("editor.addSet.\(exercise.wrappedValue.name)")
        }
    }

    private func setRow(_ set: Binding<EditableSet>, unit: MeasurementUnitPreference) -> some View {
        HStack {
            Stepper("Reps: \(set.wrappedValue.targetReps)", value: set.targetReps, in: 1...100)
                .frame(maxWidth: .infinity)
            if let w = set.wrappedValue.targetWeight {
                Text(Format.weight(w, unit: unit))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
        }
    }
}
