import Foundation
import CadenceCore
import CadenceFeatures
import os

/// Immutable request snapshot used while Home computes one direct Personalized
/// plan. There is intentionally no chooser/suggestion view.
struct SuggestedWorkoutRequest: Identifiable {
    let id = UUID()
    let input: SuggestedWorkoutInput
    let unit: MeasurementUnitPreference
    let warmupMinutes: Int
    let cooldownMinutes: Int
    let failureMessage: String?

    init(input: SuggestedWorkoutInput, unit: MeasurementUnitPreference, warmupMinutes: Int,
         cooldownMinutes: Int, failureMessage: String? = nil) {
        self.input = input
        self.unit = unit
        self.warmupMinutes = warmupMinutes
        self.cooldownMinutes = cooldownMinutes
        self.failureMessage = failureMessage
    }
}

enum SuggestedWorkoutSignposts {
    private static let log = OSLog(subsystem: "guru.parso.cladiron", category: "SuggestedWorkout")

    static func exerciseFetchAndMap<T>(_ operation: () throws -> T) rethrows -> T {
        let identifier = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "exerciseFetchAndMap", signpostID: identifier)
        defer { os_signpost(.end, log: log, name: "exerciseFetchAndMap", signpostID: identifier) }
        return try operation()
    }
}
