import Foundation
import HealthKit
import CadenceCore
import CadenceFeatures
import os

/// HealthKit-backed `HealthHeartRateSource` for "Reload cardio measurements from Apple
/// Health". Each call uses its own `HKHealthStore`, so nothing non-Sendable is shared.
/// Diagnostics log counts and error categories only — never BPM values, titles or identifiers.
private struct HRReading: Sendable { let date: Date; let bpm: Double }

struct HealthKitHeartRateSource: HealthHeartRateSource {
    private static let log = Logger(subsystem: "guru.parso.cladiron", category: "hr-repair")

    func workouts(from: Date, to: Date) async throws -> [HealthWorkoutCandidate] {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthRepairError.authorization }
        let store = HKHealthStore()
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
        let appID = Bundle.main.bundleIdentifier ?? ""
        let result: [HealthWorkoutCandidate] = try await Self.run { done in
            HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit,
                          sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                let mapped = ((samples as? [HKWorkout]) ?? []).map { w in
                    HealthWorkoutCandidate(
                        token: w.uuid.uuidString, start: w.startDate, end: w.endDate,
                        isStrength: w.workoutActivityType == .traditionalStrengthTraining
                            || w.workoutActivityType == .functionalStrengthTraining,
                        sourceName: w.sourceRevision.source.name,
                        isFromThisApp: !appID.isEmpty && w.sourceRevision.source.bundleIdentifier.hasPrefix(appID))
                }
                done(mapped, error)
            }
        } on: { store.execute($0) }
        Self.log.info("match query returned \(result.count, privacy: .public) workouts")
        return result
    }

    func heartRate(for candidate: HealthWorkoutCandidate) async throws -> [(date: Date, bpm: Double)] {
        guard let id = UUID(uuidString: candidate.token) else { return [] }
        let store = HKHealthStore()
        let unit = HKUnit.count().unitDivided(by: .minute())
        // One continuation: look up the workout, then query its samples, so the
        // non-Sendable HKWorkout never crosses an isolation boundary.
        let samples: [HRReading] = try await Self.run { done in
            HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForObject(with: id), limit: 1,
                          sortDescriptors: nil) { _, found, error in
                guard error == nil, let workout = (found as? [HKWorkout])?.first else { done([], error); return }
                let time = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate, options: .strictStartDate)
                let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [time, HKQuery.predicateForObjects(from: workout)])
                let hrQuery = HKSampleQuery(sampleType: HKQuantityType(.heartRate), predicate: predicate, limit: HKObjectQueryNoLimit,
                                            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, error in
                    done(((samples as? [HKQuantitySample]) ?? []).map { HRReading(date: $0.endDate, bpm: $0.quantity.doubleValue(for: unit)) }, error)
                }
                store.execute(hrQuery)
            }
        } on: { store.execute($0) }
        Self.log.info("queried \(samples.count, privacy: .public) hr samples")
        return samples.map { ($0.date, $0.bpm) }
    }

    private static func run<T: Sendable>(_ make: (@escaping @Sendable (T, (any Error)?) -> Void) -> HKQuery,
                                         on execute: (HKQuery) -> Void) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let query = make { value, error in
                if let error {
                    let category = (error as? HKError)?.code == .errorAuthorizationDenied
                        ? HealthRepairError.authorization : HealthRepairError.query
                    Self.log.error("query failed: \(String(describing: category), privacy: .public)")
                    continuation.resume(throwing: category)
                } else {
                    continuation.resume(returning: value)
                }
            }
            execute(query)
        }
    }
}
