import Foundation
import CadenceCore

/// Stable semantic fingerprint of everything that can change the generated Today
/// strength plan. Built only from the immutable request snapshot, so cache
/// validation and generation cannot drift apart. It deliberately excludes view
/// identity, refresh tokens and sub-day time (the local day key covers dates).
public enum TodaySuggestedWorkoutFingerprint {
    public static func make(input: SuggestedWorkoutInput,
                            unitRaw: String,
                            warmupMinutes: Int,
                            cooldownMinutes: Int,
                            extras: [String] = []) -> String {
        var h = Hasher64()
        h.add("v1")
        h.add(unitRaw); h.add(warmupMinutes); h.add(cooldownMinutes)
        for e in extras.sorted() { h.add("x:" + e) }
        for (k, v) in input.completedSetsByMuscle.sorted(by: { $0.key < $1.key }) {
            h.add(k); h.add(v)
        }
        for c in input.candidates.sorted(by: { $0.id < $1.id }) {
            h.add(c.id); h.add(c.name); h.add(String(describing: c.mechanics))
            for m in c.primaryMuscles { h.add("p:" + m) }
            for m in c.secondaryMuscles { h.add("s:" + m) }
            h.add(c.equipment.map { String(describing: $0) } ?? "-")
            h.add(c.volumeEligible); h.add(c.isPersonalized)
            for t in c.trainingTypes { h.add("t:" + String(describing: t)) }
            for t in c.modalities { h.add("m:" + String(describing: t)) }
            for t in c.sportContexts { h.add("c:" + String(describing: t)) }
        }
        for id in input.recentlyCompletedCandidateIDs.sorted() { h.add("r:" + id) }
        h.add(input.historyData ?? Data())
        h.add(input.historyWorkoutCount); h.add(input.historyWorkingSetCount)
        for g in input.trackedGroups.map(\.rawValue).sorted() { h.add("g:" + g) }
        h.add(input.preferredSetsPerExercise)
        h.add(input.mostRecentExerciseWorkingSets ?? -1)
        h.add(String(describing: input.trainingGoal))
        h.add(String(describing: input.preferredStyle))
        if let ctx = input.engineContext {
            h.add(String(describing: ctx.experience))
            h.add(ctx.environment)
            for e in ctx.availableEquipment.map({ String(describing: $0) }).sorted() { h.add("e:" + e) }
            let s = ctx.schedule
            h.add(s.strengthDaysPerWeek); h.add(s.cardioDaysPerWeek)
            h.add(String(describing: s.restPreference)); h.add(s.allowsTwoADays)
            h.add(String(describing: s.sameDayCardioTiming))
            h.add(s.dailyStepTarget); h.add(s.desiredSetsPerExercise)
        }
        return h.hex
    }

    /// FNV-1a 64 over length-prefixed fields (stable across launches, unlike `Hasher`).
    private struct Hasher64 {
        var state: UInt64 = 0xcbf29ce484222325
        mutating func add(_ data: Data) {
            var n = UInt64(data.count)
            for _ in 0..<8 { mix(UInt8(n & 0xff)); n >>= 8 }
            for b in data { mix(b) }
        }
        mutating func add(_ s: String) { add(Data(s.utf8)) }
        mutating func add(_ i: Int) { add(String(i)) }
        mutating func add(_ b: Bool) { add(b ? "1" : "0") }
        mutating func add(_ d: Double) { add(String(d.bitPattern)) }
        private mutating func mix(_ b: UInt8) { state = (state ^ UInt64(b)) &* 0x100000001b3 }
        var hex: String { String(state, radix: 16) }
    }
}

