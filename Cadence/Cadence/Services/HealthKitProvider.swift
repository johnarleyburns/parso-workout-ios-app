import Foundation
import CadenceCore
import HealthKit
import CoreLocation

/// Real HealthKit-backed provider (FR-3, FR-2.1, FR-4.1/4.3, FR-2.5). Reads
/// steps and Watch-recorded workouts; writes strength, cardio, and swim workout
/// summaries with HR, distance (per-type), and GPS routes. Detailed set/rep data
/// stays in SwiftData — HealthKit has no schema for it.
@MainActor
final class HealthKitProvider: HealthDataProviding {
    private let store = HKHealthStore()

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        let ids: [HKQuantityTypeIdentifier] = [.stepCount, .distanceWalkingRunning,
                                               .flightsClimbed, .activeEnergyBurned, .heartRate,
                                               // Passive readiness (revenue Phase 4): read-only,
                                               // on-device, does not change the Data Not Collected
                                               // privacy label. bodyMass also makes the CLAUDE.md
                                               // HealthKit line true.
                                               .heartRateVariabilitySDNN, .restingHeartRate, .bodyMass]
        for id in ids { if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        return types
    }

    /// Write authorizations cover every quantity type the app may write.
    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        let ids: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
            .heartRate
        ]
        for id in ids { if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) } }
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

    // MARK: Passive readiness (revenue Phase 4)

    /// Trailing daily HRV (SDNN, ms), resting HR (bpm), and sleep (hours). One
    /// `PassiveReadinessSample` per day where any metric exists. On-device reads.
    func passiveReadinessSamples(days: Int) async -> [PassiveReadinessSample] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let windowStart = cal.date(byAdding: .day, value: -days, to: today) else { return [] }

        async let hrv = dailyAverage(.heartRateVariabilitySDNN,
                                     unit: HKUnit.secondUnit(with: .milli),
                                     start: windowStart, end: Date())
        async let rhr = dailyAverage(.restingHeartRate,
                                     unit: HKUnit.count().unitDivided(by: .minute()),
                                     start: windowStart, end: Date())
        async let sleep = dailySleepHours(start: windowStart, end: Date())

        let hrvByDay = await hrv
        let rhrByDay = await rhr
        let sleepByDay = await sleep

        let allDays = Set(hrvByDay.keys).union(rhrByDay.keys).union(sleepByDay.keys)
        return allDays.sorted().map { day in
            PassiveReadinessSample(date: day,
                                   hrvSDNN: hrvByDay[day],
                                   restingHR: rhrByDay[day],
                                   sleepHours: sleepByDay[day])
        }
    }

    /// Per-day discrete average of a quantity type, keyed by start-of-day.
    private func dailyAverage(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                              start: Date, end: Date) async -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [:] }
        let cal = Calendar.current
        return await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let anchor = cal.startOfDay(for: start)
            let interval = DateComponents(day: 1)
            let q = HKStatisticsCollectionQuery(quantityType: type,
                                                quantitySamplePredicate: predicate,
                                                options: .discreteAverage,
                                                anchorDate: anchor,
                                                intervalComponents: interval)
            q.initialResultsHandler = { _, collection, _ in
                var out: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let avg = stats.averageQuantity()?.doubleValue(for: unit) {
                        out[cal.startOfDay(for: stats.startDate)] = avg
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Per-day asleep hours, keyed by start-of-day of the sample's start.
    private func dailySleepHours(start: Date, end: Date) async -> [Date: Double] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let cal = Calendar.current
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        var out: [Date: Double] = [:]
        for s in samples where asleepValues.contains(s.value) {
            let hours = s.endDate.timeIntervalSince(s.startDate) / 3600
            out[cal.startOfDay(for: s.startDate), default: 0] += hours
        }
        return out
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
            let source: CardioSource = Self.isWatchSource(w.sourceRevision) ? .watch : .iphone
            let importedKind = Self.importedWorkoutKind(from: w.workoutActivityType)
            let type = Self.cardioType(from: w.workoutActivityType)
            let summary = IngestedWorkout(
                id: w.uuid,
                type: type,
                start: w.startDate, end: w.endDate,
                source: source,
                importedKind: importedKind)
            guard WorkoutRepository.shouldAutoImport(summary) else { continue }

            let distance = w.totalDistance?.doubleValue(for: .meter())
            let energy = w.totalEnergyBurned?.doubleValue(for: .kilocalorie())
            // Pull the recorded heart-rate curve for this workout (e.g. one the
            // Watch saved) — historical read only, no watch app needed. Capped to
            // keep the stored series light (feedback batch 4).
            let hr = await heartRateSamples(start: w.startDate, end: w.endDate)
            let bpms = hr.map(\.bpm).filter { $0 > 0 }
            result.append(IngestedWorkout(
                id: w.uuid,
                type: type,
                start: w.startDate, end: w.endDate,
                distanceMeters: distance, activeEnergyKcal: energy,
                avgHeartRate: bpms.isEmpty ? nil : bpms.reduce(0, +) / Double(bpms.count),
                maxHeartRate: bpms.max(),
                source: source,
                hrSamples: hr,
                importedKind: importedKind))
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
               let distType = HKQuantityType.quantityType(forIdentifier: Self.distanceType(for: summary.type)) {
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

            // Phase 2 — attach GPS route (FR-2.5).
            if let hkWorkout = workout, !summary.route.isEmpty {
                try? await writeRoute(summary.route, start: summary.start, workout: hkWorkout)
            }
            return workout?.uuid
        } catch {
            return nil
        }
    }

    /// Writes a GPS route as an `HKWorkoutRoute` attached to `workout`.
    private func writeRoute(_ fixes: [LocationFix], start: Date, workout: HKWorkout) async throws {
        let locations = fixes.map { fix in
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: fix.lat, longitude: fix.lon),
                       altitude: fix.elevation,
                       horizontalAccuracy: max(0, fix.horizontalAccuracy),
                       verticalAccuracy: -1,
                       timestamp: start.addingTimeInterval(fix.t))
        }
        let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
        try await routeBuilder.insertRouteData(locations)
        try await routeBuilder.finishRoute(with: workout, metadata: nil)
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

    /// Maps a cardio type to the appropriate HealthKit distance quantity type.
    static func distanceType(for t: CardioType) -> HKQuantityTypeIdentifier {
        switch t {
        case .run, .walk: return .distanceWalkingRunning
        case .cycle: return .distanceCycling
        case .swim: return .distanceSwimming
        default: return .distanceWalkingRunning
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

    static func importedWorkoutKind(from t: HKWorkoutActivityType) -> ImportedWorkoutKind {
        switch t {
        case .traditionalStrengthTraining: return .traditionalStrength
        case .functionalStrengthTraining: return .functionalStrength
        case .running: return .running
        case .cycling: return .cycling
        case .swimming: return .swimming
        case .boxing, .martialArts: return .boxing
        case .highIntensityIntervalTraining: return .hiit
        case .walking: return .walking
        case .rowing: return .rowing
        default: return .other
        }
    }

    private static func isWatchSource(_ sourceRevision: HKSourceRevision) -> Bool {
        let source = sourceRevision.source
        let fields = [
            source.name,
            source.bundleIdentifier,
            sourceRevision.productType ?? ""
        ]
        return fields.contains { $0.localizedCaseInsensitiveContains("watch") }
    }
}
