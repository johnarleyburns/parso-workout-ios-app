import SwiftUI
import SwiftData
import CadenceCore

/// The strength-logging screen for one session (FR-1.2–1.5, 1.7). Shows each
/// exercise with inline last-time + PR context, its logged sets, and a rest
/// timer that auto-starts on set completion.
struct SessionView: View {
    @Bindable var session: WorkoutSession
    /// Manual after-the-fact logging (feedback batch 7 follow-up): the session is
    /// `isLogged` + back-dated and is NOT the live `active` session, so the elapsed
    /// clock, control bar, and idle watchdog all stay hidden (they gate on
    /// `active.strengthSession`). Instead we show a "Done" button and stamp sets to
    /// the workout's date. Defaults keep the live/edit-from-history callers unchanged.
    var isManualLog: Bool = false
    /// Dismisses the whole logging flow back to Home once the user is finished.
    var onDone: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(ActiveWorkoutModel.self) private var active

    @State private var rest = RestTimerModel()
    @State private var pickerPresented = false
    @State private var keypad: KeypadContext?
    @State private var healthSaved = false
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var addPartnerPresented = false
    @State private var newPartnerName = ""
    // Idle auto-terminate (field-testing §02/§04, decisions #6/#7).
    @State private var lastActivity = Date()
    @State private var idlePromptShown = false
    @State private var idlePromptAt: Date?
    @State private var usePreviousPresented = false
    // Cool-down (feedback batch 4): a guided timer that, on finish/skip, ends the
    // workout. The workout is paused while it runs so the clock doesn't advance.
    @State private var coolingDown = false
    // Guard against an accidental Cool Down tap — it ends the workout (batch 7 item 6).
    @State private var coolDownConfirm = false
    private let idleTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    /// Owner first, then partners alphabetically.
    private var roster: [Person] {
        allPeople.filter(\.isMe) + allPeople.filter { !$0.isMe }
    }
    /// At least one training partner is in the roster — then owner sets are tagged
    /// "Me" too, to disambiguate (feedback batch 3).
    private var hasPartners: Bool { allPeople.contains { !$0.isMe } }
    /// Whether the set editor should default to a bodyweight set for an exercise.
    private func isBodyweight(_ exercise: Exercise) -> Bool {
        exercise.equipmentValue == .bodyweight
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
    /// The CrossFit / preset plan that launched this session, if any (round4b §B-1).
    private var plan: WorkoutPlan? {
        session.planKey.flatMap { PlanCatalog.plan(forKey: $0) }
    }
    /// Rep-ladder for the plan's scheme (applies to every item), else nil.
    private var planLadder: [Int]? {
        if case let .forTime(rounds, _) = plan?.scheme { return rounds }
        return nil
    }
    /// Prescription line for a planned movement, resolved from the plan. A
    /// flexible template launched with a chosen rep scheme (feedback batch 3)
    /// shows that ladder, applied to every movement.
    private func prescription(for name: String) -> String? {
        let chosen = session.plannedRepLadder
        if let item = plan?.items.first(where: { $0.movement == name }) {
            let ladder = chosen.isEmpty ? planLadder : chosen
            let line = Format.prescription(item, ladder: ladder, unit: settings.unit)
            return line.isEmpty ? nil : line
        }
        // No catalog item (e.g. a reused session) but a chosen scheme is present.
        guard !chosen.isEmpty else { return nil }
        return chosen.map(String.init).joined(separator: "-") + " reps"
    }

    /// The effective rep-ladder for an exercise: the chosen scheme if the session
    /// carries one, else the plan's `forTime` ladder. Drives the pre-seeded planned
    /// set rows and the default reps for each new set (feedback batch 6, items 1/2).
    private func effectiveLadder(for name: String) -> [Int]? {
        let chosen = session.plannedRepLadder
        if !chosen.isEmpty { return chosen }
        return planLadder
    }
    /// How many planned set rows an exercise should pre-seed (ladder length).
    private func plannedSetCount(for name: String) -> Int {
        effectiveLadder(for: name)?.count ?? 0
    }
    /// Default reps for the set at `setIndex`: the ladder value at that rung if any,
    /// else the last logged set of this exercise, else 5 (feedback batch 6 item 1).
    private func plannedReps(for exercise: Exercise, setIndex: Int) -> Int {
        if let ladder = effectiveLadder(for: exercise.name),
           setIndex < ladder.count, ladder[setIndex] > 0 {
            return ladder[setIndex]
        }
        if let last = session.orderedSets.last(where: { $0.exercise?.id == exercise.id }) {
            return last.reps
        }
        return 5
    }

    /// Opens the weight keypad for a new or existing set of `exercise`. `repsOverride`
    /// seeds the reps for a tapped planned row.
    private func openKeypad(for exercise: Exercise, editing: SetEntry? = nil, repsOverride: Int? = nil) {
        keypad = KeypadContext(exercise: exercise, editing: editing, repsOverride: repsOverride)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isManualLog { loggedDateBanner }
                if rest.isRunning {
                    RestTimerBar(model: rest) { Haptics.restComplete() }
                }
                if let plan { planBanner(plan) }
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
                        onCoolDown: { coolDownConfirm = true },
                        confirmMessage: "This finishes and saves your workout."
                    )
                    .padding(.top, 8)
                } else if isManualLog {
                    // A logged session saves incrementally as sets are added; Done just
                    // returns to Home (the "Logged" workout is already in history).
                    Button {
                        finishManualLog()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)
                    .padding(.top, 8)
                    .accessibilityIdentifier("log.done")
                }
            }
            .padding()
        }
        .navigationTitle(session.title.isEmpty ? "Workout" : session.title)
        .navigationBarTitleDisplayMode(.inline)
        // P2 (#7) — a prominent elapsed clock, pinned above the scroll so it stays
        // visible while logging. Only for the live session (not when reviewing/editing
        // a past one from history), driven by the active session's WorkoutClock.
        .safeAreaInset(edge: .top, spacing: 0) {
            if active.strengthSession?.id == session.id {
                WorkoutElapsedHeader(clock: active.clock, isPaused: active.isPaused)
            }
        }
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
                // Open the keypad immediately for the chosen exercise.
                keypad = KeypadContext(exercise: exercise, editing: nil)
            }
        }
        .sheet(item: $keypad) { ctx in
            keypadSheet(ctx)
        }
        .sheet(isPresented: $usePreviousPresented) {
            PreviousWorkoutPicker(excluding: session) { past in
                _ = try? WorkoutRepository.copyWorkout(from: past, into: session, in: context)
                poke()
            }
        }
        .fullScreenCover(isPresented: $coolingDown) {
            GuidedPhaseOverlay(
                title: "Cool Down",
                minutes: settings.cooldownMinutes,
                tint: .teal,
                idPrefix: "cooldown",
                soundsEnabled: settings.workoutSounds,
                onFinish: { secs in
                    session.cooldownSeconds = Double(secs)
                    coolingDown = false
                    endWorkout()
                })
        }
        .confirmationDialog("Start cool-down?", isPresented: $coolDownConfirm, titleVisibility: .visible) {
            Button("Start Cool Down") { active.pause(); coolingDown = true }
                .accessibilityIdentifier("workout.coolDownConfirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This ends your workout and starts the cool-down timer.")
        }
        .task { _ = try? WorkoutRepository.me(in: context) }
        // Backing out of a freshly-started log with nothing entered shouldn't litter
        // history with an empty "Logged" row.
        .onDisappear { if isManualLog { cleanupEmptyLog() } }
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

    /// Reminds the user which past date a manually-logged workout is being filed
    /// under (feedback batch 7 follow-up).
    private var loggedDateBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.and.pencil")
            Text("Logging \(session.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("log.dateBanner")
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

    // MARK: Plan banner (CrossFit / preset scheme, round4b §B-1)

    @ViewBuilder
    private func planBanner(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.schemeSummary)
                .font(.headline)
                .accessibilityIdentifier("session.planBanner")
            if let notes = plan.notes {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Planned (reused) exercise card — no sets yet

    @ViewBuilder
    private func plannedCard(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name).font(.headline)
                .accessibilityIdentifier("exerciseCard.\(name)")
            if let rx = prescription(for: name) {
                Text(rx).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("session.rx.\(name)")
            } else {
                Text("Planned — tap to log").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
                    openKeypad(for: ex)
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
        // Pre-seed one row per planned set still to do (feedback batch 6 item 2):
        // tap a pending row to log it with its prescribed reps already filled in.
        let pending = max(0, plannedSetCount(for: exercise.name) - sets.count)
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.name)
                .font(.headline)
                .accessibilityIdentifier("exerciseCard.\(exercise.name)")

            contextLine(for: exercise)

            ForEach(Array(sets.enumerated()), id: \.element.id) { idx, set in
                Button {
                    openKeypad(for: exercise, editing: set)
                } label: {
                    setRow(set, index: idx, exercise: exercise)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("set.row.\(exercise.name).\(idx)")
            }

            ForEach(0..<pending, id: \.self) { offset in
                let rowIndex = sets.count + offset
                Button {
                    openKeypad(for: exercise, repsOverride: plannedReps(for: exercise, setIndex: rowIndex))
                } label: {
                    pendingRow(index: rowIndex, reps: plannedReps(for: exercise, setIndex: rowIndex))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("set.pending.\(exercise.name).\(offset)")
            }

            HStack {
                Button {
                    openKeypad(for: exercise)
                } label: { Label("Add Set", systemImage: "plus") }
                    .accessibilityIdentifier("set.add.\(exercise.name)")
                if let last = sets.last {
                    Spacer()
                    Button {
                        addSet(to: exercise, weightKg: last.weight, reps: last.reps,
                               rpe: last.rpe, isWarmup: last.isWarmup,
                               usesBodyweight: last.usesBodyweight, note: nil)
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

    /// A not-yet-logged planned set: its rung number, target reps, and a tap-to-log
    /// affordance (feedback batch 6 item 2).
    @ViewBuilder
    private func pendingRow(index: Int, reps: Int) -> some View {
        HStack {
            Text("\(index + 1)")
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            Text("\(reps) reps")
                .foregroundStyle(.secondary)
            Spacer()
            Image(systemName: "plus.circle")
                .foregroundStyle(.tint)
        }
        .font(.subheadline)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(.quaternary).frame(height: 1)
        }
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
            if let p = set.performedBy, !p.isMe {
                Text(p.name).font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .accessibilityIdentifier("set.performer.\(p.name)")
            } else if hasPartners {
                // With a partner in the session, tag the owner's own sets "Me".
                Text("Me").font(.caption2).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                    .accessibilityIdentifier("set.performer.Me")
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

    // MARK: Weight keypad sheet (feedback batch 6 item 2)

    @ViewBuilder
    private func keypadSheet(_ ctx: KeypadContext) -> some View {
        let exercise = ctx.exercise
        let last = WorkoutRepository.lastTimeSets(for: exercise, excluding: session).first
        let pr = WorkoutRepository.currentPR(for: exercise, rule: settings.prRule, formula: settings.formula)
        let inSessionLast = session.orderedSets.last { $0.exercise?.id == exercise.id }
        let loggedCount = session.orderedSets.filter { $0.exercise?.id == exercise.id }.count
        // Reps default (item 1): edit keeps its own reps; a tapped planned row uses
        // its rung; otherwise the prescribed reps for the next rung (falling back to
        // the last in-session set / 5).
        let initialReps = ctx.editing?.reps
            ?? ctx.repsOverride
            ?? plannedReps(for: exercise, setIndex: loggedCount)

        WeightKeypadSheet(
            exerciseName: exercise.name,
            unit: settings.unit,
            lastTimeText: last.map { Format.setLine($0, unit: settings.unit) },
            prText: pr.map { Format.weight($0, unit: settings.unit) },
            people: roster,
            plateRounding: settings.plateRounding,
            isBodyweightExercise: isBodyweight(exercise),
            initialWeightKg: ctx.editing?.weight ?? 0,
            initialReps: initialReps,
            initialBodyweight: ctx.editing?.usesBodyweight ?? isBodyweight(exercise),
            initialPerformedBy: ctx.editing?.performedBy ?? inSessionLast?.performedBy,
            isPRPredicate: { kg, reps in
                WorkoutRepository.wouldBePR(exercise: exercise, weightKg: kg, reps: reps, isWarmup: false,
                                            rule: settings.prRule, formula: settings.formula)
            },
            onSave: { kg, reps, bodyweight, performedBy in
                if let editing = ctx.editing {
                    try? WorkoutRepository.updateSet(editing, weightKg: kg, reps: reps,
                                                     rpe: .some(nil), isWarmup: false,
                                                     usesBodyweight: bodyweight, note: .some(nil), in: context)
                    editing.performedBy = (performedBy?.isMe ?? true) ? nil : performedBy
                    try? context.save()
                } else {
                    addSet(to: exercise, weightKg: kg, reps: reps, rpe: nil, isWarmup: false,
                           usesBodyweight: bodyweight, note: nil, performedBy: performedBy)
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
        // Auto-end on idle is opt-out (batch 7 item 8) — some users never want it.
        guard settings.autoEndOnIdle else { return }
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

    /// Finalizes the active session (field-testing §02): optionally writes a Health
    /// summary (P1 #8), stamps `endedAt`, clears the active reference, then hands the
    /// summary to the app model so it presents *over Home* (P1 #9) — the session pops
    /// behind it, so Done reveals Home without flashing the session screen.
    private func endWorkout() {
        // Workout ends — bell so the user knows to stop (batch 7 item 9). Covers both
        // "End now" and the end of a guided cool-down.
        WorkoutCues.transition(enabled: settings.workoutSounds)
        if settings.autoSaveHealth, session.healthKitWorkoutUUID == nil, !session.orderedSets.isEmpty {
            Task { await saveToHealth() }
        }
        active.endStrength()
        try? context.save()
        active.finishedSummary = FinishedSummary(data: .from(session: session))
        dismiss()
    }

    /// Finishes a manual-log session: discards it if nothing was entered, then hands
    /// control back to Home (the logged workout already persisted as sets were added).
    private func finishManualLog() {
        cleanupEmptyLog()
        Haptics.selection()
        onDone?()
    }

    /// Deletes a just-started logged session that has no sets, so an abandoned log
    /// doesn't appear in history. Idempotent — only acts while the session is empty.
    private func cleanupEmptyLog() {
        guard isManualLog, session.orderedSets.isEmpty else { return }
        context.delete(session)
        try? context.save()
    }

    private func addSet(to exercise: Exercise, weightKg: Double, reps: Int,
                        rpe: Double?, isWarmup: Bool, usesBodyweight: Bool = false,
                        note: String?, performedBy: Person? = nil) {
        poke()
        let person = (performedBy?.isMe ?? true) ? nil : performedBy
        // PR is only the owner's concern; a partner's set never fires a PR.
        let isPR = person == nil && WorkoutRepository.wouldBePR(exercise: exercise, weightKg: weightKg, reps: reps,
                                               isWarmup: isWarmup, rule: settings.prRule, formula: settings.formula)
        // A logged set is stamped to the workout's date, not data-entry time, so a
        // back-dated log reads correctly (also right when editing a logged session).
        let when = session.isLogged ? session.date : Date()
        _ = try? WorkoutRepository.addSet(to: session, exercise: exercise, weightKg: weightKg,
                                          reps: reps, rpe: rpe, isWarmup: isWarmup,
                                          usesBodyweight: usesBodyweight, note: note,
                                          completedAt: when, performedBy: person, in: context)
        if isPR { Haptics.prAchieved() } else { Haptics.setLogged() }
        // No rest timer when filing a past workout — there's nothing to rest from.
        if settings.autoStartRest && !isWarmup && !isManualLog {
            rest.start(seconds: settings.restSeconds)
        }
    }
}

/// Identifies what the weight keypad sheet is logging or editing. `repsOverride`
/// seeds the reps for a tapped planned set row (feedback batch 6 item 2).
struct KeypadContext: Identifiable {
    let id = UUID()
    let exercise: Exercise
    let editing: SetEntry?
    var repsOverride: Int? = nil
}

/// Identifiable wrapper so the post-workout `WorkoutSummaryData` (a pure value
/// type, deliberately not `Identifiable`) can drive a `fullScreenCover(item:)`.
struct FinishedSummary: Identifiable {
    let id = UUID()
    let data: WorkoutSummaryData
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