/// App-owned Codable representation of a generated Today plan. Transient UI
/// identities (`EditablePlan.id`, set ids) are regenerated on reconstruction.
public struct TodaySuggestedPlanPayload: Codable, Equatable, Sendable {
    public struct SetDTO: Codable, Equatable, Sendable {
        public var targetReps: Int
        public var targetWeight: Double?
        public var loadMode: String
        public var oneRepMaxPercent: Double?
    }
    public struct PerformerDTO: Codable, Equatable, Sendable {
        public var performerID: UUID?
        public var name: String
        public var sets: [SetDTO]
    }
    public struct ExerciseDTO: Codable, Equatable, Sendable {
        public var name: String
        public var sets: [SetDTO]
        public var notes: String
        public var supersetGroup: SupersetGroupID?
        public var performerPlans: [PerformerDTO]
    }
    public struct ExerciseRationaleDTO: Codable, Equatable, Sendable {
        public var exerciseName: String
        public var whyExercise: String
        public var whySetRep: String
    }
    public struct RationaleDTO: Codable, Equatable, Sendable {
        public var whyWorkout: String
        public var exercises: [ExerciseRationaleDTO]
    }

    public var title: String
    public var warmupMinutes: Int
    public var cooldownMinutes: Int
    public var exercises: [ExerciseDTO]
    public var partnerIDs: [UUID]
    public var enginePlanId: String?
    public var engineRevisionId: String?
    public var enginePlanJSON: Data?
    public var suggestedWorkoutStyle: String?
    public var rationale: RationaleDTO?

    private static func dto(_ s: EditableSet) -> SetDTO {
        SetDTO(targetReps: s.targetReps, targetWeight: s.targetWeight,
               loadMode: s.loadMode.rawValue, oneRepMaxPercent: s.oneRepMaxPercent)
    }

    private static func set(_ d: SetDTO) -> EditableSet {
        EditableSet(targetReps: d.targetReps, targetWeight: d.targetWeight,
                    loadMode: EditableLoadMode(rawValue: d.loadMode) ?? .straight,
                    oneRepMaxPercent: d.oneRepMaxPercent)
    }

    public init(_ plan: EditablePlan) {
        title = plan.title
        warmupMinutes = plan.warmupMinutes
        cooldownMinutes = plan.cooldownMinutes
        exercises = plan.exercises.map { e in
            ExerciseDTO(name: e.name, sets: e.sets.map(Self.dto), notes: e.notes,
                        supersetGroup: e.supersetGroup,
                        performerPlans: e.performerPlans.map {
                            PerformerDTO(performerID: $0.performerID, name: $0.name,
                                         sets: $0.sets.map(Self.dto))
                        })
        }
        partnerIDs = plan.partnerIDs
        enginePlanId = plan.enginePlanId
        engineRevisionId = plan.engineRevisionId
        enginePlanJSON = plan.enginePlanJSON
        suggestedWorkoutStyle = plan.suggestedWorkoutStyle?.rawValue
        rationale = plan.recommendationRationale.map { r in
            RationaleDTO(whyWorkout: r.whyWorkout,
                         exercises: r.exercises.map {
                             ExerciseRationaleDTO(exerciseName: $0.exerciseName,
                                                  whyExercise: $0.whyExercise,
                                                  whySetRep: $0.whySetRep)
                         })
        }
    }

    /// A fresh editable draft with new transient identities.
    public func makePlan() -> EditablePlan {
        EditablePlan(
            title: title, warmupMinutes: warmupMinutes, cooldownMinutes: cooldownMinutes,
            exercises: exercises.map { e in
                EditableExercise(
                    name: e.name, sets: e.sets.map(Self.set), notes: e.notes,
                    performerPlans: e.performerPlans.map {
                        EditablePerformerPlan(performerID: $0.performerID, name: $0.name,
                                              sets: $0.sets.map(Self.set))
                    },
                    supersetGroup: e.supersetGroup)
            },
            partnerIDs: partnerIDs,
            enginePlanId: enginePlanId, engineRevisionId: engineRevisionId,
            enginePlanJSON: enginePlanJSON,
            suggestedWorkoutStyle: suggestedWorkoutStyle.flatMap(SuggestedWorkoutStyle.init(rawValue:)),
            recommendationRationale: rationale.map { r in
                SuggestedWorkoutRationale(
                    whyWorkout: r.whyWorkout,
                    exercises: r.exercises.map {
                        SuggestedExerciseRationale(exerciseName: $0.exerciseName,
                                                   whyExercise: $0.whyExercise,
                                                   whySetRep: $0.whySetRep)
                    })
            })
    }
}

