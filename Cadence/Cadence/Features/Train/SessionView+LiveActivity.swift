import SwiftUI
import SwiftData
import UIKit
import CadenceCore
import CadenceFeatures

extension SessionView {
    func updateLiveActivityNextSet() {
        guard isActiveSession,
              let context = cache.state.contexts.first(where: { !$0.pendingSets.isEmpty }),
              let pending = context.pendingSets.first else {
            active.nextSetSummary = nil
            active.nextSetToken = nil
            return
        }

        let load = pending.targetWeightKg.map {
            "\(Format.weightValue($0, unit: settings.unit)) \(settings.unit.abbreviation)"
        } ?? String(localized: "Bodyweight")
        active.nextSetSummary = "\(context.name) · \(load) × \(pending.targetReps)"
        active.nextSetToken = pending.id
    }

    func applyLiveActivityAction(_ action: CadencePlatformRequestStore.LiveActivityAction,
                                 token: String? = nil) {
        recordActivity()
        switch action {
        case .logPlannedSet:
            guard let context = cache.state.contexts.first(where: { context in
                context.pendingSets.contains { token == nil || $0.id == token }
            }),
                  let pending = context.pendingSets.first(where: { token == nil || $0.id == token }),
                  let exercise = exerciseForID(context.exerciseID) else { return }
            logPendingSet(pending, for: exercise)
        case .addRest:
            rest.add(30)
            active.restEndsAt = rest.endsAt
            syncRestAlarm(to: rest.endsAt)
        case .skipRest:
            rest.skip()
            active.restEndsAt = nil
            syncRestAlarm(to: nil)
        }
    }
}
