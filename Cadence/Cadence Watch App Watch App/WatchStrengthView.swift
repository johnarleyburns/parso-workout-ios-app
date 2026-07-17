import SwiftUI
import SwiftData
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchStrengthView: View {
    @State private var flowModel: WatchStrengthFlowModel?

    @Environment(\.modelContext) private var modelContext
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(AppSettings.self) private var watchSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model = flowModel {
                content(model)
            }
        }
        .onAppear {
            if flowModel == nil {
                let m = WatchStrengthFlowModel(
                    context: modelContext,
                    unit: watchSettings.unit,
                    cooldownDefault: watchSettings.cooldownMinutes,
                    restDefault: watchSettings.restSeconds
                )
                m.start()
                flowModel = m
                watchManager.startWorkout(type: "strength")
            }
        }
        .onDisappear {
            if watchManager.isActive {
                watchManager.stopWorkout(save: false)
            }
        }
        .onChange(of: flowModel?.stage) { _, newStage in
            guard let newStage, newStage == .discarded else { return }
            if let payload = flowModel?.discardPayload {
                sendWCPayload(payload)
            }
            watchManager.stopWorkout(save: false)
            dismiss()
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
            WatchStrengthSummaryView(model: model, onDismiss: { dismiss() })
        case .discarded, .idle:
            EmptyView()
        }
    }

    private func sendWCPayload(_ payload: [String: Any]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload)
    }
}
