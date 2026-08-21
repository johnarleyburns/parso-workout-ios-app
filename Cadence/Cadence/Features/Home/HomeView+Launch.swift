import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension HomeView {
    func start(_ type: WorkoutType) {
        // Only "Other Cardio" carries a custom title; clear any stale one first.
        otherCardioTitle = nil
        if type.isStrength {
            // Weights is handled inside the sheet (WeightsStartView), so this
            // branch is normally unreached.
            launchFromPicker(.strength)
        } else if type == .swim {
            guard acquireCardio(.swim(id: UUID())) else { return }
            swimPresented = true
        } else if type.usesGPS, let c = type.cardioType {
            startOutdoorWithGoal(c)
        } else if type == .hiit || type == .boxing {
            intervalType = type
        } else if let c = type.cardioType {
            begin(.timer(c))
        }
    }
    func startQuickStartStrength() {
        guard active.liveWorkout.active == nil else {
            showWorkoutConflict = true
            return
        }
        pendingPlan = nil
        startWarmupAfterHRGate = false
        if settings.warmupMinutes > 0 {
            warmupActive = true
        } else {
            launch(.strength, startCue: .single)
        }
    }
    /// "Other Cardio" chosen (feedback batch 6 item 3): stash its description, then
    /// route to the GPS recorder or the indoor timer per the user's GPS toggle.
    func startOtherCardio(description: String, gps: Bool) {
        outdoorGoalMeters = nil   // Other Cardio carries no distance goal.
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        otherCardioTitle = trimmed.isEmpty ? nil : trimmed
        begin(gps ? .outdoor(.other) : .timer(.other))
    }

    /// Presents the optional distance-goal chooser before a run/walk/cycle (batch 8).
    /// A fresh start clears any prior goal; the chooser sets it (or leaves it nil).
    func startOutdoorWithGoal(_ type: CardioType) {
        otherCardioTitle = nil
        outdoorGoalMeters = nil
        cardioGoalFor = type
    }

    /// Launches a strength/plan workout chosen from the Start sheet without a Home
    /// flash (P1 #1/#5). Strength workouts route through the HR gate first, then
    /// the get-ready countdown.
    /// `skipCountdown` makes "Quick Start" truly immediate — no countdown
    /// regardless of the Settings value (which still applies to library/reuse/warm-up).
    func launchFromPicker(_ kind: PendingWorkout.Kind, skipCountdown: Bool = false) {
        if skipCountdown {
            launch(kind)
        } else {
            proceedFromHRGate(kind, useHR: false)
        }
    }
    func begin(_ kind: PendingWorkout.Kind) {
        hrGateKind = kind
    }

    /// Called after the HR gate closes.  If the countdown is enabled, show it;
    /// otherwise launch immediately.
    func proceedFromHRGate(_ kind: PendingWorkout.Kind, useHR: Bool) {
        if startWarmupAfterHRGate {
            startWarmupAfterHRGate = false
            warmupActive = true
            return
        }
        if case .interval = kind {
            launch(kind)
            return
        }
        if kind.isStrength || settings.preWorkoutCountdown > 0 {
            pending = PendingWorkout(kind: kind)
        } else {
            launch(kind)
        }
    }
    func launch(_ kind: PendingWorkout.Kind, startCue: WorkoutStartCue = .countdown) {
        guard active.liveWorkout.active == nil else { showWorkoutConflict = true; return }
        switch kind {
        case .strength:
            if let plan = pendingPlan {
                pendingPlan = nil
                startStrengthAfterLease(startCue: startCue) { try? materializePlan(plan) }
            } else { startStrengthAfterLease(startCue: startCue) { try? WorkoutRepository.createSession(title: "Workout", in: context) } }
        case .plan(let plan, let ladder):
            startStrengthAfterLease(startCue: startCue) { try? WorkoutRepository.startSession(from: plan, repLadder: ladder, in: context) }
        case .reuse(let past):
            startStrengthAfterLease(startCue: startCue) { try? WorkoutRepository.reuseSession(from: past, in: context) }
        case .outdoor(let c):
            guard acquireCardio(.outdoorCardio(id: UUID(), type: c)) else { return }
            outdoorType = c
        case .interval(let l):
            guard acquireCardio(.interval(id: UUID(), type: l.saveType)) else { return }
            intervalLaunch = l
        case .timer(let c):
            guard acquireCardio(.timerCardio(id: UUID(), type: c)) else { return }
            cardioType = c
        }
    }

    func startStrengthAfterLease(startCue: WorkoutStartCue,
                                         create: () -> WorkoutSession?) {
        let intent = LiveWorkoutStartIntent(kind: .strength(sessionID: UUID()),
                                             routePayload: "strength",
                                             origin: .finalCommit)
        guard case .granted(let lease) = active.liveWorkout.requestStart(intent: intent,
                                                                            descriptorName: "Workout") else {
            showWorkoutConflict = true
            return
        }
        guard let session = create(), active.startStrength(session, lease: lease) else {
            _ = active.liveWorkout.release(lease)
            return
        }
        playStartCue(startCue)
    }

    func acquireCardio(_ kind: LiveWorkoutKind) -> Bool {
        guard active.liveWorkout.active == nil else { showWorkoutConflict = true; return false }
        let name: String
        switch kind {
        case .outdoorCardio(_, let type), .timerCardio(_, let type), .interval(_, let type): name = type.displayName
        case .swim: name = "Swim"
        case .strength: name = "Workout"
        }
        let intent = LiveWorkoutStartIntent(kind: kind, routePayload: kindName(kind), origin: .homeStart)
        guard case .granted = active.liveWorkout.requestStart(intent: intent, descriptorName: name) else {
            showWorkoutConflict = true
            return false
        }
        return true
    }

    func kindName(_ kind: LiveWorkoutKind) -> String {
        switch kind {
        case .outdoorCardio(_, let type), .timerCardio(_, let type), .interval(_, let type): return type.rawValue
        case .swim: return "swim"
        case .strength: return "strength"
        }
    }

    func releaseCardioWorkout() {
        guard active.strengthSession == nil else { return } // Every cardio dismiss here stops the watch session (2026-08-20 #5).
        model.stopWatchWorkout(); if let lease = active.liveWorkout.lease { _ = active.liveWorkout.release(lease) }
    }

    func finishWarmup(elapsedSeconds secs: Int, startCue: WorkoutStartCue) {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            launch(.strength, startCue: startCue)
            // Record the actual warm-up time on the session just created
            // (feedback batch 6).
            active.strengthSession?.warmupSeconds = Double(secs)
            try? context.save()
            warmupActive = false
        }
    }

    func playStartCue(_ cue: WorkoutStartCue) {
        switch cue {
        case .countdown:
            WorkoutCues.startBeepSequence(enabled: settings.workoutSounds)
        case .single:
            WorkoutCues.singleStart(enabled: settings.workoutSounds)
        case .none:
            break
        }
    }

    /// Handles an add-on selection from the post-completion coach card. Encouraged
    /// and neutral options launch directly; warn options show a confirmation dialog.
    func handleAddOn(_ session: CoachSession, _ status: CoachAddOnStatus) {
        switch CoachRouter.addOnAction(status: status) {
        case .launch:
            launchDecision(session)
        case .warn:
            warnAddOn = (session, status)
        }
    }

    /// Launch from the CoachDecision engine. Every trainable recommendation lands
    /// on that workout's setup/settings surface first — never directly into an
    /// active recorder (audio/coach routing plan §D). The recorder begins only
    /// after the user confirms from the setup screen. The pure routing decision
    /// lives in `CoachRouter` (unit-tested); this only performs the UI action.
    func launchDecision(_ session: CoachSession) {
        switch CoachRouter.destination(for: session) {
        case .planEditor(let plan):
            path.append(HomeRoute.workoutEditor(plan))
        case .emptyEditor(let title):
            // Defensive: a strength session with no exercises should never dead-end
            // back to Home (issue 3). Open an empty editor titled from the session.
            let fallback = EditablePlan(
                title: title,
                warmupMinutes: settings.warmupMinutes,
                cooldownMinutes: settings.cooldownMinutes,
                exercises: [])
            path.append(HomeRoute.workoutEditor(fallback))
        case .outdoorCardio(let type):
            startOutdoorWithGoal(type)             // → CardioGoalSheet → HR gate → recorder
        case .swim:
            swimPresented = true                   // SwimRecordView opens to its setup screen
        case .interval(let workoutType):
            intervalType = workoutType             // → IntervalSetupView (protocol picker)
        case .timerCardio(let type, let suggestedMinutes):
            timerCardioSetup = TimerCardioSetup(type: type, suggestedMinutes: suggestedMinutes)
        case .none:
            break
        }
    }

    /// User picked a different cardio modality from the alternatives chooser.
    /// Records the preference so Coach learns, dismisses the sheet, then launches
    /// the chosen session on the next runloop turn — deferring the launch lets the
    /// alternatives sheet finish dismissing before the cardio setup sheet/cover
    /// presents (SwiftUI drops a present that races an in-flight dismiss).
    func chooseAlternative(_ session: CoachSession) {
        let decision = coachDecision
        settings.recordCoachSelection(session, alternatives: [decision.primary] + decision.alternatives)
        showAlternatives = false
        Task { @MainActor in
            await Task.yield()
            launchDecision(session)
        }
    }

    /// "Something else?" from the alternatives sheet → the full cardio picker,
    /// after the sheet finishes dismissing (same one-runloop deferral).
    func openFullCardioPicker() {
        showAlternatives = false
        Task { @MainActor in
            await Task.yield()
            cardioPickerPresented = true
        }
    }

    /// "Do a strength workout anyway" (coach-user-control Phase 5): build the
    /// best-fit full-body session and open it in the plan editor for perusal.
    func strengthAnyway() {
        let facts = coachSnapshot.coachFacts.withStepSummary(from: activityTrend)
        guard let plan = EditablePlan.strengthAnyway(
            facts: facts,
            desiredSetsPerExercise: settings.coachSchedulePreferences.desiredSetsPerExercise
        ) else { return }
        path.append(HomeRoute.workoutEditor(plan))
    }

    /// Swap one component of a two-a-day plan: strength → the strength start
    /// surface (Coach's Workout / presets / reuse); cardio → the full picker.
    func swapComponent(_ session: CoachSession) {
        if session.kind == .strength { weightsStartPresented = true }
        else { cardioPickerPresented = true }
    }

    func handleEditorStart(_ plan: EditablePlan) {
        pendingPlan = plan
        if plan.warmupMinutes > 0 {
            startWarmupAfterHRGate = true
        }
        proceedFromHRGate(.strength, useHR: false)
    }

    func materializePlan(_ plan: EditablePlan) throws -> WorkoutSession {
        let session = try WorkoutRepository.createSession(title: plan.title, in: context)
        plan.apply(to: session)
        for name in plan.exercises.map(\.name) {
            _ = try WorkoutRepository.findOrCreateExercise(named: name, in: context)
        }
        session.cooldownSeconds = Double(plan.cooldownMinutes * 60)
        try context.save()
        return session
    }
}
