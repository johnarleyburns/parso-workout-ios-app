import Foundation
import CadenceCore

/// Deterministic fingerprint of the inputs that drive the Today recommendation.
/// Built only from semantic values (never view identity, refresh tokens or a
/// random `@State` UUID), so it is stable across view recreation and launches.
/// Passive (HealthKit) readiness is kept as a separate stamp because it arrives
/// asynchronously after launch.
public enum TodayRecommendationFingerprint {
    public struct Result: Equatable, Sendable {
        public var fingerprint: String
        public var passiveStamp: String
    }

    /// Order-independent stamp for a collection of dated records.
    public static func historyStamp(count: Int, latestChange: Date?, ids: [UUID]) -> String {
        var h = Hash64()
        h.add(count)
        h.add(latestChange.map { String($0.timeIntervalSinceReferenceDate.bitPattern) } ?? "-")
        for id in ids.map(\.uuidString).sorted() { h.add(id) }
        return h.hex
    }

    public static func passiveStamp(_ samples: [PassiveReadinessSample],
                                    calendar: Calendar = .current) -> String {
        var h = Hash64()
        for s in samples.sorted(by: { $0.date < $1.date }) {
            h.add(String(Int(calendar.startOfDay(for: s.date).timeIntervalSinceReferenceDate)))
            h.add(s.hrvSDNN.map { String(Int($0.rounded())) } ?? "-")
            h.add(s.restingHR.map { String(Int($0.rounded())) } ?? "-")
            h.add(s.sleepHours.map { String(Int(($0 * 4).rounded())) } ?? "-")
        }
        return h.hex
    }

    public static func make(dayKey: String,
                            sessionsStamp: String,
                            cardioStamp: String,
                            assessmentsStamp: String,
                            readinessStamp: String,
                            painToday: Bool,
                            goal: TrainingGoal,
                            experience: ExperienceLevel,
                            formula: OneRepMaxFormula,
                            schedule: CoachSchedulePreferences,
                            profile: CoachPreferenceProfile,
                            userAge: Int?,
                            cardioMaximumHROverride: Double?,
                            overrideWeekKey: String?,
                            extras: [String] = [],
                            passiveSamples: [PassiveReadinessSample]) -> Result {
        var h = Hash64()
        h.add("v1"); h.add(dayKey)
        h.add(sessionsStamp); h.add(cardioStamp); h.add(assessmentsStamp)
        h.add(readinessStamp); h.add(painToday)
        h.add(goal.rawValue); h.add(experience.rawValue); h.add(formula.rawValue)
        h.add(canonicalJSON(schedule)); h.add(canonicalJSON(profile))
        h.add(userAge.map(String.init) ?? "-")
        h.add(cardioMaximumHROverride.map { String($0.bitPattern) } ?? "-")
        h.add(overrideWeekKey ?? "-")
        for e in extras.sorted() { h.add("x:" + e) }
        return Result(fingerprint: h.hex, passiveStamp: passiveStamp(passiveSamples))
    }

    private static func canonicalJSON<T: Encodable>(_ value: T) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return (try? enc.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// FNV-1a 64 over length-prefixed fields (stable across launches).
    struct Hash64 {
        var state: UInt64 = 0xcbf29ce484222325
        mutating func add(_ s: String) {
            var n = UInt64(s.utf8.count)
            for _ in 0..<8 { mix(UInt8(n & 0xff)); n >>= 8 }
            for b in s.utf8 { mix(b) }
        }
        mutating func add(_ i: Int) { add(String(i)) }
        mutating func add(_ b: Bool) { add(b ? "1" : "0") }
        private mutating func mix(_ b: UInt8) { state = (state ^ UInt64(b)) &* 0x100000001b3 }
        var hex: String { String(state, radix: 16) }
    }
}

/// Codable presentation of the Today recommendation hero (no domain types).
public struct TodayRecommendationPayload: Codable, Equatable, Sendable {
    public struct LineDTO: Codable, Equatable, Sendable {
        public var name: String
        public var detail: String
    }
    public var isRest: Bool
    public var primaryIsStrength: Bool
    public var title: String
    public var estimatedMinutes: Int?
    public var exercises: [LineDTO]
    public var reason: String?
    public var citationIDs: [String]

    public init(hero: TodayHero, primaryIsStrength: Bool) {
        isRest = hero.kind == .restDay
        self.primaryIsStrength = primaryIsStrength
        title = hero.title
        estimatedMinutes = hero.estimatedMinutes
        exercises = hero.exercises.map { LineDTO(name: $0.name, detail: $0.detail) }
        reason = hero.reason
        citationIDs = hero.citationIDs
    }

