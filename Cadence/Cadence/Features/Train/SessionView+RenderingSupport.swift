import SwiftUI
import Foundation
import CadenceCore
import CadenceFeatures
/// Keeps the inline editor's generic view tree out of SessionView's already
/// large result builder. This is intentionally a presentation-only wrapper;
/// all workout mutations remain owned by SessionView.
private struct SessionInlineEditorSheet: View {
    let config: InlineEditorConfig
    let exercise: Exercise
    let wouldBePR: (Double, Int) -> Bool
    let onSave: (SetDraft) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void
    let onActivity: () -> Void
    let onEffortMode: (WatchEffortMode) -> Void
    let onAddPartner: () -> Void

    var body: some View {
        InlineSetEditorView(
            config: config,
            wouldBePR: wouldBePR,
            onSave: onSave,
            onDelete: onDelete,
            onCancel: onCancel,
            onActivity: onActivity,
            onEffortMode: onEffortMode,
            onAddPartner: onAddPartner)
    }
}
extension SessionView {
    func startWatchIfNeeded() {
        guard !isManualLog, model.watchAvailable else { return }
        if case .connected = model.hrm.state { return }
        model.startWatchStrength()
    }
    func handleIdleTimer(_ _: Date) {
        handleIdleTick()
        guard isActiveSession else { return }
        sampleHR()
        active.writeHeartbeat()
    }
    func handleSessionDisappear() {
        if isManualLog { cleanupEmptyLog() }
        raiseToTalkMonitor.stop()
        quickTalkCapture.stop()
        quickTalkDelayTask?.cancel()
    }
    func handleSessionAppear() {
        if expandedExerciseID == nil {
            expandedExerciseID = initiallyExpandedExerciseID
        }
        if isActiveSession && settings.raiseToTalk {
            raiseToTalkMonitor.start()
        }
    }
    func handleRaiseToTalkSettingChange(_ enabled: Bool) {
        if enabled && isActiveSession {
            raiseToTalkMonitor.start()
        } else {
            raiseToTalkMonitor.stop()
        }
    }
    func handleRaiseToTalkChange(_ raised: Bool) {
        guard settings.raiseToTalk, isActiveSession else { return }
        guard let pending = quickTalkPending ?? cache.state.contexts.first?.pendingSets.first else { return }
        let context = quickTalkContext(for: pending)
        guard let context, let exercise = exerciseForID(context.exerciseID) else { return }
        quickTalkPressing(pending, exercise: exercise, pressing: raised)
    }
    func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            recordActivity()
        }
    }

    func handleExercisePickerSelection(_ exercise: Exercise) {
        let isAlreadyInWorkout = session.exercisesInOrder.contains { $0.id == exercise.id }
        let isAlreadyPlanned = session.plannedExerciseNames.contains(exercise.name)
        if !isAlreadyInWorkout && !isAlreadyPlanned {
            session.plannedExerciseNames.append(exercise.name)
            try? context.save()
        }
        openInlineEditor(for: exercise)
    }

    func finishCooldown(_ seconds: Int) {
        session.cooldownSeconds = Double(seconds)
        coolingDown = false
        endWorkout()
    }

    func startCooldown() {
        active.pause()
        coolingDown = true
    }

    func deleteSessionFromConfirmation() {
        let wasActive = active.strengthSession?.id == session.id
        if wasActive {
            active.endStrength()
            active.minimize()
        }
        try? WorkoutRepository.softDeleteSession(session, in: context)
        if !wasActive {
            dismiss()
        }
    }

    func inlineWouldBePR(_ weightKg: Double, reps: Int, exercise: Exercise) -> Bool {
        cache.state.wouldBePR(weightKg: weightKg,
                               reps: reps,
                               isWarmup: false,
                               rule: settings.prRule,
                               formula: settings.formula,
                               for: exercise.id)
    }

    func addPartnerFromInlineEditor() {
        setEditorRoute = nil
        addPartnerPresented = true
    }

    var inlineSetEditorSheetContent: AnyView {
        if let cfg = inlineEditorConfig(), let ex = inlineExercise {
            let prAction: (Double, Int) -> Bool = { kg, reps in
                inlineWouldBePR(kg, reps: reps, exercise: ex)
            }
            let saveAction: (SetDraft) -> Void = { draft in
                recordInlineSet(for: ex, draft: draft)
            }
            let deleteAction: (() -> Void)? = inlineEditingSetID == nil
                ? nil
                : { deleteInlineSet() }
            let effortAction: (WatchEffortMode) -> Void = { mode in
                lastEffortMode = mode
            }
            return AnyView(SessionInlineEditorSheet(
                config: cfg,
                exercise: ex,
                wouldBePR: prAction,
                onSave: saveAction,
                onDelete: deleteAction,
                onCancel: { closeInlineEditor() },
                onActivity: { recordActivity() },
                onEffortMode: effortAction,
                onAddPartner: { addPartnerFromInlineEditor() }))
        } else {
            return AnyView(Color.clear)
        }
    }

    func removeExerciseFromConfirmation() {
        if let ex = exerciseToRemove {
            _ = try? WorkoutRepository.removeExercise(ex, from: session, in: context)
            recordActivity()
        }
        exerciseToRemove = nil
    }

    var idlePromptMessage: String {
        String(localized: "No activity for \(settings.idleTimeoutMinutes) min. Your workout will pause — it never ends on its own.")
    }

    func setSessionDate(_ date: Date) {
        session.date = date
        try? context.save()
        NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
    }

    func setSessionEndDate(_ date: Date) {
        session.endedAt = date
        try? context.save()
    }

    @ViewBuilder
    func sessionDatePickerSheet() -> some View {
        NavigationStack {
            DatePicker("Workout date", selection: Binding(
                get: { session.date },
                set: { setSessionDate($0) }))
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

    @ViewBuilder
    func sessionEndDatePickerSheet() -> some View {
        NavigationStack {
            DatePicker("End time", selection: Binding(
                get: { session.endedAt ?? session.date },
                set: { setSessionEndDate($0) }))
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

    @ViewBuilder
    func cooldownOverlay() -> some View {
        GuidedPhaseOverlay(
            title: String(localized: "Cool Down"),
            minutes: session.cooldownSeconds > 0 ? Int(session.cooldownSeconds / 60) : settings.cooldownMinutes,
            tint: .teal,
            idPrefix: "cooldown",
            soundsEnabled: settings.workoutSounds,
            onFinish: finishCooldown)
    }

    @ViewBuilder
    var sessionTopOverlay: some View {
        if let prMoment {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                prMomentCard(prMoment)
                    .padding(.horizontal, 20)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                    .zIndex(2)
            }
        } else if healthSaved {
            Text("Saved to Apple Health")
                .font(.caption)
                .padding(8)
                .cadenceGlass(in: Capsule(), fallback: .thinMaterial)
                .accessibilityIdentifier("session.healthSaved")
        }
    }

    func refreshSession() async {
        let recent = (try? WorkoutRepository.recentSessions(context, limit: 21)) ?? []
        generalRepLadders = SessionRenderModel.generalRepLadders(recentSessions: recent,
                                                                 excluding: session)
        plannedExerciseIndex = indexedPlannedExercises()
        refreshLiveVolume()
        cache.refresh(signature: refreshSignature) {
            SessionRenderModel.build(session: session, prRule: settings.prRule,
                                     formula: settings.formula, allPeople: allPeople,
                                     recentSessions: recent)
        }
        updateLiveActivityNextSet()
        if expandedExerciseID == nil {
            expandedExerciseID = initiallyExpandedExerciseID
        }
        if let target = pendingScrollExerciseID,
           cache.state.contexts.contains(where: { $0.exerciseID == target }) {
            pendingScrollExerciseID = nil
            expandedExerciseID = target
            scrollTarget = target
        }
    }

    @ViewBuilder
    var sessionScrollSurface: some View {
        ScrollViewReader { proxy in
            ScrollView { scrollContent }
                // Saving a set returns here with that exercise expanded and pulled
                // to the top of the screen, so the next set is always what you are
                // looking at (field test 2026-08-19 #6).
                .onChange(of: scrollTarget) { _, target in handleScrollTarget(target, proxy: proxy) }
        }
    }

    func handleScrollTarget(_ target: UUID?, proxy: ScrollViewProxy) {
        guard let target else { return }
        if reduceMotion {
            proxy.scrollTo(target, anchor: .top)
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
        scrollTarget = nil
    }

    func handleLiveActivityRequest(_ note: Notification) {
        guard isActiveSession else { return }
        guard let request = note.object as? CadencePlatformRequestStore.LiveActivityRequest else { return }
        applyLiveActivityAction(request.action, token: request.token)
    }

    func quickTalkContext(for pending: SessionRenderModel.PendingSetDisplay) -> SessionRenderModel.ExerciseContext? {
        for context in cache.state.contexts {
            for candidate in context.pendingSets where candidate.id == pending.id {
                return context
            }
        }
        return cache.state.contexts.first
    }

    func compactSummary(for ctx: SessionRenderModel.ExerciseContext) -> String {
        SessionRenderModel.compactSummary(context: ctx, unit: settings.unit)
    }

    @ViewBuilder
    func suggestedExerciseSheet(_ request: SuggestedExerciseRequest) -> some View {
        SuggestExerciseView(request: request,
                            exerciseForName: { name in
                                plannedExerciseIndex[name] ?? exerciseForName(named: name)
                            },
                            onAdd: addSuggestedExercise)
    }
}

struct QuickTalkNotificationModifier: ViewModifier {
    let isActive: Bool
    let isEnabled: Bool
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .cadenceQuickTalkRequested)) { _ in
            guard isActive, isEnabled else { return }
            isPresented = true
        }
    }
}

struct SessionIdlePromptModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let onKeepGoing: () -> Void
    let onSave: () -> Void

    func body(content: Content) -> some View {
        content.alert("Still training?", isPresented: $isPresented) {
            Button("Keep going", action: onKeepGoing)
            Button("Save now", role: .destructive, action: onSave)
        } message: {
            Text(message)
        }
    }
}

struct SessionCooldownConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onStart: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("Start cool-down?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Start Cool Down", action: onStart)
                .accessibilityIdentifier("workout.coolDownConfirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This ends your workout and starts the cool-down timer.")
        }
    }
}

struct SuggestionFailureAlertModifier: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("Couldn't suggest an exercise", isPresented: $isPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Exercise data could not be read. Try again after the catalog finishes loading.")
        }
    }
}

struct SessionDeleteConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("Delete this workout?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
                .accessibilityIdentifier("session.deleteConfirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("All sets and exercises in this session will be removed. You can restore it from History → View Deleted.")
        }
    }
}

struct ExerciseRemovalConfirmationModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onRemove: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog("Remove this exercise?", isPresented: $isPresented, titleVisibility: .visible) {
            Button("Remove exercise and all its sets", role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) { }
        }
    }
}
