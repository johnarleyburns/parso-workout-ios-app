import SwiftUI
import Combine
import SwiftData
import CadenceCore
import CadenceFeatures

struct RootTabView: View {
    enum Tab: Hashable { case home, strength, cardio, progress, settings, search }
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(ActiveWorkoutModel.self) private var active
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = .home
    @State private var watchSyncToast: WatchSyncToast?
    /// UI-test seam backing the `-uiTestWatchStop` counter: `AppModel` writes
    /// each `stopWatchWorkout()` call to this UserDefaults key, and the hidden
    /// element below surfaces the running total to the iPhone smoke test.
    @AppStorage("uitest.watchStopCount") private var uiTestWatchStopCount = 0
    /// Liveness heartbeat for crash/upgrade recovery (launch-blockers Phase 1e).
    /// Root-level so it keeps beating while the workout is minimized.
    private let heartbeatTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var active = active
        return ZStack {
            nativeTabs

            // Explicit Watch action results use one non-layout-affecting host.
            // Automatic CloudKit restore state stays in Settings/diagnostics so
            // it never shifts the Today dashboard during launch.
            if watchSyncToast != nil {
                GeometryReader { proxy in
                    VStack(spacing: 8) {
                        if let watchSyncToast {
                            WatchSyncToastView(toast: watchSyncToast)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, proxy.safeAreaInsets.top + 52)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .zIndex(20)
            }

            if model.isUITestMode {
                Text("\(uiTestWatchStopCount)")
                    .accessibilityIdentifier("uitest.watchStopCount")
                    .frame(width: 1, height: 1)
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
        .environment(\.rootTabSelection, $selection)
        // The live workout + its finish summary share ONE root-level cover
        // (launch-blockers Phase 1b). A cover — not a NavigationStack push — so
        // lock/unlock can never pop the session (iOS 17 NavigationStack drops
        // non-Codable path values on background). Ending a workout swaps the
        // surface identity `.session` → `.summary` in place: no Home flash.
        .fullScreenCover(item: $active.presentedSurface) { surface in
            switch surface {
            case .session(let session):
                AdaptiveSessionRoot(session: session)
            case .summary(let finished):
                // Tapping an exercise expands it read-only in place (field test
                // 2026-08-18 #1, decision D7). Editing what was just logged stays
                // reachable through the toolbar's Edit, which reopens the session
                // — the escape hatch NFR-8 requires.
                let reviewSession = finished.session
                WorkoutSummaryView(data: finished.data,
                                   onEdit: reviewSession.map { session in
                                       {
                                           active.finishedSummary = nil
                                           active.presentedSurface = .session(session)
                                       }
                                   },
                                   onDone: { active.finishedSummary = nil })
            }
        }
        // Keep the screen awake while a workout is active in any navigation
        // state — presented or minimized — except a paused-and-minimized one
        // (e.g. crash-recovered onto Home), which shouldn't burn the screen.
        .keepAwake(active.isActive && !(active.isPaused && active.presentedSurface == nil))
        .onReceive(heartbeatTimer) { _ in
            // Bounded foreground backstop; reconciling is not activity.
            reconcileStrengthInactivity()
            reconcilePhoneCardio()
            active.writeHeartbeat()
            if let request = CadencePlatformRequestStore.consumeLiveActivityRequest() {
                NotificationCenter.default.post(name: .cadenceLiveActivityActionRequested,
                                                object: request)
            }
            if active.isActive {
                WorkoutLiveActivityCoordinator.shared.update(
                    elapsedSeconds: Int(active.clock.elapsed()),
                    status: active.isPaused ? String(localized: "Paused") : String(localized: "Active"),
                    isPaused: active.isPaused,
                    restEndsAt: active.restEndsAt,
                    nextExercise: active.nextExercise,
                    nextSetSummary: active.nextSetSummary,
                    nextSetToken: active.nextSetToken)
            } else {
                // Heartbeat backstop: no active workout means no Live Activity.
                // A live phone cardio session keeps (and refreshes) its own.
                model.syncPhoneCardioLiveActivity()
                WorkoutLiveActivityCoordinator.shared.reconcile(
                    workoutIsActive: active.isActive, hasStrengthSession: active.strengthSession != nil,
                    hasPhoneCardioSession: PhoneCardioLiveActivityContent.isLive(model.phoneCardio.session))
            }
        }
        .onChange(of: active.isActive) { _, isActive in
            // Workout start/end boundary: propagate summary state (bounded by the tracker).
            model.pushSettingsContext(reason: .workoutBoundary)
            if isActive, let session = active.strengthSession {
                WorkoutLiveActivityCoordinator.shared.start(
                    title: session.title.isEmpty ? String(localized: "Workout") : session.title,
                    restEndsAt: active.restEndsAt,
                    nextExercise: active.nextExercise,
                    nextSetSummary: active.nextSetSummary,
                    nextSetToken: active.nextSetToken)
            } else if !PhoneCardioLiveActivityContent.isLive(model.phoneCardio.session) {
                WorkoutLiveActivityCoordinator.shared.end()
            }
        }
        .task {
            // Crash/upgrade recovery FIRST (launch-blockers Phase 1e): re-adopt
            // an in-progress workout paused and return straight to its session
            // surface. A workout is never auto-ended or discarded, no matter
            // how stale. Manual minimization remains a deliberate path to Home.
            installStrengthFinalizer()
            recoverActiveSessionIfNeeded()
            // End any Live Activity orphaned by a previous launch when no
            // workout is running (issue #74).
            if !PhoneCardioLiveActivityContent.isLive(model.phoneCardio.session) {
                WorkoutLiveActivityCoordinator.shared.reconcile(workoutIsActive: active.isActive)
            }
            // Recovery can make the workout active before this view's
            // `.onChange` observer is installed. Reconcile once after launch
            // so a recovered workout always gets its Live Activity.
            if active.isActive, let session = active.strengthSession {
                WorkoutLiveActivityCoordinator.shared.start(
                    title: session.title.isEmpty ? String(localized: "Workout") : session.title,
                    restEndsAt: active.restEndsAt,
                    nextExercise: active.nextExercise,
                    nextSetSummary: active.nextSetSummary,
                    nextSetToken: active.nextSetToken)
            } else if PhoneCardioLiveActivityContent.isLive(model.phoneCardio.session) {
                // Recovered phone cardio session re-adopts its Live Activity.
                model.syncPhoneCardioLiveActivity()
            } else {
                // Launch cleanup: end any activity orphaned by a prior process.
                WorkoutLiveActivityCoordinator.shared.reconcile(
                    workoutIsActive: active.isActive, hasStrengthSession: active.strengthSession != nil)
            }
            // The training log syncs live via SwiftData↔CloudKit (private DB);
            // there is nothing to restore or upload here — SwiftData mirrors the
            // store automatically on launch and as changes happen.
        }
        .onChange(of: scenePhase) { _, phase in
            // Reconcile BEFORE anything else: foregrounding is never activity, and an
            // expired workout ends at its original deadline, not at wake-up time.
            if phase == .active { reconcileStrengthInactivity(); reconcilePhoneCardio() }
            active.writeHeartbeat()
            // End any Live Activity that outlived its workout (e.g. a finish
            // while suspended could lose the async end) on every transition.
            if !active.isActive {
                WorkoutLiveActivityCoordinator.shared.reconcile(
                    workoutIsActive: false, hasStrengthSession: false,
                    hasPhoneCardioSession: PhoneCardioLiveActivityContent.isLive(model.phoneCardio.session))
            }
            guard phase == .active else { return }
            model.pushSettingsContext(reason: .activation)
            if let request = CadencePlatformRequestStore.consumeLiveActivityRequest() {
                NotificationCenter.default.post(name: .cadenceLiveActivityActionRequested,
                                                object: request)
            }
            if CadencePlatformRequestStore.consumeQuickTalk() {
                NotificationCenter.default.post(name: .cadenceQuickTalkRequested, object: nil)
            }
        }
        .alert("Workout ended automatically", isPresented: Binding(
            get: { model.autoEndedCardio != nil && !model.phoneCardioHasLiveView },
            set: { if !$0 { model.dismissAutoEndedNotice() } })) {
            Button("OK", role: .cancel) { model.dismissAutoEndedNotice() }
        } message: {
            Text("Your cardio workout was paused for inactivity and not resumed, so it was saved at the automatic end time. Paused time is not counted. You can find it in History.")
        }
        .alert("Workout ended", isPresented: Binding(
            get: { active.inactivityNotice != nil },
            set: { if !$0 { active.inactivityNotice = nil } })) {
            Button("OK", role: .cancel) { active.inactivityNotice = nil }
        } message: {
            Text(inactivityNoticeMessage)
        }
        .modifier(WatchSettingsContextSync(settings: settings, model: model))
        .onChange(of: model.watchSyncState) { _, state in
            showWatchSyncToast(for: state)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cadenceShowThisWeek)) { _ in
            selection = .strength
        }
        .onOpenURL { url in
            guard url.scheme == "cladiron" else { return }
            if url.host == "this-week" || url.path == "/this-week" {
                // Preserve existing deep links while taking people to the
                // first of the two dedicated weekly surfaces.
                selection = .strength
            } else if url.host == "workout" || url.path == "/workout" {
                selection = .home
                CadencePlatformRequestStore.requestStartWorkout()
                NotificationCenter.default.post(name: .cadenceStartTodaysWorkout, object: nil)
            } else {
                // Old weekly-plan deep links remain safe after the Plan tab is
                // retired: one-off scheduled workouts are reached from Home.
                selection = .home
            }
        }
        .onContinueUserActivity(CadenceHandoff.planActivityType) { _ in
            selection = .home
        }
    }

    @ViewBuilder
    private var nativeTabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selection) {
                SwiftUI.Tab("Today", systemImage: "house", value: .home) { HomeView() }
                SwiftUI.Tab("Strength", systemImage: "dumbbell.fill", value: .strength) { StrengthView() }
                SwiftUI.Tab("Cardio", systemImage: "heart.fill", value: .cardio) { CardioWeekView() }
                SwiftUI.Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: .progress) {
                    AdaptiveProgressRoot()
                }
                SwiftUI.Tab("Find", systemImage: "magnifyingglass", value: .search) { FindExercisesView() }
            }
            .modifier(MinimizeTabBarOnScrollDown())
            .modifier(LiveWorkoutTabAccessory(active: active))
        } else {
            TabView(selection: $selection) {
                HomeView().tabItem { Label("Today", systemImage: "house") }.tag(Tab.home)
                StrengthView().tabItem { Label("Strength", systemImage: "dumbbell.fill") }.tag(Tab.strength)
                CardioWeekView().tabItem { Label("Cardio", systemImage: "heart.fill") }.tag(Tab.cardio)
                AdaptiveProgressRoot().tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }.tag(Tab.progress)
            }
        }
    }

    /// Re-adopts an in-progress session after a crash, force-quit, jetsam, or
    /// app upgrade (launch-blockers Phase 1e). The session is adopted PAUSED
    /// (`.auto`), immediately presented, and the dead gap is excluded from the
    /// clock via the heartbeat.
    private func recoverActiveSessionIfNeeded() {
        guard active.strengthSession == nil else { return }
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate {
                $0.endedAt == nil && $0.deletedAt == nil && !$0.isLogged
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        guard let candidate = ActiveSessionRecovery.candidate(in: sessions) else {
            WorkoutHeartbeatStore.clear()
            return
        }
        active.adopt(candidate, heartbeat: WorkoutHeartbeatStore.read())
        // Reconcile before re-presenting: an expired session is finalized at its deadline.
        reconcileStrengthInactivity()
        if active.isActive { active.present() }
    }

    private var inactivityNoticeMessage: String {
        guard let notice = active.inactivityNotice else { return "" }
        return String(localized: "\(notice.message). Your logged sets were saved in History; the workout was not resumed.")
    }

    /// Reconciles a parked/backgrounded phone cardio session at its original deadline.
    private func reconcilePhoneCardio() {
        model.phoneCardioSettings = settings
        Task { await model.reconcilePhoneCardio() }
    }

    /// Ends an expired phone strength session without needing `SessionView`.
    private func reconcileStrengthInactivity() {
        guard active.reconcileStrengthInactivity(enabled: settings.autoEndOnIdle,
                                                 timeoutMinutes: settings.idleTimeoutMinutes) != nil else { return }
        try? context.save()
    }

    /// App-owned side effects for finalization; runs exactly once per ended session.
    private func installStrengthFinalizer() {
        active.strengthFinalizer = { [model, active, context, settings] session, reason in
            guard reason == .inactivity else { return }
            let recorder = active.heartRateRecorder
            recorder?.flush()
            RestAlarmCoordinator.shared.cancel()
            model.stopWatchWorkout()
            if let scheduledID = session.scheduledWorkoutID,
               !session.orderedSets.isEmpty,
               let scheduled = try? context.fetch(FetchDescriptor<ScheduledWorkout>(
                   predicate: #Predicate { $0.id == scheduledID })).first {
                _ = try? ScheduledWorkoutStore.markCompleted(recordID: scheduled.id, in: context)
            }
            let sessionID = session.id
            Task { @MainActor in
                if let recorder, !recorder.snapshot.isEmpty {
                    let profile = await cardioIntensityProfile(model: model, settings: settings)
                    active.finalizeHeartRate(profile: profile, sessionID: sessionID)
                }
            }
        }
    }

    private func showWatchSyncToast(for state: WatchSyncState) {
        guard let text = state.toastText else { return }
        let toast = WatchSyncToast(text: text, isFailure: state.isFailure)
        withAnimation(.easeInOut(duration: 0.18)) {
            watchSyncToast = toast
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard watchSyncToast?.id == toast.id else { return }
            withAnimation(.easeInOut(duration: 0.18)) {
                watchSyncToast = nil
            }
        }
    }
}

private struct MinimizeTabBarOnScrollDown: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

private struct LiveWorkoutTabAccessory: ViewModifier {
    let active: ActiveWorkoutModel

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            let enabled = active.isActive && active.strengthSession != nil
            content.tabViewBottomAccessory(isEnabled: enabled) {
                if let session = active.strengthSession, enabled { accessory(session) }
            }
        } else {
            content.tabViewBottomAccessory {
                if active.isActive, let session = active.strengthSession { accessory(session) }
            }
        }
    }

    private func accessory(_ session: WorkoutSession) -> some View {
        Button { active.present() } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                Text(session.title.isEmpty ? String(localized: "Workout in progress") : session.title)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up")
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab.liveWorkoutAccessory")
    }
}

/// Pushes the Watch-facing settings context whenever one of its inputs changes.
/// Split out of `RootTabView.body` so the modifier chain stays type-checkable.
private struct WatchSettingsContextSync: ViewModifier {
    let settings: AppSettings
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .onChange(of: settings.unit) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.intervalColorBlind) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.restSeconds) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.warmupMinutes) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.cooldownMinutes) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.workoutSounds) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.spokenCues) { _, _ in model.pushSettingsContext() }
            // Inputs of the Watch single-exercise Suggest context.
            .onChange(of: settings.trainingGoal) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.experienceLevel) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.preferredWorkoutStyle) { _, _ in model.pushSettingsContext() }
            .onChange(of: settings.coachSchedulePreferences) { _, _ in model.pushSettingsContext() }
    }
}

private struct WatchSyncToast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isFailure: Bool
}

private struct WatchSyncToastView: View {
    let toast: WatchSyncToast

    var body: some View {
        Label(toast.text, systemImage: toast.isFailure ? "exclamationmark.triangle.fill" : "applewatch")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(toast.isFailure ? Color.red.opacity(0.45) : Color.green.opacity(0.35), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .accessibilityIdentifier("watchSync.toast")
    }
}