/// Durable, versioned, same-local-calendar-day cache of the Today suggestion.
/// Valid only while both the local day key and the semantic fingerprint match.
/// An actor so concurrent loads for the same key coalesce onto one generation.
public actor TodaySuggestedWorkoutCacheStore {
    public static let schemaVersion = 1

    struct Envelope: Codable {
        var schemaVersion: Int
        var dayKey: String
        var fingerprint: String
        var updatedAt: Date
        var plan: TodaySuggestedPlanPayload
    }

    private let fileURL: URL?
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var memory: Envelope?
    private var memoryLoaded = false
    private var inFlight: [String: Task<TodaySuggestedPlanPayload?, Never>] = [:]
    private var epoch = 0

    /// `fileURL == nil` keeps the cache in memory only (tests / UI-test mode).
    public init(fileURL: URL?, calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
    }

    public static func defaultFileURL() -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("TodaySuggestedWorkout.v1.json")
    }

    public func dayKey() -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now())
        let tz = calendar.timeZone.identifier
        return String(format: "%04d-%02d-%02d@%@", c.year ?? 0, c.month ?? 0, c.day ?? 0, tz)
    }

    /// Returns the cached plan for this day + fingerprint, deleting any stale,
    /// corrupt or wrong-version record.
    public func restore(fingerprint: String) -> TodaySuggestedPlanPayload? {
        guard let env = loadEnvelope() else { return nil }
        guard env.schemaVersion == Self.schemaVersion,
              env.dayKey == dayKey(),
              env.fingerprint == fingerprint,
              !env.plan.exercises.isEmpty else {
            if env.dayKey != dayKey() || env.fingerprint != fingerprint
                || env.schemaVersion != Self.schemaVersion || env.plan.exercises.isEmpty {
                discard()
            }
            return nil
        }
        return env.plan
    }

    /// Restores a hit, or runs `generate` exactly once for concurrent callers of
    /// the same day + fingerprint and persists a launchable result.
    public func resolve(fingerprint: String,
                        generate: @escaping @Sendable () async -> TodaySuggestedPlanPayload?) async -> TodaySuggestedPlanPayload? {
        if let hit = restore(fingerprint: fingerprint) { return hit }
        let key = dayKey() + "|" + fingerprint
        if let running = inFlight[key] { return await running.value }
        let startEpoch = epoch
        let task = Task<TodaySuggestedPlanPayload?, Never> { await generate() }
        inFlight[key] = task
        let plan = await task.value
        inFlight[key] = nil
        guard let plan, !Task.isCancelled,
              startEpoch == epoch, key == dayKey() + "|" + fingerprint else { return plan }
        save(plan, fingerprint: fingerprint)
        return plan
    }

    public func save(_ plan: TodaySuggestedPlanPayload, fingerprint: String) {
        guard !plan.exercises.isEmpty else { return }
        let env = Envelope(schemaVersion: Self.schemaVersion, dayKey: dayKey(),
                           fingerprint: fingerprint, updatedAt: now(),
                           plan: plan)
        memory = env; memoryLoaded = true
        if let fileURL, let data = try? JSONEncoder().encode(env) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Removes the entry (memory + disk) and supersedes any in-flight work.
    public func invalidate() {
        epoch += 1
        for task in inFlight.values { task.cancel() }
        inFlight = [:]
        discard()
    }

    private func discard() {
        memory = nil; memoryLoaded = true
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func loadEnvelope() -> Envelope? {
        if memoryLoaded { return memory }
        memoryLoaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        memory = env
        return env
    }
}
