import Foundation
import CadenceCore

/// Versioned, bounded, Foundation-only rich summary of one completed workout, shown read-only in
/// Watch My Workouts. It carries display data only: no routes, notes, calories, source/bundle IDs,
/// device IDs or HealthKit metadata. The HR series never exceeds `HRSampling.defaultMaxPoints`.
public struct WatchWorkoutHistorySummary: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// Conservative cap on an encoded payload accepted over the wire.
    public static let maxPayloadBytes = 16_384

    public enum Kind: String, Codable, Sendable { case strength, cardio }

    /// Which optional sections have recorded data, so the UI omits the rest instead of faking them.
    public enum Availability: String, Codable, Sendable {
        /// Heart-rate series and cardio credit are both recorded.
        case full
        /// Heart rate is recorded but no cardio credit exists.
        case heartRateOnly
        /// No heart-rate data at all.
        case basic
    }

    public struct SetLine: Codable, Equatable, Sendable {
        public var weightKg: Double
        public var reps: Int
        public var rpe: Double?
        public var isWarmup: Bool
        /// Nil for the device owner.
        public var performerID: UUID?
        public init(weightKg: Double, reps: Int, rpe: Double? = nil, isWarmup: Bool = false,
                    performerID: UUID? = nil) {
            self.weightKg = weightKg; self.reps = reps; self.rpe = rpe
            self.isWarmup = isWarmup; self.performerID = performerID
        }
    }

    public struct ExerciseLine: Codable, Equatable, Sendable {
        public var name: String
        public var sets: [SetLine]
        public init(name: String, sets: [SetLine]) { self.name = name; self.sets = sets }
    }

    public var version: Int
    public var id: UUID
    public var kind: Kind
    public var title: String
    public var start: Date
    public var end: Date?
    public var completedAt: Date
    public var hrSamples: [HRSamplePoint]
    public var averageBPM: Double?
    public var maximumBPM: Double?
    public var minuteSummary: CardioMinuteSummary?
    public var cardioType: String?
    public var distanceMeters: Double?
    public var laps: Int?
    public var workingSetCount: Int?
    public var totalVolumeKg: Double?
    public var exercises: [ExerciseLine]

    public var availability: Availability {
        if hrSamples.isEmpty { return .basic }
        return minuteSummary == nil ? .heartRateOnly : .full
    }

    public var durationSeconds: TimeInterval {
        end.map { max(0, $0.timeIntervalSince(start)) } ?? 0
    }

    public init(id: UUID, kind: Kind, title: String, start: Date, end: Date?, completedAt: Date? = nil,
                hrSamples: [HRSamplePoint] = [], averageBPM: Double? = nil, maximumBPM: Double? = nil,
                minuteSummary: CardioMinuteSummary? = nil, cardioType: String? = nil,
                distanceMeters: Double? = nil, laps: Int? = nil, workingSetCount: Int? = nil,
                totalVolumeKg: Double? = nil, exercises: [ExerciseLine] = [],
                version: Int = currentVersion) {
        self.version = version; self.id = id; self.kind = kind
        self.title = String(title.prefix(WatchSync.CardioHistoryItem.maxTextLength))
        self.start = start; self.end = end; self.completedAt = completedAt ?? end ?? start
        self.hrSamples = Self.normalized(hrSamples)
        self.averageBPM = Self.validBPM(averageBPM); self.maximumBPM = Self.validBPM(maximumBPM)
        self.minuteSummary = self.hrSamples.isEmpty ? nil : minuteSummary
        self.cardioType = cardioType
        self.distanceMeters = distanceMeters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.laps = laps.flatMap { $0 >= 0 ? $0 : nil }
        self.workingSetCount = workingSetCount.flatMap { $0 >= 0 ? $0 : nil }
        self.totalVolumeKg = totalVolumeKg.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.exercises = exercises
    }

    private static func validBPM(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    /// Drops nonfinite / negative-time / nonpositive-BPM points, sorts chronologically and caps the
    /// series at `HRSampling.defaultMaxPoints` (first and last retained).
    public static func normalized(_ samples: [HRSamplePoint]) -> [HRSamplePoint] {
        HRSampling.downsample(
            samples.filter { $0.t.isFinite && $0.t >= 0 && $0.bpm.isFinite && $0.bpm > 0 },
            maxPoints: HRSampling.defaultMaxPoints)
    }

    // MARK: Codable (re-normalizes on decode)

    private enum CodingKeys: String, CodingKey {
        case version, id, kind, title, start, end, completedAt, hrSamples, averageBPM, maximumBPM
        case minuteSummary, cardioType, distanceMeters, laps, workingSetCount, totalVolumeKg, exercises
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .version)
        guard version >= 1, version <= Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: c, debugDescription: "unsupported version")
        }
        self.init(
            id: try c.decode(UUID.self, forKey: .id), kind: try c.decode(Kind.self, forKey: .kind),
            title: try c.decode(String.self, forKey: .title), start: try c.decode(Date.self, forKey: .start),
            end: try c.decodeIfPresent(Date.self, forKey: .end),
            completedAt: try c.decodeIfPresent(Date.self, forKey: .completedAt),
            hrSamples: try c.decodeIfPresent([HRSamplePoint].self, forKey: .hrSamples) ?? [],
            averageBPM: try c.decodeIfPresent(Double.self, forKey: .averageBPM),
            maximumBPM: try c.decodeIfPresent(Double.self, forKey: .maximumBPM),
            minuteSummary: try c.decodeIfPresent(CardioMinuteSummary.self, forKey: .minuteSummary),
            cardioType: try c.decodeIfPresent(String.self, forKey: .cardioType),
            distanceMeters: try c.decodeIfPresent(Double.self, forKey: .distanceMeters),
            laps: try c.decodeIfPresent(Int.self, forKey: .laps),
            workingSetCount: try c.decodeIfPresent(Int.self, forKey: .workingSetCount),
            totalVolumeKg: try c.decodeIfPresent(Double.self, forKey: .totalVolumeKg),
            exercises: try c.decodeIfPresent([ExerciseLine].self, forKey: .exercises) ?? [],
            version: version)
    }

    // MARK: Wire encoding

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// Nil for oversize, malformed or unsupported-version data.
    public static func decode(_ data: Data) -> WatchWorkoutHistorySummary? {
        guard data.count <= maxPayloadBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Self.self, from: data)
    }
}

