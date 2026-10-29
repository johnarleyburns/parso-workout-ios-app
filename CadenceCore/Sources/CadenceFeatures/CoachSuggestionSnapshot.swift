import Foundation
import CadenceCore

/// Value-only capture of everything the shared strength-suggestion generator
/// needs, plus the values used only to materialize the editable plan.
public struct CoachSuggestionRequest: Codable, Equatable, Sendable {
    public let input: SuggestedWorkoutInput
    public let unit: MeasurementUnitPreference
    public let warmupMinutes: Int
    public let cooldownMinutes: Int
    public let failureMessage: String?

    public init(input: SuggestedWorkoutInput, unit: MeasurementUnitPreference,
                warmupMinutes: Int, cooldownMinutes: Int, failureMessage: String? = nil) {
        self.input = input
        self.unit = unit
        self.warmupMinutes = warmupMinutes
        self.cooldownMinutes = cooldownMinutes
        self.failureMessage = failureMessage
    }
}

/// Versioned, portable input for `CoachSuggestionService`. The phone builds it
/// from persistence-backed values; any host executes it identically.
public struct CoachSuggestionSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let dayKey: String
    public let fingerprint: String
    public let request: CoachSuggestionRequest

    public init(schemaVersion: Int = Self.currentSchemaVersion,
                generatedAt: Date,
                dayKey: String,
                fingerprint: String,
                request: CoachSuggestionRequest) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.dayKey = dayKey
        self.fingerprint = fingerprint
        self.request = request
    }

    /// Start-of-day identity in the supplied calendar, e.g. `2026-10-29`.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public enum DecodeFailure: Error, Equatable, Sendable {
        case unsupportedSchema(Int)
        case corrupt
    }

    /// Fails closed: unsupported versions and malformed data yield a typed error.
    public static func decode(_ data: Data) -> Result<CoachSuggestionSnapshot, DecodeFailure> {
        struct Header: Decodable { let schemaVersion: Int }
        let decoder = PropertyListDecoder()
        let isJSON = data.first == UInt8(ascii: "{")
        func run<T: Decodable>(_ type: T.Type) throws -> T {
            isJSON ? try JSONDecoder().decode(type, from: data) : try decoder.decode(type, from: data)
        }
        guard let header = try? run(Header.self) else { return .failure(.corrupt) }
        guard header.schemaVersion == currentSchemaVersion else {
            return .failure(.unsupportedSchema(header.schemaVersion))
        }
        guard let snapshot = try? run(CoachSuggestionSnapshot.self) else { return .failure(.corrupt) }
        return .success(snapshot)
    }
}

public enum CoachSuggestionService {
    /// The single strength-suggestion entry point shared by phone and Watch.
    public static func generate(from snapshot: CoachSuggestionSnapshot) -> SuggestedWorkoutOption? {
        guard snapshot.schemaVersion == CoachSuggestionSnapshot.currentSchemaVersion,
              snapshot.request.failureMessage == nil else { return nil }
        let option = SuggestedWorkoutGenerator.generatePersonalized(input: snapshot.request.input)
        return option.isLaunchable ? option : nil
    }
}

public enum CoachSuggestionSnapshotBuilder {
    public static func make(request: CoachSuggestionRequest,
                            generatedAt: Date,
                            calendar: Calendar = .current) -> CoachSuggestionSnapshot {
        CoachSuggestionSnapshot(
            generatedAt: generatedAt,
            dayKey: CoachSuggestionSnapshot.dayKey(for: generatedAt, calendar: calendar),
            fingerprint: CoachSuggestionFingerprint.make(request: request),
            request: request)
    }
}

/// Deterministic semantic fingerprint (FNV-1a 64, length-prefixed fields,
/// order-independent over sets). Excludes transport metadata.
public enum CoachSuggestionFingerprint {
    public static func make(request: CoachSuggestionRequest) -> String {
        var h = Hasher64()
        h.add("coach-v1")
        h.add(request.unit.rawValue); h.add(request.warmupMinutes); h.add(request.cooldownMinutes)
        h.add(request.failureMessage ?? "-")
        let input = request.input
        for (k, v) in input.completedSetsByMuscle.sorted(by: { $0.key < $1.key }) { h.add(k); h.add(v) }
        for c in input.candidates.sorted(by: { $0.id < $1.id }) {
            h.add(c.id); h.add(c.name); h.add(c.mechanics.rawValue)
            for m in c.primaryMuscles { h.add("p:" + m) }
            for m in c.secondaryMuscles { h.add("s:" + m) }
            h.add(c.equipment?.rawValue ?? "-")
            h.add(c.volumeEligible); h.add(c.isPersonalized)
            for t in c.trainingTypes { h.add("t:" + t.rawValue) }
            for t in c.modalities { h.add("m:" + t.rawValue) }
            for t in c.sportContexts { h.add("c:" + t.rawValue) }
        }
        for id in input.recentlyCompletedCandidateIDs.sorted() { h.add("r:" + id) }
        h.add(input.historyData ?? Data())
        h.add(input.historyWorkoutCount); h.add(input.historyWorkingSetCount)
        for g in input.trackedGroups.map(\.rawValue).sorted() { h.add("g:" + g) }
        h.add(input.preferredSetsPerExercise)
        h.add(input.mostRecentExerciseWorkingSets ?? -1)
        h.add(input.trainingGoal.rawValue)
        h.add(input.preferredStyle.rawValue)
        if let ctx = input.engineContext {
            h.add("ctx")
            h.add(ctx.experience.rawValue); h.add(ctx.environment)
            h.add(ctx.asOf.timeIntervalSinceReferenceDate)
            for e in ctx.availableEquipment.map(\.rawValue).sorted() { h.add("e:" + e) }
            let s = ctx.schedule
            h.add(String(describing: s.restPreference)); h.add(s.allowsTwoADays)
            h.add(String(describing: s.sameDayCardioTiming))
            h.add(s.dailyStepTarget); h.add(s.desiredSetsPerExercise)
            for g in s.trackedMuscleGroups.map(\.rawValue).sorted() { h.add("sg:" + g) }
        } else {
            h.add("noctx")
        }
        return h.hex
    }

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
