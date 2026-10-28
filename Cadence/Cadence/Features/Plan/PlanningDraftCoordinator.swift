import Foundation
import SwiftData
import CadenceCore
import CadenceFeatures

/// App-facing entry point for Planning Draft mutations. Supplies the same
/// owner-history lookup the workout plan editor uses, then defers every
/// decode/encode/save to `PlanningDraftStore`.
@MainActor
enum PlanningDraftCoordinator {
    static func makeStore() -> PlanningDraftStore {
        PlanningDraftStore(historyProvider: { name, context in
            let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
            return WorkoutPlanPartnerHistory.history(forExerciseNamed: name,
                                                     performerID: nil,
                                                     people: people,
                                                     context: context)
        })
    }
}