    public func makeHero() -> TodayHero {
        TodayHero(kind: isRest ? .restDay : .suggested, title: title,
                  estimatedMinutes: estimatedMinutes,
                  exercises: exercises.map { TodayHero.Line(name: $0.name, detail: $0.detail) },
                  reason: reason, citationIDs: citationIDs)
    }
}

/// Why a durable Today record was or was not used. Carries no workout content,
/// so it is safe to log for device-QA diagnosis.
public enum TodayCacheOutcome: String, Equatable, Sendable {
    case noFile, corrupt, schemaRejected, dayRejected
    case provisionalRestore, stableMatch, stableInvalidation
    case writeFailed, invalidated
}

/// Semantic trigger for a deliberate cache invalidation (no workout content).
public enum TodayCacheInvalidationReason: String, Equatable, Sendable {
    case historyChanged, settingsChanged, readinessChanged
}

/// Result of a durable cache write. A failure leaves any previous valid file
/// and in-memory record untouched, so a generated value is never mistaken for
/// a persisted one.
public enum TodayCacheWriteResult: Equatable, Sendable {
    case saved
    case failed(String)

    public var isSaved: Bool { self == .saved }
}

enum TodayCacheFile {
    /// Atomic write; `nil` URL is memory-only and always succeeds.
    static func write<T: Encodable>(_ value: T, to url: URL?) -> TodayCacheWriteResult {
        guard let url else { return .saved }
        do {
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
            return .saved
        } catch {
            return .failed(String(describing: type(of: error)))
        }
    }
}

/// A display-eligible (same day, supported schema, decodable) durable record
/// whose freshness has not yet been checked against stable inputs.
public struct TodayProvisionalRecord: Equatable, Sendable {
    public var payload: TodayRecommendationPayload
    public var fingerprint: String
    public var passiveStamp: String
}

/// Durable, versioned, same-local-day cache of the Today recommendation.
/// Separate file from the suggested-plan cache so neither (nor This Week) can
/// evict the other; `invalidate()` is called alongside the plan store's.
public actor TodayRecommendationCacheStore {
    public static let schemaVersion = 1

    struct Envelope: Codable {
        var schemaVersion: Int
        var dayKey: String
        var fingerprint: String
        var passiveStamp: String
        var updatedAt: Date
        var payload: TodayRecommendationPayload
    }

    private let fileURL: URL?
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var memory: Envelope?
    private var memoryLoaded = false
    private var loadFailure: TodayCacheOutcome?

    public init(fileURL: URL?, calendar: Calendar = .current,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.calendar = calendar
        self.now = now
    }

    public static func defaultFileURL() -> URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("TodayRecommendation.v1.json")
    }

    public func dayKey() -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: now())
        return String(format: "%04d-%02d-%02d@%@", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      calendar.timeZone.identifier)
    }

    /// `passiveStamp == nil` means HealthKit readiness has not loaded yet: the
    /// entry is accepted and the caller reconciles via `restoredPassiveStamp`.
    public func restore(fingerprint: String, passiveStamp: String? = nil)
        -> (payload: TodayRecommendationPayload, passiveStamp: String)? {
        guard let env = loadEnvelope() else { return nil }
        guard env.schemaVersion == Self.schemaVersion, env.dayKey == dayKey(),
              env.fingerprint == fingerprint,
              passiveStamp == nil || env.passiveStamp == passiveStamp else {
            discard()
            return nil
        }
        return (env.payload, env.passiveStamp)
    }

    /// Display eligibility only: never judges the fingerprint, and never deletes
    /// a record because startup inputs are still settling. Only unusable records
    /// (corrupt, unsupported schema, wrong local day) are rejected and cleaned up.
    public func peekDisplayable() -> (record: TodayProvisionalRecord?, outcome: TodayCacheOutcome) {
        guard let env = loadEnvelope() else { return (nil, loadFailure ?? .noFile) }
        guard env.schemaVersion == Self.schemaVersion else { discard(); return (nil, .schemaRejected) }
        guard env.dayKey == dayKey() else { discard(); return (nil, .dayRejected) }
        return (TodayProvisionalRecord(payload: env.payload, fingerprint: env.fingerprint,
                                       passiveStamp: env.passiveStamp), .provisionalRestore)
    }

    @discardableResult
    public func save(_ payload: TodayRecommendationPayload, fingerprint: String,
                     passiveStamp: String) -> TodayCacheWriteResult {
        let env = Envelope(schemaVersion: Self.schemaVersion, dayKey: dayKey(),
                           fingerprint: fingerprint, passiveStamp: passiveStamp,
                           updatedAt: now(), payload: payload)
        let result = TodayCacheFile.write(env, to: fileURL)
        guard result.isSaved else { return result }
        memory = env; memoryLoaded = true; loadFailure = nil
        return result
    }

    public func invalidate() { discard() }

    private func discard() {
        memory = nil; memoryLoaded = true; loadFailure = nil
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func loadEnvelope() -> Envelope? {
        if memoryLoaded { return memory }
        memoryLoaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data) else {
            try? FileManager.default.removeItem(at: fileURL)
            loadFailure = .corrupt
            return nil
        }
        memory = env
        return env
    }
}
