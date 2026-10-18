import SwiftUI
import SwiftData
import WidgetKit
import WatchConnectivity
import WatchKit
import CadenceCore
import CadenceFeatures

/// Watch redesign §5 P1–P4 (decision D-W1) — the workout pager, Apple Workout's grammar applied to
/// lifting: Controls ◂ Set Card ▸ Plan ▸ Heart. It always returns to the Set Card. Pausing never
/// leaves the workout; Finish starts the cool-down, then the Saved summary follows (F1).
struct WatchStrengthView: View {
    @State private var flowModel: WatchStrengthFlowModel?
    @State private var shouldStopWorkoutOnDisappear = false
    @State private var page: Page = .main
    @State private var talk = WatchQuickTalkController()
    @State private var moment: Moment?

    enum Page: Hashable { case controls, main, plan, heart }
    enum Moment: Equatable { case logged(String), personalRecord(String) }

    private let resumingSession: WorkoutSession?
    private let title: String
    private let plannedExerciseNames: [String]
    private let repLadder: [Int]
    private let planKey: String?
    private let planPayload: WatchPlanPayload?
    private let initialPartnerNames: [String]
    private let restSecondsOverride: Int?

    init(resuming session: WorkoutSession? = nil,
         title: String = "Strength",
         plannedExerciseNames: [String] = [],
         repLadder: [Int] = [],
         planKey: String? = nil,
         planPayload: WatchPlanPayload? = nil,
         initialPartnerNames: [String] = [],
         restSeconds: Int? = nil) {
        self.resumingSession = session
        self.title = title
        self.plannedExerciseNames = plannedExerciseNames
        self.repLadder = repLadder
        self.planKey = planKey
        self.planPayload = planPayload
        self.initialPartnerNames = initialPartnerNames
        self.restSecondsOverride = restSeconds
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(AppSettings.self) private var watchSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model = flowModel {
                content(model)
            } else {
                ProgressView("Loading...")
            }
        }
        .task { startIfNeeded() }
        .onDisappear {
            WatchWorkoutVoiceCoach.shared.stop()
            if shouldStopWorkoutOnDisappear, watchManager.isActive {
                watchManager.stopWorkout(save: false)
                CadenceWatchWidgetStore.clear()
            }
        }
        .onChange(of: flowModel?.stage) { old, newStage in
            guard let newStage else { return }
            switch newStage {
            case .discarded:
                if let payload = flowModel?.discardPayload { WatchSyncSender.send(payload) }
                shouldStopWorkoutOnDisappear = true
                watchManager.stopWorkout(save: false)
                dismiss()
            case .summary:
                // The workout is over; stop recording now rather than when Done is tapped, which
                // the user may never do (field test 2026-10-03: a session ran for 27 hours).
                if watchManager.isActive, watchManager.phoneRequestID == nil {
                    watchManager.stopWorkout(save: false)
                }
            case .home where { if case .warmup = old { return true } else { return false } }():
                // Warm-up finished or skipped → straight into the first planned set.
                if let model = flowModel { startFirstPlannedSet(model) }
            case .home:
                // Last set of an exercise (or nothing planned yet) → the Plan page.
                if old != .home { page = .plan }
            case .keypad, .rest, .addExercise, .partners, .warmup:
                page = .main
            default:
                break
            }
        }
        .onChange(of: flowModel?.lastLoggedSetID) { _, id in
            guard id != nil, let model = flowModel else { return }
            showMoment(model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchQuickTalkTogglePause)) { _ in
            watchManager.togglePause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchQuickTalkFinish)) { _ in
            finishWorkout()
        }
        .onChange(of: WatchLaunchRequests.shared.talkRequest) { _, _ in
            // D-W5: the Action Button during a workout = Talk.
            guard flowModel != nil else { return }
            page = .main
            talk.startListening()
        }
        .navigationBarBackButtonHidden(true)
        .ownsWatchWorkoutSession()
    }

    /// Finish goes straight to the cool-down; the review/Saved summary comes after it.
    private func finishWorkout() {
        WatchHaptics.success()
        flowModel?.finish()
    }

    @ViewBuilder
    private func content(_ model: WatchStrengthFlowModel) -> some View {
        switch model.stage {
        case .warmup:
            WatchWarmUpView(model: model)
        case .cooldown:
            WatchCoolDownView(model: model)
        case .summary:
            WatchStrengthSummaryView(model: model, onDismiss: {
                shouldStopWorkoutOnDisappear = true
                if watchManager.isActive { watchManager.stopWorkout(save: false) }
                dismiss()
            })
        case .discarded, .idle:
            EmptyView()
        default:
            pager(model)
        }
    }

    private func pager(_ model: WatchStrengthFlowModel) -> some View {
        TabView(selection: $page) {
            WatchStrengthControlsPage(model: model, onFinish: { finishWorkout() }, onPartners: {
                model.goToPartners()
            })
            .tag(Page.controls)

            ZStack {
                mainPage(model)
                WatchQuickTalkOverlay(talk: talk, unit: model.unit)
                if let moment { momentView(moment) }
            }
            .tag(Page.main)

            WatchStrengthHomeView(model: model, onSelect: { page = .main })
                .tag(Page.plan)

            WatchHeartPage()
                .tag(Page.heart)
        }
        .tabViewStyle(.page)
        .alert("All exercises complete, finish workout?", isPresented: Binding(
            get: { model.allExercisesCompletePrompt },
            set: { model.allExercisesCompletePrompt = $0 }
        )) {
            Button("Done") { finishWorkout() }
            Button("Keep going", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func mainPage(_ model: WatchStrengthFlowModel) -> some View {
        switch model.stage {
        case .keypad:
            WatchSetKeypadView(model: model, talk: talk)
        case .rest:
            WatchRestView(model: model, talk: talk)
        case .addExercise:
            WatchAddExerciseView(model: model)
        case .partners:
            WatchPartnersView(model: model)
        default:
            WatchAddExerciseView(model: model)
        }
    }

    // MARK: Moments (M1/M2)

    private func showMoment(_ model: WatchStrengthFlowModel) {
        let name = model.currentExerciseName ?? ""
        let next: Moment = model.lastLoggedSetWasPR ? .personalRecord(name) : .logged(name)
        if case .personalRecord = next { WKInterfaceDevice.current().play(.notification) }
        withAnimation(.easeOut(duration: 0.2)) { moment = next }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(model.lastLoggedSetWasPR ? 2 : 0.6))
            withAnimation { moment = nil }
        }
    }

    @ViewBuilder
    private func momentView(_ moment: Moment) -> some View {
        switch moment {
        case .logged:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(.largeTitle))
                .foregroundStyle(WatchTone.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.6))
                .accessibilityHidden(true)
        case .personalRecord(let exercise):
            VStack(spacing: 4) {
                Text("New record").font(.caption.weight(.bold)).foregroundStyle(WatchTone.gold)
                Image(systemName: "trophy.fill").font(.largeTitle).foregroundStyle(WatchTone.gold)
                Text(exercise).font(.headline).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RadialGradient(colors: [WatchTone.gold.opacity(0.4), .black], center: .center, startRadius: 0, endRadius: 140))
            .onTapGesture { self.moment = nil }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("watchStrength.prMoment")
        }
    }

    // MARK: Start

    private func startFirstPlannedSet(_ m: WatchStrengthFlowModel) {
        if let first = m.exerciseList.first?.exercise, resumingSession == nil, !plannedExerciseNames.isEmpty {
            m.startLogSet(for: first)
            page = .main
        }
    }

    private func startIfNeeded() {
        guard flowModel == nil else { return }
        WatchHaptics.success()
        // The Custom start screen's rest choice lives only in this view's init, so a
        // resumed session (relaunch) would otherwise fall back to the global default.
        let activeRestKey = "watch.strength.activeRestSeconds"
        let defaults = UserDefaults.standard
        if let override = restSecondsOverride {
            defaults.set(override, forKey: activeRestKey)
        } else if resumingSession == nil {
            defaults.removeObject(forKey: activeRestKey)
        }
        let storedRest = resumingSession != nil ? defaults.object(forKey: activeRestKey) as? Int : nil
        let m = WatchStrengthFlowModel(
            context: modelContext,
            unit: watchSettings.unit,
            cooldownDefault: watchSettings.cooldownMinutes,
            restDefault: restSecondsOverride ?? storedRest ?? watchSettings.restSeconds,
            warmupDefault: watchSettings.warmupMinutes
        )
        m.prRule = watchSettings.prRule
        m.prFormula = watchSettings.formula
        m.start(
            resuming: resumingSession,
            title: title,
            plannedExerciseNames: plannedExerciseNames,
            repLadder: repLadder,
            planKey: planKey,
            planPayload: planPayload,
            initialPartnerNames: initialPartnerNames,
            createSession: true
        )
        flowModel = m
        talk.bind(model: m, unit: watchSettings.unit)
        page = m.exerciseList.isEmpty ? .plan : .main
        if resumingSession == nil, m.beginWarmup() {
            page = .main
        } else {
            startFirstPlannedSet(m)
        }
        CadenceWatchWidgetStore.save(CadenceWatchWidgetState(workoutTitle: title))
        WidgetCenter.shared.reloadTimelines(ofKind: "CadenceWatchSmartStackWidget")
        if watchManager.isActive {
            if watchManager.isPaused { watchManager.togglePause() }
        } else {
            watchManager.startWorkout(type: "strength")
        }
        WatchWorkoutVoiceCoach.shared.speak(.workoutStarted(title: title), enabled: watchSettings.spokenCues)
    }
}

