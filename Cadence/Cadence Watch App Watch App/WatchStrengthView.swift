import SwiftUI
import SwiftData
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchStrengthView: View {
    @State private var flowModel: WatchStrengthFlowModel?
    @State private var shouldStopWorkoutOnDisappear = false

    private let resumingSession: WorkoutSession?
    private let title: String
    private let plannedExerciseNames: [String]
    private let repLadder: [Int]
    private let planKey: String?

    init(resuming session: WorkoutSession? = nil,
         title: String = "Strength",
         plannedExerciseNames: [String] = [],
         repLadder: [Int] = [],
         planKey: String? = nil) {
        self.resumingSession = session
        self.title = title
        self.plannedExerciseNames = plannedExerciseNames
        self.repLadder = repLadder
        self.planKey = planKey
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
        .task {
            if flowModel == nil {
                let m = WatchStrengthFlowModel(
                    context: modelContext,
                    unit: watchSettings.unit,
                    cooldownDefault: watchSettings.cooldownMinutes,
                    restDefault: watchSettings.restSeconds
                )
                m.start(
                    resuming: resumingSession,
                    title: title,
                    plannedExerciseNames: plannedExerciseNames,
                    repLadder: repLadder,
                    planKey: planKey,
                    createSession: true
                )
                flowModel = m
                if watchManager.isActive {
                    if watchManager.isPaused { watchManager.togglePause() }
                } else {
                    watchManager.startWorkout(type: "strength")
                }
            }
        }
        .onDisappear {
            if shouldStopWorkoutOnDisappear, watchManager.isActive {
                watchManager.stopWorkout(save: false)
            }
        }
        .onChange(of: flowModel?.stage) { _, newStage in
            guard let newStage, newStage == .discarded else { return }
            if let payload = flowModel?.discardPayload {
                sendWCPayload(payload)
            }
            shouldStopWorkoutOnDisappear = true
            watchManager.stopWorkout(save: false)
            dismiss()
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if flowModel?.stage != .summary {
                    Button {
                        if watchManager.isActive, !watchManager.isPaused {
                            watchManager.togglePause()
                        }
                        dismiss()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .accessibilityIdentifier("watchStrength.pause")
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ model: WatchStrengthFlowModel) -> some View {
        switch model.stage {
        case .home:
            WatchStrengthHomeView(model: model)
        case .addExercise:
            WatchAddExerciseView(model: model)
        case .keypad:
            WatchSetKeypadView(model: model)
        case .partners:
            WatchPartnersView(model: model)
        case .rest:
            WatchRestView(model: model)
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
        }
    }

    private func sendWCPayload(_ payload: [String: Any]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload)
    }
}
