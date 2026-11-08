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

/// Cheap deterministic key over the inputs that decide the Today plan, computed
/// without loading the exercise catalog. Callers pass stable value stamps only.
public enum TodaySuggestedWorkoutEarlyKey {
    public static func make(_ parts: [String]) -> String {
        var state: UInt64 = 0xcbf29ce484222325
        for part in ["early-v1"] + parts {
            var n = UInt64(part.utf8.count)
            for _ in 0..<8 { state = (state ^ UInt64(n & 0xff)) &* 0x100000001b3; n >>= 8 }
            for b in part.utf8 { state = (state ^ UInt64(b)) &* 0x100000001b3 }
        }
        return String(state, radix: 16)
    }
}

/// Launch-order seam for Today: restores the durable plan before any candidate
/// catalog work, and only on a miss loads candidates and generates.
public enum TodaySuggestionLaunch {
    public enum Result: Sendable, Equatable {
        case restored(TodaySuggestedPlanPayload)
        case generated(TodaySuggestedPlanPayload?)
    }

    public static func run(store: TodaySuggestedWorkoutCacheStore,
                           earlyKey: String,
                           loadAndGenerate: @Sendable () async -> TodaySuggestedPlanPayload?) async -> Result {
        if let hit = await store.restoreEarly(earlyKey: earlyKey) { return .restored(hit) }
        return .generated(await loadAndGenerate())
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

/// Privacy-safe diagnostic outcome of a suggested-plan cache operation.
/// Raw values are the only thing ever logged: never plan content, ids or paths.
public enum TodaySuggestionCacheOutcome: String, Sendable, Equatable {
    case displayRestored, earlyKeyMatch, noFile, corrupt, schemaRejected
    case dayRejected, earlyKeyRejected, fullKeyRejected
    case writeSaved, writeFailed, storageUnavailable, invalidated
}

public struct TodaySuggestionCacheResolution: Sendable, Equatable {
    public let payload: TodaySuggestedPlanPayload?
    public let outcome: TodaySuggestionCacheOutcome
    /// True only when the payload is backed by a valid file that survives a restart.
    public let persisted: Bool

    public init(payload: TodaySuggestedPlanPayload?, outcome: TodaySuggestionCacheOutcome,
                persisted: Bool) {
        self.payload = payload; self.outcome = outcome; self.persisted = persisted
    }
}

/// Explicit storage state; a failed Application Support lookup is `.unavailable`,
/// never a silently successful memory-only cache.
public enum TodaySuggestionCacheStorage: Sendable {
    case file(URL)
    case unavailable

    public static func `default`() -> TodaySuggestionCacheStorage {
        TodaySuggestedWorkoutCacheStore.defaultFileURL().map { .file($0) } ?? .unavailable
    }
}

/// Durable, versioned, same-local-calendar-day cache of the Today suggestion.
/// Valid only while both the local day key and the semantic fingerprint match.
/// An actor so concurrent loads for the same key coalesce onto one generation.
public actor TodaySuggestedWorkoutCacheStore {
    // v2 invalidates the legacy Today-only recommendation payloads. Persisted
    // entries now represent the shared "Suggest a workout" presentation.
    public static let schemaVersion = 2

    struct Envelope: Codable {
        var schemaVersion: Int
        var dayKey: String
        var fingerprint: String
        /// Lightweight semantic key (no catalog needed) for restore before
        /// candidate loading. Optional so older records still decode.
        var earlyKey: String?
        var updatedAt: Date
        var plan: TodaySuggestedPlanPayload
    }

    private let storage: TodaySuggestionCacheStorage
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let outcomeObserver: (@Sendable (TodaySuggestionCacheOutcome) -> Void)?
    private var memory: Envelope?
    private var memoryLoaded = false
    /// Why `memory` is nil (valid only when it is nil).
    private var missOutcome: TodaySuggestionCacheOutcome = .noFile
    private var inFlight: [String: Task<TodaySuggestedPlanPayload?, Never>] = [:]
    private var epoch = 0

    public init(storage: TodaySuggestionCacheStorage, calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() },
                outcomeObserver: (@Sendable (TodaySuggestionCacheOutcome) -> Void)? = nil) {
        self.storage = storage
        self.calendar = calendar
        self.now = now
        self.outcomeObserver = outcomeObserver
    }

    /// `fileURL == nil` means unavailable storage (in-memory for this process only).
    public init(fileURL: URL?, calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() },
                outcomeObserver: (@Sendable (TodaySuggestionCacheOutcome) -> Void)? = nil) {
        self.init(storage: fileURL.map { .file($0) } ?? .unavailable, calendar: calendar,
                  now: now, outcomeObserver: outcomeObserver)
    }

