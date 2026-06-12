import SwiftUI
import SwiftData
import CadenceCore

/// The strength-logging screen for one session (FR-1.2–1.5, 1.7). Shows each
/// exercise with inline last-time + PR context, its logged sets, and a rest
/// timer that auto-starts on set completion.
struct SessionView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(ActiveWorkoutModel.self) private var active

    @State private var rest = RestTimerModel()
    @State private var pickerPresented = false
    @State private var setEditor: SetEditorContext?
    @State private var healthSaved = false
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var addPartnerPresented = false
    @State private var newPartnerName = ""
    // Idle auto-terminate (field-testing §02/§04, decisions #6/#7).
    @State private var lastActivity = Date()
    @State private var idlePromptShown = false
    @State private var idlePromptAt: Date?
    @State private var usePreviousPresented = false
    private let idleTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    /// Owner first, then partners alphabetically.
    private var roster: [Person] {
        allPeople.filter(\.isMe) + allPeople.filter { !$0.isMe }
    }
    /// Planned exercise names from a reused workout that have no sets yet.
    private var plannedOnlyNames: [String] {
        let logged = Set(session.exercisesInOrder.map(\.name))
        return session.plannedExerciseNames.filter { !logged.contains($0) }
    }
    /// Nothing logged or planned yet → offer "Use Previous Workout".
    private var isEmptySession: Bool {
        session.exercisesInOrder.isEmpty && plannedOnlyNames.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if rest.isRunning {
                    RestTimerBar(model: rest) { Haptics.restComplete() }
                }
                partnerBar

                if isEmptySession {
                    Button {
                        usePreviousPresented = true
                    } label: {
                        Label("Use Previous Workout", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityIdentifier("session.usePrevious")

                    ContentUnavailableView("Empty workout",
                                           systemImage: "dumbbell",
                                           description: Text("Use a previous workout, or add exercises below."))
                        .padding(.top, 16)
                }

                ForEach(session.exercisesInOrder) { exercise in
                    exerciseCard(exercise)
                }
                ForEach(plannedOnlyNames, id: \.self) { name in
                    plannedCard(name)
                }

                // Add Exercise sits at the bottom, just before End Workout.
                Button {
                    pickerPresented = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 4)
                .accessibilityIdentifier("session.addExercise")

                if active.strengthSession?.id == session.id {
                    WorkoutControlBar(
                        isPaused: active.isPaused,
                        onPauseToggle: togglePause,
                        onEnd: endWorkout,
                        confirmMessage: "This finishes and saves your workout."
                    )
                    .padding(.top, 8)
                }
            }
            .padding()
        }
        .navigationTitle(session.title.isEmpty ? "Workout" : session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await saveToHealth() }
                } label: { Image(systemName: healthSaved ? "checkmark.circle.fill" : "heart.text.square") }
                    .disabled(session.orderedSets.isEmpty)
                    .accessibilityIdentifier("session.saveHealth")
            }
        }
        .overlay(alignment: .top) {
            if healthSaved {
                Text("Saved to Apple Health")
                    .font(.caption).padding(8)
                    .background(.thinMaterial, in: Capsule())
                    .accessibilityIdentifier("session.healthSaved")
            }
        }
        .sheet(isPresented: $pickerPresented) {
            ExercisePickerView { exercise in
                // Open the set editor immediately for the chosen exercise.
                setEditor = SetEditorContext(exercise: exercise, editing: nil)
            }
        }
        .sheet(item: $setEditor) { ctx in
            setEditorSheet(ctx)
        }
        .sheet(isPresented: $usePreviousPresented) {
            PreviousWorkoutPicker(excluding: session) { past in
                _ = try? WorkoutRepository.copyWorkout(from: past, into: session, in: context)
                poke()
            }
        }
        .task { _ = try? WorkoutRepository.me(in: context) }
        .onReceive(idleTimer) { _ in checkIdle() }
        .alert("Still training?", isPresented: $idlePromptShown) {
            Button("Keep going") { poke() }
            Button("Save now", role: .destructive) { endWorkout() }
        } message: {
            Text("No activity for \(settings.idleTimeoutMinutes) min. This workout saves automatically soon.")
        }
        .alert("Add training partner", isPresented: $addPartnerPresented) {
            TextField("Name", text: $newPartnerName)
                .accessibilityIdentifier("partner.nameField")
            Button("Add") {
                let name = newPartnerName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { _ = try? WorkoutRepository.findOrCreatePerson(named: name, in: context) }
                newPartnerName = ""
            }
            Button("Cancel", role: .cancel) { newPartnerName = "" }
        } message: {
            Text("Their sets are recorded separately and kept out of your PRs and Apple Health.")
        }
    }

    // MARK: Partner bar (field-testing §04)

    private var partnerBar: some View {
        HStack(spacing: 8) {
            Text("With:").font(.caption).foregroundStyle(.secondary)
            ForEach(roster) { p in
                Text(p.isMe ? "Me" : p.name)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.tint.opacity(p.isMe ? 0.18 : 0.10), in: Capsule())
                    .accessibilityIdentifier("partner.chip.\(p.isMe ? "Me" : p.name)")
            }
            Button {
                addPartnerPresented = true
            } label: { Image(systemName: "plus.circle") }
                .accessibilityIdentifier("partner.add")
            Spacer()
        }
    }

    // MARK: Planned (reused) exercise card — no sets yet

    @ViewBuilder
    private func plannedCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.headline)
                .accessibilityIdentifier("exerciseCard.\(name)")
            Text("Planned — tap to log").font(.caption).foregroundStyle(.secondary)
            Button {
                if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
                    setEditor = SetEditorContext(exercise: ex, editing: nil)
                }
            } label: { Label("Add Set", systemImage: "plus") }
                .buttonStyle(.bordered).controlSize(.small)
                .accessibilityIdentifier("set.add.\(name)")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
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
            if let p = set.performedBy, !p.isMe {
                Text(p.name).font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .accessibilityIdentifier("set.performer.\(p.name)")
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
        // Partner sets never earn the owner's PR badge (field-testing §04).
        guard set.isOwnerSet, !set.isWarmup, set.reps > 0, set.weight > 0 else { return false }
        let previous = (exercise.sets ?? [])
            .filter { $0.isOwnerSet && $0.completedAt < set.completedAt }
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
            people: roster,
            plateRounding: settings.plateRounding,
            initialWeightKg: ctx.editing?.weight ?? inSessionLast?.weight ?? 0,
            initialReps: ctx.editing?.reps ?? inSessionLast?.reps ?? 5,
            initialRPE: ctx.editing?.rpe,
            initialWarmup: ctx.editing?.isWarmup ?? false,
            initialNote: ctx.editing?.note,
            initialPerformedBy: ctx.editing?.performedBy ?? inSessionLast?.performedBy,
            isPRPredicate: { kg, reps, warmup in
                WorkoutRepository.wouldBePR(exercise: exercise, weightKg: kg, reps: reps, isWarmup: warmup,
                                            rule: settings.prRule, formula: settings.formula)
            },
            onSave: { kg, reps, rpe, warmup, note, performedBy in
                if let editing = ctx.editing {
                    try? WorkoutRepository.updateSet(editing, weightKg: kg, reps: reps,
                                                     rpe: .some(rpe), isWarmup: warmup, note: .some(note), in: context)
                    editing.performedBy = (performedBy?.isMe ?? true) ? nil : performedBy
                    try? context.save()
                } else {
                    addSet(to: exercise, weightKg: kg, reps: reps, rpe: rpe, isWarmup: warmup,
                           note: note, performedBy: performedBy)
                }
            },
            onDelete: ctx.editing.map { set in { try? WorkoutRepository.deleteSet(set, in: context) } }
        )
    }

    /// Writes a summary HKWorkout for this session (FR-4.3). Detailed sets stay
    /// local; only duration + estimated energy go to Health.
    private func saveToHealth() async {
        let sets = session.orderedSets
        guard let first = sets.first?.completedAt else { return }
        let last = sets.last?.completedAt ?? first
        // Minimum 1-minute duration so Health accepts it.
        let end = max(last, first.addingTimeInterval(60))
        let minutes = end.timeIntervalSince(first) / 60
        let summary = StrengthWorkoutSummary(id: session.id, start: first, end: end,
                                             activeEnergyKcal: max(50, minutes * 5))
        let hkID = await model.health.saveStrengthWorkout(summary)
        if let hkID { session.healthKitWorkoutUUID = hkID; try? context.save() }
        withAnimation { healthSaved = true }
    }

    /// Idle watchdog: after `idleTimeoutMinutes` with no activity, prompt; if the
    /// prompt is ignored for 30s, auto-save (field-testing §02, decisions #6/#7).
    private func checkIdle() {
        guard active.strengthSession?.id == session.id else { return }
        // A paused workout never auto-saves — the clock and idle watchdog freeze.
        guard !active.isPaused else { return }
        if idlePromptShown {
            if let at = idlePromptAt, Date().timeIntervalSince(at) >= 30 { endWorkout() }
        } else {
            let timeout = TimeInterval(max(1, settings.idleTimeoutMinutes) * 60)
            if Date().timeIntervalSince(lastActivity) >= timeout {
                idlePromptShown = true; idlePromptAt = Date()
            }
        }
    }

    /// Records activity, resetting the idle countdown.
    private func poke() {
        lastActivity = Date(); idlePromptShown = false; idlePromptAt = nil
    }

    /// Toggles the active session's pause (field-testing Round 4 A1). Resuming
    /// also pokes the idle watchdog so it doesn't fire on the stale timestamp.
    private func togglePause() {
        if active.isPaused { active.resume(); poke() } else { active.pause() }
    }

    /// Finalizes the active session (field-testing §02): stamps `endedAt`,
    /// clears the active reference, and returns to Home.
    private func endWorkout() {
        active.endStrength()
        try? context.save()
        dismiss()
    }

    private func addSet(to exercise: Exercise, weightKg: Double, reps: Int,
                        rpe: Double?, isWarmup: Bool, note: String?, performedBy: Person? = nil) {
        poke()
        let person = (performedBy?.isMe ?? true) ? nil : performedBy
        // PR is only the owner's concern; a partner's set never fires a PR.
        let isPR = person == nil && WorkoutRepository.wouldBePR(exercise: exercise, weightKg: weightKg, reps: reps,
                                               isWarmup: isWarmup, rule: settings.prRule, formula: settings.formula)
        _ = try? WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: weightKg,
                                          reps: reps, rpe: rpe, isWarmup: isWarmup, note: note,
                                          performedBy: person, in: context)
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

/// Pick a past workout to copy into the current session (field-test round 2).
struct PreviousWorkoutPicker: View {
    let excluding: WorkoutSession
    let onPick: (WorkoutSession) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    private var candidates: [WorkoutSession] {
        sessions.filter { $0.id != excluding.id && !$0.orderedSets.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List {
                if candidates.isEmpty {
                    ContentUnavailableView("No previous workouts", systemImage: "clock",
                                           description: Text("Log a workout first."))
                }
                ForEach(candidates) { s in
                    Button {
                        onPick(s); dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title.isEmpty ? "Workout" : s.title)
                            Text(s.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(s.exercisesInOrder.count) exercises · \(s.orderedSets.count) sets")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityIdentifier("usePrevious.row")
                }
            }
            .navigationTitle("Use Previous Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("usePrevious.cancel")
                }
            }
        }
    }
}
