import SwiftUI
import SwiftData
import CadenceCore

/// The strength-logging screen for one session (FR-1.2–1.5, 1.7). Shows each
/// exercise with inline last-time + PR context, its logged sets, and a rest
/// timer that auto-starts on set completion.
struct SessionView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var rest = RestTimerModel()
    @State private var pickerPresented = false
    @State private var setEditor: SetEditorContext?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if rest.isRunning {
                    RestTimerBar(model: rest) { Haptics.restComplete() }
                }
                ForEach(session.exercisesInOrder) { exercise in
                    exerciseCard(exercise)
                }
                Button {
                    pickerPresented = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
                .accessibilityIdentifier("session.addExercise")

                if session.exercisesInOrder.isEmpty {
                    ContentUnavailableView("No exercises yet",
                                           systemImage: "dumbbell",
                                           description: Text("Tap Add Exercise to start logging."))
                        .padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle(session.title.isEmpty ? "Workout" : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickerPresented) {
            ExercisePickerView { exercise in
                // Open the set editor immediately for the chosen exercise.
                setEditor = SetEditorContext(exercise: exercise, editing: nil)
            }
        }
        .sheet(item: $setEditor) { ctx in
            setEditorSheet(ctx)
        }
    }

    // MARK: Exercise card

    @ViewBuilder
    private func exerciseCard(_ exercise: Exercise) -> some View {
        let sets = session.orderedSets.filter { $0.exercise?.id == exercise.id }
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.name)
                .font(.headline)
                .accessibilityIdentifier("exerciseCard.\(exercise.name)")

            contextLine(for: exercise)

            ForEach(Array(sets.enumerated()), id: \.element.id) { idx, set in
                Button {
                    setEditor = SetEditorContext(exercise: exercise, editing: set)
                } label: {
                    setRow(set, index: idx, exercise: exercise)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("set.row.\(exercise.name).\(idx)")
            }

            HStack {
                Button {
                    setEditor = SetEditorContext(exercise: exercise, editing: nil)
                } label: { Label("Add Set", systemImage: "plus") }
                    .accessibilityIdentifier("set.add.\(exercise.name)")
                if let last = sets.last {
                    Spacer()
                    Button {
                        addSet(to: exercise, weightKg: last.weight, reps: last.reps,
                               rpe: last.rpe, isWarmup: last.isWarmup, note: nil)
                    } label: { Label("Repeat last", systemImage: "arrow.clockwise") }
                        .accessibilityIdentifier("set.repeat.\(exercise.name)")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func contextLine(for exercise: Exercise) -> some View {
        let last = WorkoutRepository.lastTimeSets(for: exercise, excluding: session)
        let pr = WorkoutRepository.currentPR(for: exercise, rule: settings.prRule,
                                             formula: settings.formula, excluding: session)
        VStack(alignment: .leading, spacing: 2) {
            if !last.isEmpty {
                Text("Last time: " + last.map { Format.setLine($0, unit: settings.unit) }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("exercise.lastTime")
            }
            if let pr {
                Text("PR: \(Format.weight(pr, unit: settings.unit)) · \(settings.prRule.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("exercise.pr")
            }
        }
    }

    @ViewBuilder
    private func setRow(_ set: SetEntry, index: Int, exercise: Exercise) -> some View {
        HStack {
            Text("\(index + 1)")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            Text(Format.setLine(set, unit: settings.unit))
                .monospacedDigit()
            if set.isWarmup {
                Text("warmup").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            if let rpe = set.rpe {
                Text("RPE \(rpe, specifier: "%.1f")").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if isAllTimePR(set, exercise: exercise) {
                Label("PR", systemImage: "trophy.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.bold())
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("set.prBadge")
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
        .swipeActions {
            Button(role: .destructive) {
                try? WorkoutRepository.deleteSet(set, in: context)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    // MARK: PR detection for display

    private func isAllTimePR(_ set: SetEntry, exercise: Exercise) -> Bool {
        guard !set.isWarmup, set.reps > 0, set.weight > 0 else { return false }
        let previous = (exercise.sets ?? [])
            .filter { $0.completedAt < set.completedAt }
            .map { SetSample(weight: $0.weight, reps: $0.reps, date: $0.completedAt, isWarmup: $0.isWarmup) }
        let candidate = SetSample(weight: set.weight, reps: set.reps, date: set.completedAt, isWarmup: set.isWarmup)
        return PRCalculator.isNewPR(candidate: candidate, previous: previous,
                                    rule: settings.prRule, formula: settings.formula)
    }

    // MARK: Set editor sheet

    @ViewBuilder
    private func setEditorSheet(_ ctx: SetEditorContext) -> some View {
        let exercise = ctx.exercise
        let last = WorkoutRepository.lastTimeSets(for: exercise, excluding: session).first
        let pr = WorkoutRepository.currentPR(for: exercise, rule: settings.prRule, formula: settings.formula)
        let inSessionLast = session.orderedSets.last { $0.exercise?.id == exercise.id }

        SetEditorView(
            exerciseName: exercise.name,
            unit: settings.unit,
            lastTimeText: last.map { Format.setLine($0, unit: settings.unit) },
            prText: pr.map { Format.weight($0, unit: settings.unit) },
            initialWeightKg: ctx.editing?.weight ?? inSessionLast?.weight ?? 0,
            initialReps: ctx.editing?.reps ?? inSessionLast?.reps ?? 5,
            initialRPE: ctx.editing?.rpe,
            initialWarmup: ctx.editing?.isWarmup ?? false,
            initialNote: ctx.editing?.note,
            isPRPredicate: { kg, reps, warmup in
                WorkoutRepository.wouldBePR(exercise: exercise, weightKg: kg, reps: reps, isWarmup: warmup,
                                            rule: settings.prRule, formula: settings.formula)
            },
            onSave: { kg, reps, rpe, warmup, note in
                if let editing = ctx.editing {
                    try? WorkoutRepository.updateSet(editing, weightKg: kg, reps: reps,
                                                     rpe: .some(rpe), isWarmup: warmup, note: .some(note), in: context)
                } else {
                    addSet(to: exercise, weightKg: kg, reps: reps, rpe: rpe, isWarmup: warmup, note: note)
                }
            },
            onDelete: ctx.editing.map { set in { try? WorkoutRepository.deleteSet(set, in: context) } }
        )
    }

    private func addSet(to exercise: Exercise, weightKg: Double, reps: Int,
                        rpe: Double?, isWarmup: Bool, note: String?) {
        let isPR = WorkoutRepository.wouldBePR(exercise: exercise, weightKg: weightKg, reps: reps,
                                               isWarmup: isWarmup, rule: settings.prRule, formula: settings.formula)
        _ = try? WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: weightKg,
                                          reps: reps, rpe: rpe, isWarmup: isWarmup, note: note, in: context)
        if isPR { Haptics.prAchieved() } else { Haptics.setLogged() }
        if settings.autoStartRest && !isWarmup {
            rest.start(seconds: settings.restSeconds)
        }
    }
}

/// Identifies what the set editor sheet is editing.
struct SetEditorContext: Identifiable {
    let id = UUID()
    let exercise: Exercise
    let editing: SetEntry?
}
