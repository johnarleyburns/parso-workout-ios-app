import CadenceFeatures
import Foundation
import CadenceCore

/// A review-only draft. Applying defaults prepares a new launch value and never
/// edits the original workout or creates a session before the Start action.
public struct WatchStrengthPreviewSetup: Equatable, Sendable {
    public var repOverride: [Int]?
    public var partnerNames: [String]
    public var restSeconds: Int?
    private let originalPartners: [String]

    public init(launch: WatchLiftLaunch) {
        let names = launch.planPayload?.strength?.performers?.filter { !$0.isOwner }.map(\.displayName) ?? []
        originalPartners = names
        partnerNames = names
    }

    public var normalizedPartnerNames: [String] { WatchCustomStrengthDefaults.unique(partnerNames) }

    public func partnerOptions(recentNames: [String]) -> [String] {
        WatchCustomStrengthDefaults.unique(partnerNames + recentNames)
    }

    public mutating func togglePartner(_ name: String) {
        if let index = partnerNames.firstIndex(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            partnerNames.remove(at: index)
        } else {
            partnerNames = WatchCustomStrengthDefaults.unique(partnerNames + [name])
        }
    }

    public func preparedLaunch(from source: WatchLiftLaunch) -> WatchLiftLaunch {
        var launch = source
        if normalizedPartnerNames != originalPartners {
            // Explicit Watch roster edits supersede the synced roster. The
            // session resolves selected names to local People on actual Start.
            launch.planPayload?.strength?.performers = nil
        }
        guard let reps = repOverride, !reps.isEmpty,
              reps.allSatisfy({ (1...100).contains($0) }) else { return launch }
        launch.repLadder = reps
        var payload = launch.planPayload ?? WatchPlanPayload(title: launch.title)
        var strength = payload.strength ?? .init(exerciseNames: launch.exerciseNames)
        strength.repLadder = reps
        let existing = strength.prescriptions
        strength.prescriptions = launch.exerciseNames.map { name in
            let prior = existing.first { $0.exerciseName.caseInsensitiveCompare(name) == .orderedSame }
            let sets = reps.enumerated().map { index, reps -> PlannedSetPrescription in
                let oldSets = prior?.sets ?? []
                var set = oldSets.indices.contains(index) ? oldSets[index]
                    : (oldSets.last ?? PlannedSetPrescription(targetReps: reps))
                set.targetReps = reps
                if index >= oldSets.count { set.sourceSetID = nil }
                return set
            }
            var prescription = prior ?? PlannedExercisePrescription(exerciseName: name, sets: [])
            prescription.sets = sets
            return prescription
        }
        payload.strength = strength
        launch.planPayload = payload
        return launch
    }

    /// Empty custom plans need explicit targets on exercises added after Start;
    /// otherwise the logger would prefer the exercise's old rep history.
    public static func customDefaultPrescription(for name: String, payload: WatchPlanPayload?) -> PlannedExercisePrescription? {
        guard let strength = payload?.strength, strength.exerciseNames.isEmpty,
              !strength.repLadder.isEmpty else { return nil }
        return PlannedExercisePrescription(exerciseName: name,
            sets: strength.repLadder.map { PlannedSetPrescription(targetReps: $0) })
    }

}
