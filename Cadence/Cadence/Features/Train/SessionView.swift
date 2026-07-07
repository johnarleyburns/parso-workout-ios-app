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
    @State private var inlineExerciseID: UUID?
    @State private var inlineExercise: Exercise?
    @State private var inlineEditingSet: SetEntry?
    @State private var inlineWeight: String = ""
    @State private var inlineReps: Int = 5
    @State private var inlineUnit: MeasurementUnitPreference = .kilograms
    @State private var inlineBodyweight: Bool = false
    @State private var inlinePerformedByID: UUID?
    @State private var inlineRPE: Int? = nil
    @State private var showRPEInfo = false
    @State private var showWeightInfo = false
    @State private var showDumbbellInfo = false
    @State private var inlinePriorWeightHint: Double? = nil
    @AppStorage("dumbbellInfoShown") private var dumbbellInfoShown = false
    @State private var showDeleteConfirm = false
    @FocusState private var weightFocused: Bool
    @State private var healthSaved = false
    @Query(sort: \Person.name) private var allPeople: [Person]
    @State private var addPartnerPresented = false
    @State private var newPartnerName = ""
    @State private var renamePresented = false
    @State private var editedTitle = ""
    @State private var datePickerPresented = false
    @State private var endDatePickerPresented = false
    @State private var exerciseToRemove: Exercise?
    @State private var changingExerciseFor: Exercise?
    @State private var managePartnersPresented = false
    // Idle auto-terminate (field-testing §02/§04, decisions #6/#7).
    @State private var lastActivity = Date()
    @State private var idlePromptShown = false
    @State private var idlePromptAt: Date?
    @State private var usePreviousPresented = false
    @State private var swappingPlannedName: String?
    // Cool-down (feedback batch 4): a guided timer that, on finish/skip, ends the
    // workout. The workout is paused while it runs so the clock doesn't advance.
    @State private var coolingDown = false
    // Guard against an accidental Cool Down tap — it ends the workout (batch 7 item 6).
    @State private var coolDownConfirm = false
    private let idleTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    // HR sampling for strength workouts (FR-2.3). Captures BPM from the BLE strap
    // every 5 s during the live session, piggybacking on the idle timer.
    @State private var hrSamples: [HRSamplePoint] = []

    /// Partner ids already attributed to a set in this session, so a set
    /// mis-attributed to a now-unscoped partner can still be re-picked (and
    /// corrected back to "Me") when editing.
    private var attributedPartnerIDs: [UUID] {
        (session.sets ?? []).compactMap { set in
            guard let p = set.performedBy, !p.isMe else { return nil }
            return p.id
        }
    }
    /// Training partners scoped to this session (opt-in: empty ⇒ solo).
    private var activePartnerPeople: [Person] {
        SessionRoster.scopedPartners(activePartnerIDs: session.activePartnerIDs, allPeople: allPeople)
    }
    /// Configured performer order. Solo ⇒ just the owner.
    private var roster: [Person] {
        SessionRoster.roster(activePartnerIDs: session.activePartnerIDs, allPeople: allPeople)
    }
    /// People that may be attributed a set: scoped partners + anyone already
    /// attributed to a set here. The performer pickers add "Me" separately.
    private var attributablePartners: [Person] {
        SessionRoster.attributablePartners(activePartnerIDs: session.activePartnerIDs,
                                           allPeople: allPeople,
                                           includingAttributed: attributedPartnerIDs)
    }
    /// Whether sets can be attributed to a partner — drives the WHO column and the
    /// performer pickers (true when a partner is scoped OR a set is already attributed).
    private var hasPartners: Bool {
        SessionRoster.canAttribute(activePartnerIDs: session.activePartnerIDs,
                                   allPeople: allPeople,
                                   attributedIDs: attributedPartnerIDs)
    }
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
    /// The strength preset that launched this session, if any (round4b §B-1).
    private var plan: WorkoutPlan? {
        session.planKey.flatMap { PlanCatalog.plan(forKey: $0) }
    }
    /// Prescription line for a planned movement, resolved from the plan. A
    /// flexible template launched with a chosen rep scheme (feedback batch 3)
    /// shows that ladder, applied to every movement.
    private func prescription(for name: String) -> String? {
        let chosen = session.plannedRepLadder
        if let item = plan?.items.first(where: { $0.movement == name }) {
            let ladder = chosen.isEmpty ? nil : chosen
            let line = Format.prescription(item, ladder: ladder, unit: settings.unit)
            return line.isEmpty ? nil : line
        }
        // No catalog item (e.g. a reused or coach-prescribed session) but a chosen
        // scheme is present. A coach prescription (P5.3) also carries a working load.
        guard !chosen.isEmpty else { return nil }
        var line = chosen.map(String.init).joined(separator: "-") + " reps"
        if isPrescribedMovement(name), session.prescribedLoadKg > 0 {
            line += " @ \(Format.weight(session.prescribedLoadKg, unit: settings.unit))"
        }
        return line
    }

    /// Whether `name` is a movement the coach prescribed for this session (P5.3) —
    /// the one the prescribed load pre-fills the keypad for.
    private func isPrescribedMovement(_ name: String) -> Bool {
        session.prescribedLoadKg > 0 && session.plannedExerciseNames.contains(name)
    }

    /// The effective rep-ladder for an exercise: the chosen scheme if the session
    /// carries one, else none. Drives the pre-seeded planned set rows and the
    /// default reps for each new set (feedback batch 6, items 1/2).
    private func effectiveLadder(for name: String) -> [Int]? {
        let chosen = session.plannedRepLadder
        return chosen.isEmpty ? nil : chosen
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
    private func openInlineEditor(for exercise: Exercise, editing: SetEntry? = nil, repsOverride: Int? = nil) {
        inlineExerciseID = exercise.id
        inlineExercise = exercise
        inlineEditingSet = editing
        inlineUnit = settings.unit
        if let editing {
            inlineWeight = Format.weightValue(editing.weight, unit: inlineUnit)
            inlineReps = editing.reps
            inlineBodyweight = editing.usesBodyweight
            inlinePerformedByID = editing.performedBy.flatMap { $0.isMe ? nil : $0.id }
            inlineRPE = editing.rpe.map { Int($0.rounded()) }
        } else {
            let loggedCount = session.orderedSets.filter { $0.exercise?.id == exercise.id }.count
            inlineReps = repsOverride ?? plannedReps(for: exercise, setIndex: loggedCount)
            inlineBodyweight = isBodyweight(exercise)
            inlinePerformedByID = nextPerson().flatMap { $0.isMe ? nil : $0.id }
            inlineRPE = nil

            // Weight defaulting is performer-specific: current-session work by
            // that person first, then that person's prior history, then any coach
            // prescription for the movement.
            let performer = people(for: inlinePerformedByID)
            if let last = lastSessionWeight(for: exercise, performerID: inlinePerformedByID) {
                inlineWeight = Format.weightValue(last, unit: inlineUnit)
                inlinePriorWeightHint = nil
            } else if let firstPrior = firstWorkingSetWeight(for: exercise, performedBy: performer) {
                inlineWeight = Format.weightValue(firstPrior, unit: inlineUnit)
                inlinePriorWeightHint = firstPrior
            } else {
                let prescribedKg = isPrescribedMovement(exercise.name) ? session.prescribedLoadKg : 0
                inlineWeight = prescribedKg > 0 ? Format.weightValue(prescribedKg, unit: inlineUnit) : ""
                inlinePriorWeightHint = nil
            }
        }
        weightFocused = true

        // First-time dumbbell info: show once when starting a dumbbell exercise.
        if !dumbbellInfoShown, case .dumbbell = exercise.equipmentValue {
            dumbbellInfoShown = true
            showDumbbellInfo = true
        }
    }

    /// The first working-set weight from the most recent prior session for this
    /// exercise, if any. nil when no prior data exists.
    private func firstWorkingSetWeight(for exercise: Exercise, performedBy person: Person?) -> Double? {
        WorkoutRepository.firstWorkingSetWeight(for: exercise, performedBy: person, excluding: session)
    }

    private func lastSessionWeight(for exercise: Exercise, performerID: UUID?) -> Double? {
        session.orderedSets.reversed().first {
            $0.exercise?.id == exercise.id && setPerformedBy($0, performerID: performerID)
        }?.weight
    }

    private func closeInlineEditor() {
        weightFocused = false
        inlineExerciseID = nil
        inlineExercise = nil
        inlineEditingSet = nil
    }

    private func recordInlineSet(for exercise: Exercise) {
        let parsed = Double(inlineWeight) ?? 0
        var kg = WorkoutMath.canonical(parsed, from: inlineUnit)
        if settings.plateRounding { kg = UnitEntry.plateRounded(kg: kg, unit: inlineUnit) }
        let rpe = inlineRPE.map(Double.init)
        if let editing = inlineEditingSet {
            // Omit isWarmup/note so a weight/reps edit never silently flips a
            // warm-up to a working set or erases the note (history-edit fix).
            try? WorkoutRepository.updateSet(editing, weightKg: kg, reps: inlineReps,
                                             rpe: .some(rpe),
                                             usesBodyweight: inlineBodyweight,
                                             performedBy: .some(people(for: inlinePerformedByID)),
                                             in: context)
        } else {
            addSet(to: exercise, weightKg: kg, reps: inlineReps, rpe: rpe, isWarmup: false,
                   usesBodyweight: inlineBodyweight, note: nil, performedBy: people(for: inlinePerformedByID))
        }
        closeInlineEditor()
    }

    private func people(for id: UUID?) -> Person? {
        guard let id else { return nil }
        return allPeople.first { $0.id == id }
    }

    // MARK: Columnar set table (A0-A8)

    private enum SetCol {
        static let num: CGFloat = 26
        static let prev: CGFloat = 50
        static let reps: CGFloat = 46
        static let check: CGFloat = 34
        static let gap: CGFloat = 7
    }

    private var whoColumnWidth: CGFloat {
        hasPartners ? 32 : SetCol.num
    }

    private var setColumnHeader: some View {
        HStack(spacing: SetCol.gap) {
            Text(hasPartners ? "WHO" : "Set")
                .frame(width: whoColumnWidth, alignment: .leading)
            Text("Prev")
                .frame(width: SetCol.prev, alignment: .leading)
            Text("Weight (\(settings.unit.abbreviation))")
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Reps")
                .frame(width: SetCol.reps, alignment: .center)
            Color.clear.frame(width: SetCol.check)
        }
        .font(.caption2).textCase(.uppercase).foregroundStyle(.tertiary)
        .lineLimit(1).minimumScaleFactor(0.5)
        .padding(.horizontal, 2)
    }

    private func setIndexBadge(_ label: String, isWarmup: Bool) -> some View {
        Group {
            if isWarmup {
                Text("W").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                    .frame(width: 22, height: 22).background(.orange.opacity(0.15), in: Circle())
            } else {
                Text(label).font(.subheadline.weight(.medium)).monospacedDigit()
            }
        }
        .frame(width: SetCol.num, alignment: .leading)
    }

    private func personColor(_ p: Person?) -> Color {
        guard let p, !p.isMe else { return .accentColor }
        let palette: [Color] = [.purple, .teal, .pink, .indigo, .orange, .mint]
        return palette[abs(p.id.hashValue) % palette.count]
    }

    private func performerChip(_ p: Person?) -> some View {
        let label = (p?.isMe ?? true) ? "M" : String((p?.name ?? "?").prefix(1)).uppercased()
        return Text(label)
            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(personColor(p), in: Circle())
            .accessibilityIdentifier("set.performer.\((p?.isMe ?? true) ? "Me" : (p?.name ?? "?"))")
    }

    private func performerName(_ id: UUID?) -> String {
        guard let id, let p = allPeople.first(where: { $0.id == id }) else { return "Me" }
        return p.name.components(separatedBy: " ").first ?? p.name
    }

    /// Working-set number assignments (warm-ups → "").
    private func workingNumbers(_ sets: [SetEntry]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        var n = 1
        for s in sets {
            if s.isWarmup { result[s.id] = ""; continue }
            result[s.id] = String(n); n += 1
        }
        return result
    }

    /// Next working-set number, with `extra` for pending rows.
    private func workingNumber(for exercise: Exercise, extra: Int = 0) -> Int {
        let sets = session.orderedSets.filter { $0.exercise?.id == exercise.id && !$0.isWarmup }
        return sets.count + 1 + extra
    }

    /// Compact previous-set reference, e.g. "60×8".
    private func previousReference(for exercise: Exercise, number: String) -> String {
        guard let ref = previousValues(for: exercise, number: number) else { return "" }
        return Format.previousShort(ref.weight, reps: ref.reps, unit: settings.unit)
    }

    /// Previous-set (weightKg, reps) for tap-to-prefill.
    private func previousValues(for exercise: Exercise, number: String) -> (weight: Double, reps: Int)? {
        guard let n = Int(number), n > 0 else { return nil }
        let lastSets = WorkoutRepository.lastTimeSets(for: exercise, excluding: session)
        guard n <= lastSets.count else { return nil }
        let s = lastSets[n - 1]
        return (s.weight, s.reps)
    }

    private var sessionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isManualLog { loggedDateBanner }
            if active.strengthSession?.id != session.id && !isManualLog {
                editableMetadataRow
            }
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

    private var coreSessionView: AnyView {
        AnyView(
            ScrollView { sessionContent }
                .navigationTitle(session.title.isEmpty ? "Workout" : session.title)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if active.strengthSession?.id == session.id {
                        VStack(spacing: 0) {
                            WorkoutElapsedHeader(clock: active.clock, isPaused: active.isPaused)
                            if model.hrm.currentBPM != nil {
                                liveHRBand
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 12) {
                            if let plan {
                                NavigationLink {
                                    RoutineDetailView(plan: plan, onEditorStart: { _ in })
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .accessibilityIdentifier("session.info")
                                .accessibilityLabel("Workout details")
                            }
                            Button {
                                showDeleteConfirm = true
                            } label: { Image(systemName: "trash") }
                                .foregroundStyle(.red)
                                .accessibilityIdentifier("session.delete")
                                .accessibilityLabel("Delete workout")
                            Button {
                                editedTitle = session.title
                                renamePresented = true
                            } label: { Image(systemName: "pencil") }
                                .accessibilityIdentifier("session.rename")
                                .accessibilityLabel("Rename workout")

                            Button {
                                Task { await saveToHealth() }
                            } label: { Image(systemName: healthSaved ? "checkmark.circle.fill" : "heart.text.square") }
                                .disabled(session.orderedSets.isEmpty)
                                .accessibilityIdentifier("session.saveHealth")
                                .accessibilityLabel(healthSaved ? "Saved to Apple Health" : "Save workout to Apple Health")
                        }
                    }
                }
                .overlay(alignment: .top) {
                    if healthSaved {
                        Text("Saved to Apple Health")
                            .font(.caption).padding(8)
                            .cadenceGlass(in: Capsule(), fallback: .thinMaterial)
                            .accessibilityIdentifier("session.healthSaved")
                    }
                }
        )
    }

    var body: some View {
        coreSessionView
        // Keep the screen awake during a live workout so it never locks between
        // sets. Manual logging is data entry, not training, so it's excluded.
        .keepAwake(!isManualLog)
        .sheet(isPresented: $pickerPresented) {
            ExercisePickerView { exercise in
                if !session.exercisesInOrder.contains(where: { $0.id == exercise.id }) &&
                   !session.plannedExerciseNames.contains(exercise.name) {
                    session.plannedExerciseNames.append(exercise.name)
                    try? context.save()
                }
                openInlineEditor(for: exercise)
            }
        }
        .sheet(isPresented: Binding(
            get: { swappingPlannedName != nil },
            set: { if !$0 { swappingPlannedName = nil } }
        )) {
            ExercisePickerView(action: .swap) { exercise in
                if let oldName = swappingPlannedName {
                    swapPlannedExercise(oldName: oldName, newName: exercise.name)
                    swappingPlannedName = nil
                }
            }
        }
        // Change which movement a logged exercise card actually is — moves every
        // set in the card to the picked exercise (history-edit "wrong movement" fix).
        .sheet(isPresented: Binding(
            get: { changingExerciseFor != nil },
            set: { if !$0 { changingExerciseFor = nil } }
        )) {
            ExercisePickerView(action: .use) { picked in
                if let old = changingExerciseFor, old.id != picked.id {
                    _ = try? WorkoutRepository.changeExercise(in: session, from: old, to: picked, in: context)
                    poke()
                }
                changingExerciseFor = nil
            }
        }
        .sheet(isPresented: $managePartnersPresented) { managePartnersSheet }
        .sheet(isPresented: $usePreviousPresented) {
            PreviousWorkoutPicker(excluding: session) { past in
                _ = try? WorkoutRepository.copyWorkout(from: past, into: session, in: context)
                poke()
            }
        }
        .sheet(isPresented: $showRPEInfo) {
            RPEInfoView()
        }
        .sheet(isPresented: $showWeightInfo) {
            weightInfoSheet
        }
        .sheet(isPresented: $showDumbbellInfo) {
            dumbbellInfoSheet
        }
        .fullScreenCover(isPresented: $coolingDown) {
            GuidedPhaseOverlay(
                title: "Cool Down",
                minutes: session.cooldownSeconds > 0 ? Int(session.cooldownSeconds / 60) : settings.cooldownMinutes,
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
        // Auto-start Watch HR for strength when no BLE strap is connected (FR-8).
        .onAppear {
            guard !isManualLog, model.watchAvailable else { return }
            if case .connected = model.hrm.state { return }
            model.startWatchStrength()
        }
        // Backing out of a freshly-started log with nothing entered shouldn't litter
        // history with an empty "Logged" row.
        .onDisappear { if isManualLog { cleanupEmptyLog() } }
        .onReceive(idleTimer) { _ in
            checkIdle()
            if active.strengthSession?.id == session.id { sampleHR() }
        }
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
                if !name.isEmpty {
                    if let p = try? WorkoutRepository.findOrCreatePerson(named: name, in: context) {
                        var ids = explicitRosterIDs()
                        if !ids.contains(p.id.uuidString) {
                            ids.append(p.id.uuidString)
                            session.activePartnerIDs = normalizedRosterIDs(ids)
                            try? context.save()
                        }
                    }
                }
                newPartnerName = ""
            }
            Button("Cancel", role: .cancel) { newPartnerName = "" }
        } message: {
            Text("Their sets are recorded separately and kept out of your PRs and Apple Health.")
        }
        .alert("Rename workout", isPresented: $renamePresented) {
            TextField("Title", text: $editedTitle)
                .accessibilityIdentifier("rename.field")
            Button("Save") {
                session.title = editedTitle.trimmingCharacters(in: .whitespaces)
                try? context.save()
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Delete this workout?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if active.strengthSession?.id == session.id {
                    active.endStrength()
                }
                try? WorkoutRepository.softDeleteSession(session, in: context)
                dismiss()
            }
            .accessibilityIdentifier("session.deleteConfirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All sets and exercises in this session will be removed. You can restore it from History → View Deleted.")
        }
        .sheet(isPresented: $datePickerPresented) {
            NavigationStack {
                DatePicker("Workout date", selection: Binding(
                    get: { session.date },
                    set: { session.date = $0; try? context.save() }
                ))
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Edit Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { datePickerPresented = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $endDatePickerPresented) {
            NavigationStack {
                DatePicker("End time", selection: Binding(
                    get: { session.endedAt ?? session.date },
                    set: { session.endedAt = $0; try? context.save() }
                ))
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Edit End Time")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { endDatePickerPresented = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("Remove this exercise?", isPresented: Binding(
            get: { exerciseToRemove != nil },
            set: { if !$0 { exerciseToRemove = nil } }
        ), titleVisibility: .visible) {
            Button("Remove exercise and all its sets", role: .destructive) {
                if let ex = exerciseToRemove {
                    let sets = session.orderedSets.filter { $0.exercise?.id == ex.id }
                    for s in sets { try? WorkoutRepository.deleteSet(s, in: context) }
                    session.plannedExerciseNames.removeAll { $0 == ex.name }
                    try? context.save()
                }
                exerciseToRemove = nil
            }
            Button("Cancel", role: .cancel) { exerciseToRemove = nil }
        }
    }

    /// Reminds the user which past date a manually-logged workout is being filed
    /// under (feedback batch 7 follow-up).
    private var loggedDateBanner: some View {
        Button { datePickerPresented = true } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.and.pencil")
                Text("Logging \(session.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Image(systemName: "calendar").font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("log.dateBanner")
    }

    private var editableMetadataRow: some View {
        HStack(spacing: 16) {
            Button { datePickerPresented = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar").font(.caption)
                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                }
                .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("session.editDate")

            if session.endedAt != nil {
                Button { endDatePickerPresented = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock").font(.caption)
                        if let end = session.endedAt {
                            Text(Format.duration(end.timeIntervalSince(session.date)))
                                .font(.subheadline)
                        }
                    }
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("session.editEndTime")
            }

            Spacer()
        }
    }

    // MARK: Partner bar (field-testing §04)

    // MARK: Partner bar (field-testing §04, Bug 4 fix)

    private var partnerBar: some View {
        HStack(spacing: 8) {
            Text("With:").font(.caption).foregroundStyle(.secondary)
            ForEach(roster) { p in
                performerChip(p)
                    .contextMenu {
                        if !p.isMe {
                            Button(role: .destructive) {
                                var ids = session.activePartnerIDs
                                ids.removeAll { $0 == p.id.uuidString }
                                session.activePartnerIDs = normalizedRosterIDs(ids)
                                try? context.save()
                            } label: { Label("Remove from session", systemImage: "person.slash") }
                        }
                    }
                if !p.isMe {
                    Text(p.name).font(.caption.weight(.medium))
                        .padding(.horizontal, 6)
                }
            }
            Button {
                addPartnerPresented = true
            } label: { Image(systemName: "plus.circle") }
                .accessibilityIdentifier("partner.add")
                .accessibilityLabel("Add training partner")
            Button {
                managePartnersPresented = true
            } label: { Image(systemName: "gearshape") }
                .accessibilityIdentifier("partner.manage")
                .accessibilityLabel("Manage training partners")
            Spacer()
        }
    }

    // MARK: Plan banner (preset scheme, round4b §B-1)

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
            HStack {
                Text(name).font(.headline)
                    .accessibilityIdentifier("exerciseCard.\(name)")
                Spacer()
                Button {
                    swappingPlannedName = name
                } label: {
                    Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.bordered).controlSize(.mini)
                .accessibilityIdentifier("planned.swap.\(name)")
            }
            if let rx = prescription(for: name) {
                Text(rx).font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("session.rx.\(name)")
            } else {
                Text("Planned — tap to log").font(.caption).foregroundStyle(.secondary)
            }
            if let ex = inlineExercise, ex.name == name {
                activeSetRow(for: ex)
            } else {
                Button {
                    if let ex = try? WorkoutRepository.findOrCreateExercise(named: name, in: context) {
                        openInlineEditor(for: ex)
                    }
                } label: { Label("Add Set", systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small)
                    .accessibilityIdentifier("set.add.\(name)")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Exercise card

    // MARK: Exercise card (columnar A6)

    @ViewBuilder
    private func exerciseCard(_ exercise: Exercise) -> some View {
        let sets = session.orderedSets.filter { $0.exercise?.id == exercise.id }
        let pending = max(0, plannedSetCount(for: exercise.name) - sets.count)
        let isActive = inlineExerciseID == exercise.id
        let numbers = workingNumbers(sets)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(exercise.name).font(.headline)
                    .accessibilityIdentifier("exerciseCard.\(exercise.name)")
                Spacer()
                Menu {
                    Button { changingExerciseFor = exercise } label: {
                        Label("Change exercise", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .accessibilityIdentifier("exercise.changeExercise.\(exercise.name)")
                    Button(role: .destructive) { exerciseToRemove = exercise } label: {
                        Label("Remove exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.headline)
                        .foregroundStyle(.secondary).frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("exercise.menu.\(exercise.name)")
                .accessibilityLabel("Exercise options")
            }
            contextLine(for: exercise)

            if !sets.isEmpty || isActive || pending > 0 { setColumnHeader }

            ForEach(Array(sets.enumerated()), id: \.element.id) { idx, set in
                // Editing a logged set swaps that row for the inline editor in
                // place, so tapping a weight/reps value visibly enters edit mode
                // (history-edit discoverability fix). New sets use the trailing row.
                if inlineEditingSet?.id == set.id {
                    activeSetRow(for: exercise)
                } else {
                    completedSetRow(set, number: numbers[set.id] ?? "", exercise: exercise)
                }
                if idx < sets.count - 1 || (isActive && inlineEditingSet == nil) || pending > 0 {
                    Divider()
                }
            }

            if isActive && inlineEditingSet == nil { activeSetRow(for: exercise) }

            ForEach(0..<pending, id: \.self) { offset in
                let n = workingNumber(for: exercise, extra: offset)
                pendingRow(for: exercise, number: String(n),
                           reps: plannedReps(for: exercise, setIndex: sets.count + offset))
            }

            if !isActive {
                HStack(spacing: 10) {
                    Button { openInlineEditor(for: exercise) } label: {
                        Label("Add set", systemImage: "plus").frame(maxWidth: .infinity).lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("set.add.\(exercise.name)")

                    if let last = sets.last {
                        Button {
                            addSet(to: exercise, weightKg: last.weight, reps: last.reps, rpe: last.rpe,
                                   isWarmup: last.isWarmup, usesBodyweight: last.usesBodyweight, note: nil,
                                   performedBy: nextPerson())
                        } label: {
                            Label("Repeat", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("set.repeat.\(exercise.name)")
                    }
                }
                .controlSize(.regular)
                .padding(.top, 2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    /// A not-yet-logged planned set: its rung number, target reps, and a tap-to-log
    /// affordance (feedback batch 6 item 2).
    @ViewBuilder
    private func pendingRow(for exercise: Exercise, number: String, reps: Int) -> some View {
        Button { openInlineEditor(for: exercise, repsOverride: reps) } label: {
            HStack(spacing: SetCol.gap) {
                if hasPartners {
                    performerChip(nextPerson())
                } else {
                    setIndexBadge(number, isWarmup: false)
                }
                Text(previousReference(for: exercise, number: number))
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    .frame(width: SetCol.prev, alignment: .leading)
                Text("\(reps) reps").font(.subheadline).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: SetCol.reps)
                Image(systemName: "plus.circle").foregroundStyle(.tint).frame(width: SetCol.check)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("set.pending.\(exercise.name).\(number)")
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

    // MARK: Completed set row (columnar A2)

    @ViewBuilder
    private func completedSetRow(_ set: SetEntry, number: String, exercise: Exercise) -> some View {
        HStack(spacing: SetCol.gap) {
            if hasPartners {
                performerChip(set.performedBy)
            } else {
                setIndexBadge(number, isWarmup: set.isWarmup)
            }

            Text(set.isWarmup ? "" : previousReference(for: exercise, number: number))
                .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                .frame(width: SetCol.prev, alignment: .leading)

            Button {
                openInlineEditor(for: exercise, editing: set)
            } label: {
                if set.usesBodyweight && set.weight <= 0 {
                    Text("BW").monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(Format.weightValue(set.weight, unit: settings.unit))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("set.editWeight.\(exercise.name).\(number)")

            Button {
                openInlineEditor(for: exercise, editing: set)
            } label: {
                Text("\(set.reps)").monospacedDigit().frame(width: SetCol.reps)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("set.editReps.\(exercise.name).\(number)")

            if let rpe = set.rpe, !set.isWarmup {
                Text("\(Int(rpe.rounded()))")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 3))
                    .accessibilityIdentifier("set.rpe.\(exercise.name).\(number)")
                    .accessibilityLabel("RPE \(Int(rpe.rounded()))")
            }

            Group {
                if isAllTimePR(set, exercise: exercise) {
                    Image(systemName: "trophy.fill").foregroundStyle(.orange)
                        .accessibilityIdentifier("set.prBadge")
                        .accessibilityLabel("Personal record")
                } else {
                    Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                        .accessibilityLabel("Set completed")
                }
            }
            .frame(width: SetCol.check)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu { rowMenu(for: set, exercise: exercise) }
        // Keep the inner weight/reps/performer controls individually accessible —
        // a `.contextMenu` otherwise collapses the row into one a11y element,
        // hiding their identifiers from UI tests (and VoiceOver).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("set.row.\(exercise.name).\(number)")
    }

    // MARK: PR detection for display

    private func isAllTimePR(_ set: SetEntry, exercise: Exercise) -> Bool {
        // Partner sets never earn the owner's PR badge (field-testing §04).
        guard set.isOwnerSet, !set.isWarmup, set.reps > 0, set.effectiveLoadKg > 0 else { return false }
        let previous = (exercise.sets ?? [])
            .filter { $0.isOwnerSet && $0.completedAt < set.completedAt }
            .map { SetSample.from($0) }
        let candidate = SetSample.from(set)
        return PRCalculator.isNewPR(candidate: candidate, previous: previous,
                                    rule: settings.prRule, formula: settings.formula)
    }

    // MARK: Per-row context menu (A4)

    @ViewBuilder
    private func rowMenu(for set: SetEntry, exercise: Exercise) -> some View {
        Button {
            try? WorkoutRepository.updateSet(set, isWarmup: !set.isWarmup, in: context)
        } label: {
            Label(set.isWarmup ? "Mark as working set" : "Mark as warm-up",
                  systemImage: set.isWarmup ? "flame.fill" : "flame")
        }
        if isBodyweight(exercise) {
            Button {
                try? WorkoutRepository.updateSet(set, usesBodyweight: !set.usesBodyweight, in: context)
            } label: {
                Label(set.usesBodyweight ? "Remove bodyweight" : "Mark bodyweight",
                      systemImage: "figure.stand")
            }
        }
        if hasPartners {
            Menu {
                Button("Me") {
                    try? WorkoutRepository.updateSet(set, performedBy: .some(nil), in: context)
                }
                ForEach(attributablePartners) { p in
                    Button(p.name) {
                        try? WorkoutRepository.updateSet(set, performedBy: .some(p), in: context)
                    }
                }
            } label: { Label("Performed by", systemImage: "person") }
        }
        Divider()
        Button(role: .destructive) {
            try? WorkoutRepository.deleteSet(set, in: context)
        } label: { Label("Delete set", systemImage: "trash") }
    }

    // MARK: Inline set editor (replaces WeightKeypadSheet)

    // MARK: Active entry row (columnar A3)

    @ViewBuilder
    private func activeSetRow(for exercise: Exercise) -> some View {
        let parsed = Double(inlineWeight) ?? 0
        let kg = WorkoutMath.canonical(parsed, from: settings.unit)
        let effectiveKg = exercise.prospectiveEffectiveLoadKg(rawWeightKg: kg)
        let altUnit: MeasurementUnitPreference = settings.unit == .kilograms ? .pounds : .kilograms
        let canSave = inlineReps > 0
        let number = String(workingNumber(for: exercise))
        let wouldBePR = canSave && WorkoutRepository.wouldBePR(
            exercise: exercise, weightKg: effectiveKg, reps: inlineReps, isWarmup: false,
            rule: settings.prRule, formula: settings.formula)

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: SetCol.gap) {
                if hasPartners {
                    Menu {
                        Button {
                            inlinePerformedByID = nil
                        } label: {
                            HStack { Text("Me"); if inlinePerformedByID == nil { Image(systemName: "checkmark") } }
                        }
                        ForEach(attributablePartners) { p in
                            Button {
                                inlinePerformedByID = p.id
                            } label: {
                                HStack { Text(p.name); if inlinePerformedByID == p.id { Image(systemName: "checkmark") } }
                            }
                        }
                    } label: {
                        performerChip(people(for: inlinePerformedByID))
                    }
                    .accessibilityIdentifier("inline.performer")
                    .accessibilityLabel("Performed by")
                } else {
                    setIndexBadge(number, isWarmup: false)
                }

                Button {
                    if let (w, r) = previousValues(for: exercise, number: number) {
                        inlineWeight = Format.weightValue(w, unit: settings.unit)
                        inlineReps = r
                    }
                } label: {
                    Text(previousReference(for: exercise, number: number))
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        .frame(width: SetCol.prev, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Use previous set values")

                TextField("0", text: $inlineWeight)
                    .keyboardType(.decimalPad).focused($weightFocused)
                    .multilineTextAlignment(.center).monospacedDigit()
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(weightFocused ? Color.accentColor : Color(.separator),
                                lineWidth: weightFocused ? 1.5 : 0.5))
                    .accessibilityIdentifier("inline.weight")

                TextField("0", value: $inlineReps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center).monospacedDigit()
                    .frame(width: SetCol.reps, height: 36)
                    .background(.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 0.5))
                    .accessibilityIdentifier("inline.reps")

                Button { recordInlineSet(for: exercise) } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title).foregroundStyle(canSave ? .green : Color(.tertiaryLabel))
                }
                .buttonStyle(.plain).disabled(!canSave)
                .frame(width: SetCol.check)
                .accessibilityIdentifier("inline.save")
                .accessibilityLabel("Save set")
            }

            HStack(spacing: 10) {
                if parsed > 0 {
                    Text("\u{2248} \(Format.weightValue(kg, unit: altUnit)) \(altUnit.abbreviation)")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityIdentifier("inline.alt")
                }
                if isBodyweight(exercise) {
                    Toggle(isOn: $inlineBodyweight) {
                        Text("BW").lineLimit(1).fixedSize()
                    }
                    .toggleStyle(.button).controlSize(.mini)
                    .fixedSize()
                    .accessibilityIdentifier("inline.bodyweight")
                    .accessibilityLabel("Bodyweight")
                }
                // Weight info button (barbell/bodyweight/dumbbell guidance)
                Button { showWeightInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.caption2).foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("inline.weightInfo")
                .accessibilityLabel("Weight entry help")
                HStack(spacing: 3) {
                    Text("RPE").font(.caption2).foregroundStyle(.secondary)
                    if let rpe = inlineRPE {
                        Text("\(rpe)").font(.caption.monospacedDigit()).foregroundStyle(.primary)
                        Button {
                            inlineRPE = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear RPE")
                    } else {
                        Text("none").font(.caption).foregroundStyle(.tertiary)
                    }
                    Stepper("RPE", value: Binding(
                        get: { inlineRPE ?? 5 },
                        set: { inlineRPE = $0 }
                    ), in: 1...10)
                    .labelsHidden()
                    .scaleEffect(0.8)
                    Button { showRPEInfo = true } label: {
                        Image(systemName: "info.circle").font(.caption2).foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("RPE help")
                }
                .accessibilityIdentifier("inline.rpe")
                if wouldBePR {
                    Label("PR", systemImage: "trophy.fill")
                        .font(.caption2.bold()).foregroundStyle(.orange)
                }
                Spacer()
                if inlineEditingSet != nil {
                    Button(role: .destructive) {
                        if let set = inlineEditingSet {
                            try? WorkoutRepository.deleteSet(set, in: context)
                        }
                        closeInlineEditor()
                    } label: {
                        Image(systemName: "trash").font(.subheadline)
                    }
                    .buttonStyle(.plain).foregroundStyle(.red)
                    .accessibilityIdentifier("inline.delete")
                    .accessibilityLabel("Delete set")
                }
                Button("Cancel") { closeInlineEditor() }
                    .font(.caption)
                    .accessibilityIdentifier("inline.cancel")
            }
            .padding(.leading, whoColumnWidth + SetCol.gap)

            // Prior-weight hint for first set of an exercise.
            if let hint = inlinePriorWeightHint, weightFocused {
                Text("Previously started this exercise at \(Format.weight(hint, unit: settings.unit))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, whoColumnWidth + SetCol.gap)
            }
        }
        .padding(8)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Writes a summary HKWorkout for this session (FR-4.3). Detailed sets stay
    /// local; only duration + estimated energy go to Health. HR samples are
    /// included when a BLE strap was connected (FR-2.3).
    private func saveToHealth() async {
        let sets = session.orderedSets
        guard let first = sets.first?.completedAt else { return }
        let last = sets.last?.completedAt ?? first
        // Minimum 1-minute duration so Health accepts it.
        let end = max(last, first.addingTimeInterval(60))
        let minutes = end.timeIntervalSince(first) / 60
        let kcal = max(30, round(CardioMath.strengthCaloriesPerMinute * minutes))
        let bpmValues = hrSamples.map(\.bpm)
        let summary = StrengthWorkoutSummary(
            id: session.id, start: first, end: end,
            activeEnergyKcal: kcal,
            hrSamples: hrSamples,
            avgHR: bpmValues.isEmpty ? nil : bpmValues.reduce(0, +) / Double(bpmValues.count),
            maxHR: bpmValues.max()
        )
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
        WorkoutCues.endBeepSequence(enabled: settings.workoutSounds)
        model.stopWatchWorkout()
        if settings.autoSaveHealth, session.healthKitWorkoutUUID == nil, !session.orderedSets.isEmpty {
            Task { await saveToHealth() }
        }
        active.endStrength()
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("[Cadence] failed to save session on end: \(error.localizedDescription)")
            #endif
        }
        // Yield to next MainActor cycle so SwiftData propagates to @Query
        // subscribers before we set finishedSummary (coach recomputes from stale
        // sessions otherwise).
        Task { @MainActor in
            await Task.yield()
            active.finishedSummary = FinishedSummary(data: .from(session: session, hrSamples: hrSamples))
        }
        dismiss()
    }

    /// A compact live HR readout band shown under the elapsed clock during a
    /// strength workout when a BLE strap is connected (FR-2.3).
    private var liveHRBand: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(.red)
            if let bpm = model.hrm.currentBPM {
                Text("\(Int(bpm)) bpm")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            if let battery = model.hrm.battery {
                Image(systemName: battery <= 10 ? "battery.0" : "battery.75")
                    .font(.caption2)
                    .foregroundStyle(battery <= 10 ? .red : .secondary)
                Text("\(battery)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if model.hrm.criticalBattery {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .cadenceGlass(in: Rectangle(), fallback: .ultraThinMaterial)
    }

    /// Samples the live BPM from the connected BLE strap into `hrSamples` (FR-2.3).
    private func sampleHR() {
        guard let bpm = model.hrm.currentBPM, bpm > 0 else { return }
        let now = Date().timeIntervalSince(session.date)
        hrSamples.append(HRSamplePoint(t: now, bpm: bpm))
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

    private func swapPlannedExercise(oldName: String, newName: String) {
        guard oldName != newName else { return }
        var names = session.plannedExerciseNames
        if let idx = names.firstIndex(of: oldName) {
            names[idx] = newName
        }
        session.plannedExerciseNames = names
        _ = try? WorkoutRepository.findOrCreateExercise(named: newName, in: context)
        try? context.save()
        poke()
    }

    // MARK: Manage partners (opt-in roster, field-testing §04 bug fix)

    /// Discoverable partner management: check/uncheck who is in the session and
    /// add new partners. Unchecking the last partner correctly returns to solo
    /// (partners are opt-in — an empty roster never re-shows everyone).
    private var managePartnersSheet: some View {
        NavigationStack {
            List {
                if hasPartners {
                    Section {
                        ForEach(Array(roster.enumerated()), id: \.element.id) { index, person in
                            HStack {
                                performerChip(person)
                                Text(person.isMe ? "Me" : person.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button {
                                    moveRosterMember(from: index, by: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .disabled(index == 0)
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("partner.order.up.\(person.isMe ? "Me" : person.name)")
                                .accessibilityLabel("Move \(person.isMe ? "Me" : person.name) earlier")

                                Button {
                                    moveRosterMember(from: index, by: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .disabled(index >= roster.count - 1)
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("partner.order.down.\(person.isMe ? "Me" : person.name)")
                                .accessibilityLabel("Move \(person.isMe ? "Me" : person.name) later")
                            }
                        }
                    } header: {
                        Text("Order")
                    } footer: {
                        Text("The logger rotates through this order after each saved set.")
                    }
                }

                Section {
                    ForEach(allPeople.filter { !$0.isMe }) { p in
                        Button { togglePartnerScope(p) } label: {
                            HStack {
                                Text(p.name).foregroundStyle(.primary)
                                Spacer()
                                if session.activePartnerIDs.contains(p.id.uuidString) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityIdentifier("partner.manage.row.\(p.name)")
                    }
                    HStack {
                        TextField("New partner name", text: $newPartnerName)
                            .accessibilityIdentifier("partner.manage.nameField")
                        Button("Add") { addAndScopePartner() }
                            .disabled(newPartnerName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("partner.manage.add")
                    }
                } header: {
                    Text("Training partners")
                } footer: {
                    Text("Partners are optional. Their sets are recorded separately and kept out of your PRs and Apple Health.")
                }
            }
            .navigationTitle("Partners")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { managePartnersPresented = false }
                        .accessibilityIdentifier("partner.manage.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Adds or removes a partner from this session's roster.
    private func togglePartnerScope(_ p: Person) {
        var ids = explicitRosterIDs()
        if let idx = ids.firstIndex(of: p.id.uuidString) {
            ids.remove(at: idx)
        } else {
            ids.append(p.id.uuidString)
        }
        session.activePartnerIDs = normalizedRosterIDs(ids)
        try? context.save()
    }

    /// Creates a partner (if new) and scopes them to this session.
    private func addAndScopePartner() {
        let name = newPartnerName.trimmingCharacters(in: .whitespaces)
        defer { newPartnerName = "" }
        guard !name.isEmpty,
              let p = try? WorkoutRepository.findOrCreatePerson(named: name, in: context) else { return }
        var ids = explicitRosterIDs()
        if !ids.contains(p.id.uuidString) {
            ids.append(p.id.uuidString)
            session.activePartnerIDs = normalizedRosterIDs(ids)
            try? context.save()
        }
    }

    private func nextPerson() -> Person? {
        guard hasPartners else { return nil }
        let ordered = roster
        guard !ordered.isEmpty else { return nil }
        guard let last = session.orderedSets.reversed().first(where: { set in
            ordered.contains { setPerformedBy(set, person: $0) }
        }), let lastIndex = ordered.firstIndex(where: { setPerformedBy(last, person: $0) }) else {
            return ordered.first
        }
        return ordered[(lastIndex + 1) % ordered.count]
    }

    private func setPerformedBy(_ set: SetEntry, person: Person) -> Bool {
        if person.isMe { return set.isOwnerSet }
        return set.performedBy?.id == person.id
    }

    private func setPerformedBy(_ set: SetEntry, performerID: UUID?) -> Bool {
        guard let performerID else { return set.isOwnerSet }
        return set.performedBy?.id == performerID
    }

    private func explicitRosterIDs() -> [String] {
        let current = session.activePartnerIDs
        guard hasPartners else { return current }
        let ids = roster.map { $0.id.uuidString }
        return ids.isEmpty ? current : ids
    }

    private func normalizedRosterIDs(_ ids: [String]) -> [String] {
        let valid = Set(allPeople.map { $0.id.uuidString })
        var seen = Set<String>()
        let cleaned = ids.filter { valid.contains($0) && seen.insert($0).inserted }
        let partnerIDs = Set(allPeople.filter { !$0.isMe }.map { $0.id.uuidString })
        return cleaned.contains(where: { partnerIDs.contains($0) }) ? cleaned : []
    }

    private func moveRosterMember(from index: Int, by offset: Int) {
        var ids = explicitRosterIDs()
        let target = index + offset
        guard ids.indices.contains(index), ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        session.activePartnerIDs = normalizedRosterIDs(ids)
        try? context.save()
    }

    private var weightInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let ex = inlineExercise {
                    switch ex.resolvedLoadAccountingMode {
                    case .barbell:
                        Text("Barbell Weight")
                            .font(.headline)
                        Text("Enter the added plate load only. The bar weight (\(Format.weight(ex.effectiveDefaultBarWeightKg, unit: settings.unit))) is added automatically for calculations.\n\nEnter 0 when using only the bar or bodyweight. Bar weight is added separately for barbell calculations.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .bodyweight:
                        Text("Bodyweight Exercise")
                            .font(.headline)
                        Text("Enter 0 when using only your bodyweight. Enter a positive value for added weight (e.g., weighted vest, dip belt).\n\nThe app tracks added load; bodyweight is yours alone.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .dualDumbbell, .isolateralDumbbell:
                        Text("Dumbbell Weight")
                            .font(.headline)
                        Text("Enter the weight of one dumbbell. The app accounts for paired, single, and isolateral dumbbell movements in calculations.\n\nFor standard two-dumbbell exercises (bench press, curls, etc.), your entered weight is doubled automatically.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .singleDumbbell:
                        Text("Dumbbell Weight")
                            .font(.headline)
                        Text("Enter the weight of the single dumbbell used. This exercise uses one dumbbell at a time (e.g., goblet squat, skullcrusher).\n\nThe entered weight is used as-is for calculations.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case nil:
                        Text("Weight Entry")
                            .font(.headline)
                        Text("Enter the weight as you would normally. This exercise uses standard weight accounting — what you enter is what's used for PRs, volume, and trends.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Weight Entry")
                        .font(.headline)
                    Text("Enter the weight you lifted. For barbell exercises, enter the plate load — the bar weight is added automatically. For dumbbell exercises, enter the weight of one dumbbell.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Weight Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showWeightInfo = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var dumbbellInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dumbbell Weight Entry")
                    .font(.headline)
                Text("For dumbbell exercises, enter the weight of a single dumbbell — the app handles the accounting automatically:\n\n• **Two-dumbbell exercises** like bench press or curls: your entered weight is doubled for calculations (you're lifting two of them).\n\n• **Single-dumbbell exercises** like goblet squats or skullcrushers: your entered weight is used as-is.\n\n• **Isolateral exercises** like one-arm rows: your entered weight is doubled for comparison against barbell movements.\n\nThis way you can always enter what's printed on the dumbbell, and the math works correctly behind the scenes.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Dumbbell Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Got it") { showDumbbellInfo = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
