import SwiftUI
import SwiftData
import WidgetKit
import WatchConnectivity
import WatchKit
import CadenceCore
import CadenceFeatures

/// Watch redesign §5 P1–P4 (decision D-W1) — the workout pager, Apple Workout's grammar applied to
/// lifting: Controls ◂ Set Card ▸ Plan ▸ Heart. It always returns to the Set Card. Pausing never
/// leaves the workout; Finish always reviews before saving (F1).
struct WatchStrengthView: View {
    @State private var flowModel: WatchStrengthFlowModel?
    @State private var shouldStopWorkoutOnDisappear = false
    @State private var page: Page = .main
    @State private var reviewing = false
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
            case .home:
                // Last set of an exercise (or nothing planned yet) → the Plan page.
                if old != .home { page = .plan }
            case .keypad, .rest, .addExercise, .partners:
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
            reviewing = true
        }
        .onChange(of: WatchLaunchRequests.shared.talkRequest) { _, _ in
            // D-W5: the Action Button during a workout = Talk.
            guard flowModel != nil, !reviewing else { return }
            page = .main
            talk.startListening()
        }
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func content(_ model: WatchStrengthFlowModel) -> some View {
        switch model.stage {
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
            if reviewing {
                WatchStrengthReviewView(model: model, onSave: {
                    reviewing = false
                    WatchHaptics.success()
                    model.finish()
                }, onKeepGoing: { reviewing = false })
            } else {
                pager(model)
            }
        }
    }

    private func pager(_ model: WatchStrengthFlowModel) -> some View {
        TabView(selection: $page) {
            WatchStrengthControlsPage(model: model, onFinish: { reviewing = true }, onPartners: {
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
            WatchNextExerciseView(model: model, onPlan: { page = .plan })
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

    private func startIfNeeded() {
        guard flowModel == nil else { return }
        WatchHaptics.success()
        let m = WatchStrengthFlowModel(
            context: modelContext,
            unit: watchSettings.unit,
            cooldownDefault: watchSettings.cooldownMinutes,
            restDefault: restSecondsOverride ?? watchSettings.restSeconds
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
        if let first = m.exerciseList.first?.exercise, resumingSession == nil, !plannedExerciseNames.isEmpty {
            m.startLogSet(for: first)
            page = .main
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

/// M3 — between exercises: offer the next planned exercise (Double Tap), or the whole plan.
struct WatchNextExerciseView: View {
    let model: WatchStrengthFlowModel
    let onPlan: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let next = nextExercise {
                Image(systemName: "flag.checkered").font(.title3).foregroundStyle(WatchTone.accent)
                Button { model.startLogSet(for: next) } label: { Text("Next · \(next.name)") }
                    .buttonStyle(WatchPillStyle(kind: .primary))
                    .handGestureShortcut(.primaryAction)
                    .accessibilityIdentifier("watchStrength.nextExercise")
            } else {
                Text("Add an exercise to start").font(.headline).multilineTextAlignment(.center)
                Button { model.goToAddExercise() } label: { Label("Add exercise", systemImage: "plus") }
                    .buttonStyle(WatchPillStyle(kind: .primary))
                    .handGestureShortcut(.primaryAction)
            }
            Button("All exercises", action: onPlan).font(.footnote)
        }
        .padding(.horizontal, 4)
    }

    /// The first planned exercise that still has planned sets to do.
    private var nextExercise: Exercise? {
        model.exerciseList.map(\.exercise).first { exercise in
            let planned = model.plannedWorkingSets(for: exercise).count
            return planned == 0 ? model.exerciseList.first { $0.exercise.id == exercise.id }?.setCount == 0
                                : model.completedWorkingSets(for: exercise) < planned
        }
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
                Button("Keep going", action: onKeepGoing).font(.footnote)
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