// MARK: - Builders

extension WatchWorkoutHistorySummary {
    /// Stored summary wins; otherwise recompute under the shared domain rules when inputs exist.
    private static func credit(stored: CardioMinuteSummary?, samples: [HRSamplePoint],
                               duration: TimeInterval, profile: CardioIntensityProfile?) -> CardioMinuteSummary? {
        if let stored { return stored }
        guard let profile else { return nil }
        return WatchStrengthHRCoverage.summary(samples: samples, duration: duration, profile: profile)
    }

    /// A completed strength `WorkoutSession`.
    public static func make(session: WorkoutSession, profile: CardioIntensityProfile? = nil) -> WatchWorkoutHistorySummary {
        let points = normalized(session.hrSamplePoints)
        var order: [String] = []
        var grouped: [String: ExerciseLine] = [:]
        for set in session.orderedSets where set.reps > 0 {
            let name = set.exerciseNameSnapshot ?? set.exercise?.name ?? ""
            let key = set.exerciseID?.uuidString ?? name
            if grouped[key] == nil { order.append(key); grouped[key] = ExerciseLine(name: name, sets: []) }
            grouped[key]?.sets.append(SetLine(
                weightKg: set.weight, reps: set.reps, rpe: set.rpe, isWarmup: set.isWarmup,
                performerID: set.performerID ?? (set.isOwnerSet ? nil : set.performedBy?.id)))
        }
        let duration = session.duration
        let end = session.endedAt ?? session.date.addingTimeInterval(duration)
        return WatchWorkoutHistorySummary(
            id: session.id, kind: .strength, title: session.title, start: session.date, end: end,
            hrSamples: points,
            averageBPM: points.isEmpty ? nil : points.map(\.bpm).reduce(0, +) / Double(points.count),
            maximumBPM: points.map(\.bpm).max(),
            minuteSummary: credit(stored: session.intensitySummary, samples: points, duration: duration, profile: profile),
            workingSetCount: session.completedOwnerWorkingSetCount, totalVolumeKg: session.totalVolume,
            exercises: order.compactMap { grouped[$0] })
    }

    /// A completed phone-side `CardioWorkout`. Excludes route, notes, calories and source identifiers.
    public static func make(cardio row: CardioWorkout, profile: CardioIntensityProfile? = nil) -> WatchWorkoutHistorySummary {
        let points = normalized((row.hrSamples ?? []).map { HRSamplePoint(t: $0.t, bpm: $0.bpm) })
        return WatchWorkoutHistorySummary(
            id: row.id, kind: .cardio, title: row.displayTitle, start: row.start, end: row.end,
            hrSamples: points, averageBPM: row.avgHeartRate, maximumBPM: row.maxHeartRate,
            minuteSummary: credit(stored: row.intensitySummary, samples: points, duration: row.duration, profile: profile),
            cardioType: row.type, distanceMeters: row.distance, laps: row.laps)
    }

    /// A Watch-recorded cardio completion still waiting for the phone mirror.
    public static func make(completion: WatchCardioCompletion, profile: CardioIntensityProfile? = nil) -> WatchWorkoutHistorySummary {
        let points = normalized(completion.hrSamples)
        let duration = max(0, completion.end.timeIntervalSince(completion.start))
        return WatchWorkoutHistorySummary(
            id: completion.id, kind: .cardio, title: completion.title ?? completion.type.displayName,
            start: completion.start, end: completion.end, hrSamples: points,
            averageBPM: completion.avgHeartRate, maximumBPM: completion.maxHeartRate,
            minuteSummary: credit(stored: nil, samples: points, duration: duration, profile: profile),
            cardioType: completion.type.rawValue, distanceMeters: completion.distanceMeters,
            laps: completion.swimmingLapCount)
    }
}
