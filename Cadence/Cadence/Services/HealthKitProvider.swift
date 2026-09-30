import Foundation
import CadenceCore
import HealthKit
import CoreLocation

private final class HealthKitLocationAccumulator: @unchecked Sendable {
    var locations: [CLLocation] = []
}

/// Real HealthKit-backed provider (FR-3, FR-2.1, FR-4.1/4.3, FR-2.5). Reads
/// steps and Watch-recorded workouts; writes strength, cardio, and swim workout
/// summaries with HR, distance (per-type), and GPS routes. Detailed set/rep data
/// stays in SwiftData — HealthKit has no schema for it.
@MainActor
final class HealthKitProvider: HealthDataProviding {
    private let store = HKHealthStore()

    /// Anchors are device-local cursors. They deliberately live outside
    /// SwiftData/CloudKit because a cursor belongs to this HealthKit database
    /// and must never be mirrored to another device.
    private let anchorDefaults: UserDefaults

    private enum AnchorKey {
        static let workouts = "health.restore.workouts.anchor.v1"
        static let vo2Max = "health.restore.vo2max.anchor.v1"
    }

    init(anchorDefaults: UserDefaults = .standard) {
        self.anchorDefaults = anchorDefaults
    }

    var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Opens Cladiron on the paired Apple Watch with a workout, using the
    /// app's one health store. watchOS launches or wakes the Watch app and
    /// hands it the configuration (`CadenceWatchAppDelegate.handle(_:)`).
    func startWatchApp(with configuration: HKWorkoutConfiguration,
                       completion: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        store.startWatchApp(with: configuration, completion: completion)
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        let ids: [HKQuantityTypeIdentifier] = [.stepCount, .distanceWalkingRunning,
                                               .flightsClimbed, .activeEnergyBurned, .heartRate,
                                               // Passive readiness (revenue Phase 4): read-only,
                                               // on-device, does not change the Data Not Collected
                                               // privacy label. bodyMass also makes the CLAUDE.md
                                               // HealthKit line true.
                                               .heartRateVariabilitySDNN, .restingHeartRate, .bodyMass, .vo2Max]
        for id in ids { if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) } }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKSeriesType.workoutRoute())
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
        types.insert(HKSeriesType.workoutRoute())
        return types
    }

    func requestAuthorization() async -> HealthAuthorizationStatus {
        guard isHealthDataAvailable else { return .unavailable }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            // Keep the restore path alive while the app is suspended. The next
            // foreground restore still uses an anchored-compatible date query
            // until the device-only anchor store is available, but HealthKit
            // will now wake the app for newly delivered Cladiron workouts.
            try? await store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate)
            if let vo2 = HKQuantityType.quantityType(forIdentifier: .vo2Max) {
                try? await store.enableBackgroundDelivery(for: vo2, frequency: .hourly)
            }
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

    func latestVO2Max() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return nil }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                                                         ascending: false)]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(
                    for: HKUnit(from: "mL/kg*min"))
                continuation.resume(returning: value)
            }
            store.execute(query)
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
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
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
            let energy = w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            // Pull the recorded heart-rate curve for this workout (e.g. one the
            // Watch saved) — historical read only, no watch app needed. Capped to
            // keep the stored series light (feedback batch 4).
            let hr = await heartRateSamples(for: w)
            let route = type.usesGPS ? await routeSamples(for: w) : []
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
                routeSamples: route,
                importedKind: importedKind))
        }
        return result
    }

    // MARK: Cladiron backup restore (H4)

    /// Reads Cladiron-authored workouts separately from the existing third-party
    /// cardio ingest. The source check is exact for both app targets, so another
    /// app's workout can never become a Cladiron restore candidate. HealthKit
    /// does not expose read authorization state; an empty result is therefore a
    /// valid "none visible" result and is explained by the Backup center.
    func readHealthBackups(since: Date?) async -> [HealthBackupReadObject] {
        // Restore uses an anchored query after the first successful read. This
        // picks up late Health-iCloud arrivals without repeatedly scanning the
        // entire database. The older date path remains for callers that ask
        // for a bounded historical window (and for compatibility with the
        // existing ingest surface).
        if since == nil {
            return await readAnchoredHealthBackups()
        }
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let predicate = since.map { HKQuery.predicateForSamples(withStart: $0, end: nil) }
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                                                         ascending: true)]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        var result: [HealthBackupReadObject] = []
        for workout in workouts {
            guard let source = Self.cladironSource(for: workout.sourceRevision) else { continue }
            let importedKind = Self.importedWorkoutKind(from: workout.workoutActivityType)
            let kind: HealthWorkoutPayloadKind = importedKind.isStrength ? .strength : .cardio
            let cardioType = Self.cardioType(from: workout.workoutActivityType)
            let distance = workout.totalDistance?.doubleValue(for: .meter())
            let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            let metadata = Self.stringMetadata(workout.metadata)
            let hr = await heartRateSamples(for: workout)
            let route = kind == .cardio && cardioType.usesGPS
                ? await routeSamples(for: workout)
                : []
            let read = HealthWorkoutReadPayload(
                healthObjectID: workout.uuid,
                kind: kind,
                activityType: importedKind,
                start: workout.startDate,
                end: workout.endDate,
                activeEnergyKcal: energy,
                distanceMeters: distance,
                heartRate: hr,
                route: route,
                metadata: metadata,
                source: source)
            if let decoded = try? HealthBackupDecoder.workout(read) {
                result.append(decoded)
            }
        }

        guard let vo2Type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else { return result }
        let vo2Samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let predicate = since.map { HKQuery.predicateForSamples(withStart: $0, end: nil) }
            let query = HKSampleQuery(sampleType: vo2Type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                                                         ascending: true)]) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
        for sample in vo2Samples {
            guard let source = Self.cladironSource(for: sample.sourceRevision) else { continue }
            let value = sample.quantity.doubleValue(for: HKUnit(from: "mL/kg*min"))
            let payload = HealthVO2ReadPayload(
                healthObjectID: sample.uuid,
                date: sample.startDate,
                value: value,
                metadata: Self.stringMetadata(sample.metadata),
                source: source)
            if let decoded = try? HealthBackupDecoder.vo2(payload) {
                result.append(decoded)
            }
        }
        return result
    }

    /// Reads only newly delivered HealthKit objects and advances the cursor
    /// after the query has returned successfully. A failed query leaves the
    /// prior cursor untouched so the next foreground retry cannot silently
    /// skip data.
    private func readAnchoredHealthBackups() async -> [HealthBackupReadObject] {
        let workoutResult = await anchoredWorkouts()
        let workouts = workoutResult.objects
        var result: [HealthBackupReadObject] = []
        result.append(contentsOf: workoutResult.deleted.map { .deleted(healthObjectID: $0) })
        for workout in workouts {
            guard let source = Self.cladironSource(for: workout.sourceRevision) else { continue }
            let importedKind = Self.importedWorkoutKind(from: workout.workoutActivityType)
            let kind: HealthWorkoutPayloadKind = importedKind.isStrength ? .strength : .cardio
            let cardioType = Self.cardioType(from: workout.workoutActivityType)
            let distance = workout.totalDistance?.doubleValue(for: .meter())
            let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                .sumQuantity()?.doubleValue(for: .kilocalorie())
            let metadata = Self.stringMetadata(workout.metadata)
            let hr = await heartRateSamples(for: workout)
            let route = kind == .cardio && cardioType.usesGPS
                ? await routeSamples(for: workout)
                : []
            let read = HealthWorkoutReadPayload(
                healthObjectID: workout.uuid,
                kind: kind,
                activityType: importedKind,
                start: workout.startDate,
                end: workout.endDate,
                activeEnergyKcal: energy,
                distanceMeters: distance,
                heartRate: hr,
                route: route,
                metadata: metadata,
                source: source)
            if let decoded = try? HealthBackupDecoder.workout(read) {
                result.append(decoded)
            }
        }

        let vo2Result = await anchoredVO2Samples()
        let vo2Samples = vo2Result.objects
        result.append(contentsOf: vo2Result.deleted.map { .deleted(healthObjectID: $0) })
        for sample in vo2Samples {
            guard let source = Self.cladironSource(for: sample.sourceRevision) else { continue }
            let value = sample.quantity.doubleValue(for: HKUnit(from: "mL/kg*min"))
            let payload = HealthVO2ReadPayload(
                healthObjectID: sample.uuid,
                date: sample.startDate,
                value: value,
                metadata: Self.stringMetadata(sample.metadata),
                source: source)
            if let decoded = try? HealthBackupDecoder.vo2(payload) {
                result.append(decoded)
            }
        }
        return result
    }

    private func anchoredWorkouts() async -> (objects: [HKWorkout], deleted: [UUID]) {
        guard let result = await anchoredObjects(
            sampleType: .workoutType(),
            anchor: loadAnchor(forKey: AnchorKey.workouts)) else { return ([], []) }
        saveAnchor(result.anchor, forKey: AnchorKey.workouts)
        return (result.objects.compactMap { $0 as? HKWorkout },
                result.deleted.map(\.uuid))
    }

    private func anchoredVO2Samples() async -> (objects: [HKQuantitySample], deleted: [UUID]) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .vo2Max),
              let result = await anchoredObjects(
                sampleType: type,
                anchor: loadAnchor(forKey: AnchorKey.vo2Max)) else { return ([], []) }
        saveAnchor(result.anchor, forKey: AnchorKey.vo2Max)
        return (result.objects.compactMap { $0 as? HKQuantitySample },
                result.deleted.map(\.uuid))
    }

    private func anchoredObjects(sampleType: HKSampleType,
                                 anchor: HKQueryAnchor?) async
        -> (objects: [HKSample], deleted: [HKDeletedObject], anchor: HKQueryAnchor)? {
        await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: sampleType,
                                              predicate: nil,
                                              anchor: anchor,
                                              limit: HKObjectQueryNoLimit) { _, samples, deleted, newAnchor, error in
                guard error == nil, let newAnchor else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: (samples ?? [], deleted ?? [], newAnchor))
            }
            store.execute(query)
        }
    }

    private func loadAnchor(forKey key: String) -> HKQueryAnchor? {
        guard let data = anchorDefaults.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func saveAnchor(_ anchor: HKQueryAnchor, forKey key: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor,
                                                            requiringSecureCoding: true) else { return }
        anchorDefaults.set(data, forKey: key)
    }

    private static let cladironPhoneBundleID = "guru.parso.ios-workout-app"
    private static let cladironWatchBundleID = "guru.parso.ios-workout-app.watchkitapp"

    private static func cladironSource(for revision: HKSourceRevision) -> HealthBackupSource? {
        let bundleID = revision.source.bundleIdentifier
        if bundleID == cladironPhoneBundleID { return .iphone }
        if bundleID == cladironWatchBundleID { return .watch }
        return nil
    }

    private static func stringMetadata(_ values: [String: Any]?) -> [String: String] {
        guard let values else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in values {
            if let string = value as? String {
                result[key] = string
            } else if let number = value as? NSNumber {
                result[key] = number.stringValue
            } else if let date = value as? Date {
                result[key] = ISO8601DateFormatter().string(from: date)
            }
        }
        return result
    }

    /// Reads the heart-rate samples recorded across `[start, end]` and maps them to
    /// `HRSamplePoint`s relative to `start`, downsampled so long workouts stay light.
    private func heartRateSamples(for workout: HKWorkout) async -> [HRSamplePoint] {
        guard isHealthDataAvailable,
              let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let timePredicate = HKQuery.predicateForSamples(withStart: workout.startDate,
                                                            end: workout.endDate,
                                                            options: .strictStartDate)
            let workoutPredicate = HKQuery.predicateForObjects(from: workout)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [timePredicate,
                                                                                  workoutPredicate])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        let points = samples.map {
            HRSamplePoint(t: $0.startDate.timeIntervalSince(workout.startDate),
                          bpm: $0.quantity.doubleValue(for: unit))
        }
        return HRSampling.downsample(points)
    }

    /// Reads the GPS route attached to a HealthKit workout. Route data is
    /// permission-gated by HealthKit and remains relative to the workout start
    /// when it enters the app's portable model.
    private func routeSamples(for workout: HKWorkout) async -> [LocationFix] {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: routeType, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(query)
        }

        var locations: [CLLocation] = []
        for route in routes {
            let chunk: [CLLocation] = await withCheckedContinuation { continuation in
                let accumulator = HealthKitLocationAccumulator()
                let query = HKWorkoutRouteQuery(route: route) { _, newLocations, done, _ in
                    accumulator.locations.append(contentsOf: newLocations ?? [])
                    if done { continuation.resume(returning: accumulator.locations) }
                }
                store.execute(query)
            }
            locations.append(contentsOf: chunk)
        }

        return locations.sorted { $0.timestamp < $1.timestamp }.map {
            LocationFix(t: $0.timestamp.timeIntervalSince(workout.startDate),
                        lat: $0.coordinate.latitude, lon: $0.coordinate.longitude,
                        elevation: $0.altitude, horizontalAccuracy: $0.horizontalAccuracy)
        }
    }

    // MARK: Write summary strength workout (FR-4.3)

    func saveStrengthWorkout(_ summary: StrengthWorkoutSummary) async -> UUID? {
        guard isHealthDataAvailable else { return nil }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: summary.start)
            var metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: summary.id.uuidString,
                HKMetadataKeySyncVersion: NSNumber(value: CladironHealthBackup.syncVersion(for: summary.updatedAt ?? summary.end)),
                CladironHealthBackup.schemaKey: CladironHealthBackup.schemaVersion,
            ]
            for (key, value) in summary.metadata { metadata[key] = value }
            try await builder.addMetadata(metadata)
            if let kcal = summary.activeEnergyKcal,
               let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
                let sample = HKCumulativeQuantitySample(type: energyType, quantity: quantity,
                                                        start: summary.start, end: summary.end)
                try await builder.addSamples([sample])
            }
            if let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
                let unit = HKUnit.count().unitDivided(by: .minute())
                let samples = summary.hrSamples.map { point in
                    let time = summary.start.addingTimeInterval(point.t)
                    return HKQuantitySample(type: hrType,
                                            quantity: HKQuantity(unit: unit, doubleValue: point.bpm),
                                            start: time, end: time)
                }
                if !samples.isEmpty { try await builder.addSamples(samples) }
            }
            try await addOwnerSetActivities(to: builder, summary: summary)
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
            var metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: summary.id.uuidString,
                HKMetadataKeySyncVersion: NSNumber(value: CladironHealthBackup.syncVersion(for: summary.updatedAt ?? summary.end)),
                CladironHealthBackup.schemaKey: CladironHealthBackup.schemaVersion,
            ]
            if let title = summary.customTitle, !title.isEmpty {
                metadata[CladironHealthBackup.titleKey] = title
            }
            try await builder.addMetadata(metadata)
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

    func saveAssessment(_ payload: HealthAssessmentPayload) async -> UUID? {
        guard isHealthDataAvailable else { return nil }
        let config = HKWorkoutConfiguration()
        let kind = AssessmentKind(rawValue: payload.kind)
        if kind == .cooper12min || kind == .run1_5mile || kind == .rockportWalk || kind == .queensCollegeStep {
            config.activityType = .running
        } else if kind == .wingate {
            config.activityType = .cycling
        } else if kind == .plankHold || kind == .hollowHold {
            config.activityType = .coreTraining
        } else {
            config.activityType = .functionalStrengthTraining
        }
        let end = payload.date.addingTimeInterval(60)
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: payload.date)
            var metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: payload.id.uuidString,
                HKMetadataKeySyncVersion: NSNumber(value: CladironHealthBackup.syncVersion(for: payload.updatedAt)),
                CladironHealthBackup.schemaKey: CladironHealthBackup.schemaVersion,
                CladironHealthBackup.assessmentIDKey: payload.id.uuidString,
                CladironHealthBackup.assessmentKindKey: payload.kind,
                CladironHealthBackup.assessmentValueKey: payload.value
            ]
            if let protocolName = payload.protocolName, !protocolName.isEmpty {
                metadata[CladironHealthBackup.assessmentProtocolKey] = protocolName
            }
            if let value = payload.inputDistance { metadata[CladironHealthBackup.assessmentInputDistanceKey] = value }
            if let value = payload.inputTime { metadata[CladironHealthBackup.assessmentInputTimeKey] = value }
            if let value = payload.inputEndingHR { metadata[CladironHealthBackup.assessmentInputEndingHRKey] = value }
            metadata[CladironHealthBackup.assessmentInputWeightKey] = payload.inputWeight
            metadata[CladironHealthBackup.assessmentInputRepsKey] = payload.inputReps
            if let value = payload.exerciseName, !value.isEmpty { metadata[CladironHealthBackup.assessmentExerciseNameKey] = value }
            if let value = payload.notes, !value.isEmpty { metadata[CladironHealthBackup.assessmentNotesKey] = value }
            if let value = payload.inputAge { metadata[CladironHealthBackup.assessmentInputAgeKey] = value }
            if let value = payload.inputSex { metadata[CladironHealthBackup.assessmentInputSexKey] = value }
            try await builder.addMetadata(metadata)
            try await builder.endCollection(at: end)
            return try await builder.finishWorkout()?.uuid
        } catch {
            return nil
        }
    }

    func deleteHealthBackup(kind: HealthBackupEntityKind, id: UUID) async -> Bool {
        guard isHealthDataAvailable else { return false }
        // HealthKit's sync identifier is the only identity this app owns. The
        // predicate is deliberately constrained to Cladiron-authored objects;
        // deleting a third-party workout is never attempted.
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier,
                                                    allowedValues: [id.uuidString])
        return await withCheckedContinuation { continuation in
            store.deleteObjects(of: .workoutType(), predicate: predicate) { success, _, _ in
                continuation.resume(returning: success)
            }
        }
    }

    /// Stores owner-only sets as HealthKit workout activities. The payload is
    /// deliberately metadata-only: Health receives the user's own training
    /// facts, while partner identity and partner loads never cross the app
    /// boundary. Legacy/edited sets without monotonic timestamps use synthetic
    /// evenly-spaced intervals, which keeps the payload deterministic.
    private func addOwnerSetActivities(to builder: HKWorkoutBuilder,
                                       summary: StrengthWorkoutSummary) async throws {
        guard let json = summary.metadata[CladironHealthBackup.ownerSetsKey],
              let data = json.data(using: .utf8),
              let payloads = try? JSONDecoder().decode([CladironHealthBackup.SetPayload].self, from: data),
              !payloads.isEmpty else { return }

        let ordered = payloads.sorted { $0.order == $1.order ? $0.id.uuidString < $1.id.uuidString : $0.order < $1.order }
        let duration = max(1, summary.end.timeIntervalSince(summary.start))
        let syntheticStep = duration / Double(ordered.count)
        var previousEnd = summary.start
        var usedSynthetic = false

        for (index, payload) in ordered.enumerated() {
            let candidateEnd = payload.completedAt.map { min(summary.end, max(summary.start, $0)) }
            let validCandidate = candidateEnd.map { $0 > previousEnd } ?? false
            let end = validCandidate ? candidateEnd! : summary.start.addingTimeInterval(syntheticStep * Double(index + 1))
            let synthetic = !validCandidate
            usedSynthetic = usedSynthetic || synthetic
            let start: Date
            if synthetic {
                start = summary.start.addingTimeInterval(syntheticStep * Double(index))
            } else {
                start = max(summary.start, end.addingTimeInterval(-90))
            }
            let config = HKWorkoutConfiguration()
            config.activityType = .traditionalStrengthTraining
            var metadata: [String: Any] = [
                CladironHealthBackup.schemaKey: CladironHealthBackup.schemaVersion,
                CladironHealthBackup.setIDKey: payload.id.uuidString,
                CladironHealthBackup.exerciseKey: payload.exerciseKey,
                CladironHealthBackup.exerciseNameKey: payload.exerciseName,
                CladironHealthBackup.orderKey: payload.order,
                CladironHealthBackup.weightKgKey: payload.weightKg,
                CladironHealthBackup.repsKey: payload.reps,
                CladironHealthBackup.warmupKey: payload.isWarmup,
                CladironHealthBackup.bodyweightKey: payload.usesBodyweight,
                CladironHealthBackup.barWeightKgKey: payload.barWeightKg,
                CladironHealthBackup.loadMultiplierKey: payload.loadMultiplier,
                CladironHealthBackup.timingSyntheticKey: synthetic
            ]
            if let rpe = payload.rpe { metadata[CladironHealthBackup.rPEKey] = rpe }
            if let note = payload.note, !note.isEmpty { metadata[CladironHealthBackup.noteKey] = note }
            if let mode = payload.loadAccountingMode { metadata[CladironHealthBackup.loadModeKey] = mode }
            let activity = HKWorkoutActivity(workoutConfiguration: config,
                                              start: start, end: end,
                                              metadata: metadata)
            try await builder.addWorkoutActivity(activity)
            previousEnd = end
        }

        // `usedSynthetic` is intentionally not written into the parent object:
        // each activity carries its own timing provenance and old HealthKit
        // readers can still decode the parent metadata safely.
        _ = usedSynthetic
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
        case .elliptical: return .elliptical
        case .stairClimber: return .stairClimbing
        case .other: return .mixedCardio
        }
    }

    /// Maps a cardio type to the appropriate HealthKit distance quantity type.
    /// Resolves through the semantic `CardioDistanceKind` so the mapping is
    /// headlessly testable (field-test batch 2026-08-20 P8).
    static func distanceType(for t: CardioType) -> HKQuantityTypeIdentifier {
        switch t.distanceKind {
        case .walkingRunning: return .distanceWalkingRunning
        case .cycling: return .distanceCycling
        case .swimming: return .distanceSwimming
        case .rowing:
            if #available(iOS 18, *) { return .distanceRowing }
            return HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifierDistanceRowing")
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
        case .elliptical: return .elliptical
        case .stairClimbing, .stairs, .stepTraining: return .stairClimber
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