/// F1 — review before saving: time, sets, volume, PRs; Save is explicit, Keep going goes back.
struct WatchStrengthReviewView: View {
    let model: WatchStrengthFlowModel
    let onSave: () -> Void
    let onKeepGoing: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text(model.session?.title ?? String(localized: "Workout")).font(.headline)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    stat(model.durationText, label: "time")
                    stat("\(model.setCount)", label: "sets")
                    stat(model.weightValue(model.volume), label: "volume")
                    stat(prCountText, label: "PRs", highlight: prCount > 0)
                }
                Button("Save workout", action: onSave)
                    .buttonStyle(WatchPillStyle(kind: .primary))
                    .handGestureShortcut(.primaryAction)
                    .accessibilityIdentifier("watchStrength.save")
                Button("Keep going", action: onKeepGoing)
                    .buttonStyle(WatchPillStyle(kind: .secondary))
                    .accessibilityIdentifier("watchStrength.keepGoing")
            }
            .padding(.horizontal, 2)
        }
    }

    private var prCount: Int { model.personalRecordCount }
    private var prCountText: String { "\(prCount)" }

    private func stat(_ value: String, label: LocalizedStringKey, highlight: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                .foregroundStyle(highlight ? WatchTone.gold : .primary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(RoundedRectangle(cornerRadius: 12).fill(highlight ? WatchTone.gold.opacity(0.15) : WatchTone.surface))
        .accessibilityElement(children: .combine)
    }
}
