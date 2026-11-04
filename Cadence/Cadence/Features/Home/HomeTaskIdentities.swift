import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct HomeCoachTaskIdentity: Equatable {
    /// nil until Today's display restore finishes, so no history-derived
    /// signature is evaluated during the first-frame phase.
    let signature: HomeCoachModel.Signature?
    let isRestoringCloudKitHistory: Bool
}

struct HomeActivityTaskIdentity: Equatable {
    let historyRefreshToken: UUID
    let sessionCount: Int
    let cardioCount: Int
    let passiveSamples: [PassiveReadinessSample]
    let userAge: Int?
    let maximumHROverride: Double?
    let scheduledWorkouts: [ScheduledWorkoutTaskSignature]
}

struct ScheduledWorkoutTaskSignature: Equatable {
    let id: UUID
    let scheduledDate: Date
    let updatedAt: Date
    let statusRaw: String
    let payloadVersion: Int
}

extension HomeView {
    var scheduledWorkoutTaskSignatures: [ScheduledWorkoutTaskSignature] {
        scheduledWorkouts.map {
            ScheduledWorkoutTaskSignature(id: $0.id, scheduledDate: $0.scheduledDate, updatedAt: $0.updatedAt,
                                          statusRaw: $0.statusRaw, payloadVersion: $0.payloadVersion)
        }
    }
}