    public static func defaultFileURL() -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("TodaySuggestedWorkout.v1.json")
    }

    private var fileURL: URL? {
        if case .file(let url) = storage { return url }
        return nil
    }

    private var isDurable: Bool { fileURL != nil }

    private func note(_ outcome: TodaySuggestionCacheOutcome) {
        outcomeObserver?(outcome)
    }

    public func dayKey() -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now())
        let tz = calendar.timeZone.identifier
        return String(format: "%04d-%02d-%02d@%@", c.year ?? 0, c.month ?? 0, c.day ?? 0, tz)
    }

    /// True when a valid same-day, current-schema record exists, so Today can
    /// skip the artificial generation delay (the fingerprint check still runs).
    public func hasSameDayEntry() -> Bool {
        guard let env = loadEnvelope() else { return false }
        return env.schemaVersion == Self.schemaVersion && env.dayKey == dayKey()
            && !env.plan.exercises.isEmpty
    }

    /// Why a loaded envelope is unusable for display, or nil when it is usable.
    private func displayRejection(_ env: Envelope) -> TodaySuggestionCacheOutcome? {
        if env.schemaVersion != Self.schemaVersion || env.plan.exercises.isEmpty {
            return .schemaRejected
        }
        if env.dayKey != dayKey() { return .dayRejected }
        return nil
    }

    private func miss(_ outcome: TodaySuggestionCacheOutcome) -> TodaySuggestionCacheResolution {
        note(outcome)
        return TodaySuggestionCacheResolution(payload: nil, outcome: outcome, persisted: false)
    }

    /// Display-only restore with a diagnostic outcome and no deletion.
    public func inspectDisplayable() -> (resolution: TodaySuggestionCacheResolution, earlyKey: String?) {
        guard let env = loadEnvelope() else { return (miss(missOutcome), nil) }
        if let reason = displayRejection(env) { return (miss(reason), nil) }
        note(.displayRestored)
        return (TodaySuggestionCacheResolution(payload: env.plan, outcome: .displayRestored,
                                               persisted: isDurable), env.earlyKey)
    }

    /// Display-only restore for launch: any same-day, current-schema record,
    /// with no key judgement and no deletion. The caller reconciles the stored
    /// early key against the stable one after the first frame.
    public func peekDisplayable() -> (plan: TodaySuggestedPlanPayload, earlyKey: String?)? {
        let r = inspectDisplayable()
        guard let plan = r.resolution.payload else { return nil }
        return (plan, r.earlyKey)
    }

    /// Restores the persisted plan using only the lightweight early key, so Today
    /// can show it before the exercise catalog is loaded. A same-day record with
    /// a different early key is genuinely stale and is discarded; a record that
    /// predates early keys is left for the full-fingerprint path.
    public func restoreEarlyResolution(earlyKey: String) -> TodaySuggestionCacheResolution {
        guard let env = loadEnvelope() else { return miss(missOutcome) }
        if let reason = displayRejection(env) { discard(); return miss(reason) }
        guard let stored = env.earlyKey else { return miss(.earlyKeyRejected) }
        guard stored == earlyKey else { discard(); return miss(.earlyKeyRejected) }
        note(.earlyKeyMatch)
        return TodaySuggestionCacheResolution(payload: env.plan, outcome: .earlyKeyMatch,
                                              persisted: isDurable)
    }

    public func restoreEarly(earlyKey: String) -> TodaySuggestedPlanPayload? {
        restoreEarlyResolution(earlyKey: earlyKey).payload
    }

    /// Returns the cached plan for this day + fingerprint, deleting any stale,
    /// corrupt or wrong-version record. Does not notify the observer.
    private func restoreQuiet(fingerprint: String) -> (TodaySuggestedPlanPayload?, TodaySuggestionCacheOutcome) {
        guard let env = loadEnvelope() else { return (nil, missOutcome) }
        if let reason = displayRejection(env) { discard(); return (nil, reason) }
        guard env.fingerprint == fingerprint else { discard(); return (nil, .fullKeyRejected) }
        return (env.plan, .displayRestored)
    }

    public func restore(fingerprint: String) -> TodaySuggestedPlanPayload? {
        let r = restoreQuiet(fingerprint: fingerprint)
        note(r.1)
        return r.0
    }

    public func resolve(fingerprint: String,
                        earlyKey: String? = nil,
                        generate: @escaping @Sendable () async -> TodaySuggestedPlanPayload?) async -> TodaySuggestedPlanPayload? {
        await resolveWithOutcome(fingerprint: fingerprint, earlyKey: earlyKey, generate: generate).payload
    }

    /// Restores a hit, or runs `generate` exactly once for concurrent callers of
    /// the same day + fingerprint and persists a launchable result. The outcome
    /// says whether the returned plan will survive a restart.
    public func resolveWithOutcome(fingerprint: String,
                                   earlyKey: String? = nil,
                                   generate: @escaping @Sendable () async -> TodaySuggestedPlanPayload?) async -> TodaySuggestionCacheResolution {
        let (hit, missReason) = restoreQuiet(fingerprint: fingerprint)
        if let hit {
            if let earlyKey, memory?.earlyKey != earlyKey {
                // A failed upgrade keeps the previous valid record.
                if case .failed = save(hit, fingerprint: fingerprint, earlyKey: earlyKey) {
                    note(isDurable ? .writeFailed : .storageUnavailable)
                    return TodaySuggestionCacheResolution(payload: hit, outcome: .displayRestored,
                                                          persisted: isDurable)
                }
            }
            note(.displayRestored)
            return TodaySuggestionCacheResolution(payload: hit, outcome: .displayRestored,
                                                  persisted: isDurable)
        }
        let key = dayKey() + "|" + fingerprint
        if let running = inFlight[key] {
            // Follower: the leader owns persistence; never claim it here.
            let plan = await running.value
            note(missReason)
            return TodaySuggestionCacheResolution(payload: plan, outcome: missReason, persisted: false)
        }
        let startEpoch = epoch
        let task = Task<TodaySuggestedPlanPayload?, Never> { await generate() }
        inFlight[key] = task
        let plan = await task.value
        inFlight[key] = nil
        guard let plan else {
            note(missReason)
            return TodaySuggestionCacheResolution(payload: nil, outcome: missReason, persisted: false)
        }
        guard !Task.isCancelled, startEpoch == epoch,
              key == dayKey() + "|" + fingerprint else {
            note(.invalidated)
            return TodaySuggestionCacheResolution(payload: plan, outcome: .invalidated, persisted: false)
        }
        let outcome: TodaySuggestionCacheOutcome
        switch save(plan, fingerprint: fingerprint, earlyKey: earlyKey) {
        case .saved: outcome = isDurable ? .writeSaved : .storageUnavailable
        case .failed: outcome = isDurable ? .writeFailed : .storageUnavailable
        }
        note(outcome)
        return TodaySuggestionCacheResolution(payload: plan, outcome: outcome,
                                              persisted: outcome == .writeSaved)
    }

    /// Persists the plan. A failed replacement leaves the previous valid file and
    /// in-memory record intact. Unavailable storage keeps the plan in memory for
    /// this process only and reports failure.
    @discardableResult
    public func save(_ plan: TodaySuggestedPlanPayload, fingerprint: String,
                     earlyKey: String? = nil) -> TodayCacheWriteResult {
        guard !plan.exercises.isEmpty else { return .failed("emptyPlan") }
        let env = Envelope(schemaVersion: Self.schemaVersion, dayKey: dayKey(),
                           fingerprint: fingerprint, earlyKey: earlyKey, updatedAt: now(),
                           plan: plan)
        guard let url = fileURL else {
            memory = env; memoryLoaded = true
            return .failed("storageUnavailable")
        }
        let result = TodayCacheFile.write(env, to: url)
        guard result.isSaved else { return result }
        memory = env; memoryLoaded = true
        return result
    }

    /// Removes the entry (memory + disk) and supersedes any in-flight work.
    public func invalidate() {
        epoch += 1
        for task in inFlight.values { task.cancel() }
        inFlight = [:]
        discard()
        note(.invalidated)
    }

    private func discard() {
        memory = nil; memoryLoaded = true
        missOutcome = isDurable ? .noFile : .storageUnavailable
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func loadEnvelope() -> Envelope? {
        if memoryLoaded { return memory }
        memoryLoaded = true
        guard let fileURL else { missOutcome = .storageUnavailable; return nil }
        guard let data = try? Data(contentsOf: fileURL) else { missOutcome = .noFile; return nil }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else {
            // Only the corrupt file itself is cleaned up.
            try? FileManager.default.removeItem(at: fileURL)
            missOutcome = .corrupt
            return nil
        }
        memory = env
        return env
    }
}
