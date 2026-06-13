import Foundation
import CadenceCore
import HealthKit

/// Real HealthKit-backed provider (FR-3, FR-2.1, FR-4.1/4.3). Reads steps and
/// Watch-recorded workouts; writes summary strength workouts. Detailed set/rep
/// data stays in SwiftData — HealthKit has no schema for it.
final class HealthKitProvider: HealthDataProviding, @unchecked Sendable {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        let ids: [HKQuantityTypeIdentifier] = [.stepCount, .distanceWalkingRunning,
                                               .flightsClimbed, .activeEnergyBurned, .heartRate]
        for id in ids { if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) } }
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let e = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(e) }
        return types
    }

    func requestAuthorization() async -> HealthAuthorizationStatus {
        guard isHealthDataAvailable else { return .unavailable }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return .authorized
        } catch {
            return .denied
        }
    }

    // MARK: Steps & activity (FR-3)

    func todayActivity() async -> DayActivity {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        return await activity(on: start)
    }

    func activityTrend(days: Int) async -> [DayActivity] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [DayActivity] = []
        for i in stride(from: days - 1, through: 0, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -i, to: today) else { continue }
            result.append(await activity(on: day))
        }
        return result
    }

    private func activity(on dayStart: Date) async -> DayActivity {
        let cal = Calendar.current
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
        async let steps = sum(.stepCount, unit: .count(), start: dayStart, end: dayEnd)
        async let dist = sum(.distanceWalkingRunning, unit: .meter(), start: dayStart, end: dayEnd)
        async let flights = sum(.flightsClimbed, unit: .count(), start: dayStart, end: dayEnd)
        async let energy = sum(.activeEnergyBurned, unit: .kilocalorie(), start: dayStart, end: dayEnd)
        return DayActivity(date: dayStart,
                           steps: Int(await steps),
                           distanceMeters: await dist,
                           flightsClimbed: Int(await flights),
                           activeEnergyKcal: await energy)
    }

    private func sum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    // MARK: Workout ingest (FR-2.1)

    func newWorkouts(since: Date?) async -> [IngestedWorkout] {
        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let predicate = since.map { HKQuery.predicateForSamples(withStart: $0, end: nil) }
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 50,
                                  sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        var result: [IngestedWorkout] = []
        for w in workouts {
            let distance = w.totalDistance?.doubleValue(for: .meter())
            let energy = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            // Pull the recorded heart-rate curve for this workout (e.g. one the
            // Watch saved) — historical read only, no watch app needed. Capped to
            // keep the stored series light (feedback batch 4).
            let hr = await heartRateSamples(start: w.startDate, end: w.endDate)
            let bpms = hr.map(\.bpm).filter { $0 > 0 }
            result.append(IngestedWorkout(
                id: w.uuid,
                type: Self.cardioType(from: w.workoutActivityType),
                start: w.startDate, end: w.endDate,
                distanceMeters: distance, activeEnergyKcal: energy,
                avgHeartRate: bpms.isEmpty ? nil : bpms.reduce(0, +) / Double(bpms.count),
                maxHeartRate: bpms.max(),
                source: w.sourceRevision.source.name.localizedCaseInsensitiveContains("watch") ? .watch : .iphone,
                hrSamples: hr))
        }
        return result
    }

    /// Reads the heart-rate samples recorded across `[start, end]` and maps them to
    /// `HRSamplePoint`s relative to `start`, downsampled so long workouts stay light.
    private func heartRateSamples(start: Date, end: Date) async -> [HRSamplePoint] {
        guard isHealthDataAvailable,
              let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        let points = samples.map {
            HRSamplePoint(t: $0.startDate.timeIntervalSince(start),
                          bpm: $0.quantity.doubleValue(for: unit))
        }
        return HRSampling.downsample(points)
    }

    /// The single most-recent heart-rate sample HealthKit has (e.g. the Watch's
    /// latest reading) — for the pre-workout HR screen (feedback batch 5). Passive
    /// historical read; no watch app and no `HKWorkoutSession` needed. Can lag,
    /// since the Watch batches its background HR writes.
    func latestHeartRate() async -> HRReading? {
        guard isHealthDataAvailable,
              let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let sample: HKQuantitySample? = await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: hrType, predicate: nil, limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample])?.first)
            }
            store.execute(q)
        }
        guard let sample else { return nil }
        return HRReading(bpm: sample.quantity.doubleValue(for: unit), date: sample.endDate)
    }

    // MARK: Write summary strength workout (FR-4.3)

    func saveStrengthWorkout(_ summary: StrengthWorkoutSummary) async -> UUID? {
        guard isHealthDataAvailable else { return nil }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: summary.start)
            if let kcal = summary.activeEnergyKcal,
               let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
                let sample = HKCumulativeQuantitySample(type: energyType, quantity: quantity,
                                                        start: summary.start, end: summary.end)
                try await builder.addSamples([sample])
            }
            try await builder.endCollection(at: summary.end)
            let workout = try await builder.finishWorkout()
            return workout?.uuid
        } catch {
            return nil
        }
    }

    // MARK: Write summary cardio workout (FR-2.5)

    func saveCardioWorkout(_ summary: CardioWorkoutSummary) async -> UUID? {
        guard isHealthDataAvailable else { return nil }
        let config = HKWorkoutConfiguration()
        config.activityType = Self.activityType(for: summary.type)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: summary.start)
            var samples: [HKSample] = []
            if let kcal = summary.activeEnergyKcal,
               let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                samples.append(HKCumulativeQuantitySample(
                    type: energyType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                    start: summary.start, end: summary.end))
            }
            if let meters = summary.distanceMeters,
               let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
                samples.append(HKCumulativeQuantitySample(
                    type: distType, quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                    start: summary.start, end: summary.end))
            }
            if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
                let unit = HKUnit.count().unitDivided(by: .minute())
                for p in summary.hrSamples {
                    let t = summary.start.addingTimeInterval(p.t)
                    samples.append(HKQuantitySample(type: hrType,
                        quantity: HKQuantity(unit: unit, doubleValue: p.bpm), start: t, end: t))
                }
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }
            try await builder.endCollection(at: summary.end)
            let workout = try await builder.finishWorkout()
            return workout?.uuid
        } catch {
            return nil
        }
    }

    static func activityType(for t: CardioType) -> HKWorkoutActivityType {
        switch t {
        case .run: return .running
        case .cycle: return .cycling
        case .swim: return .swimming
        case .boxing: return .boxing
        case .hiit: return .highIntensityIntervalTraining
        case .walk: return .walking
        case .rowing: return .rowing
        case .other: return .mixedCardio
        }
    }

    // MARK: Mapping

    static func cardioType(from t: HKWorkoutActivityType) -> CardioType {
        switch t {
        case .running: return .run
        case .cycling: return .cycle
        case .swimming: return .swim
        case .boxing, .martialArts: return .boxing
        case .highIntensityIntervalTraining: return .hiit
        case .walking: return .walk
        case .rowing: return .rowing
        default: return .other
        }
    }
}
