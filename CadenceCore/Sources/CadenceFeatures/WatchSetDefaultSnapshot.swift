import Foundation
import CadenceCore

/// Property-list-safe, canonical-kg history inputs for `PerformerSetPlanner`.
/// Contract only: nothing builds, sends, or consumes it yet.
public struct WatchSetDefaultSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let ownerID = "owner"
    public static let maxLadders = 12
    public static let maxSamples = 48
    public static let maxGeneralLadders = 21

    public var version: Int
    public var generatedAt: Date
    public var performers: [Performer]

    public struct Performer: Codable, Equatable, Sendable, Identifiable {
        /// "owner" or the phone `Person.id.uuidString`.
        public var id: String
        public var displayName: String
        public var exercises: [Exercise]
        public var generalRepLadders: [[Int]]

        public init(id: String, displayName: String, exercises: [Exercise],
                    generalRepLadders: [[Int]]) {
            self.id = id
            self.displayName = displayName
            self.exercises = exercises
            self.generalRepLadders = WatchSetDefaultSnapshot.boundedLadders(
                generalRepLadders, limit: WatchSetDefaultSnapshot.maxGeneralLadders)
        }
    }

    public struct Exercise: Codable, Equatable, Sendable, Identifiable {
        /// Canonical normalized key (`WatchSetDefaultSnapshot.canonicalKey`), never a Watch UUID.
        public var id: String
        public var displayName: String
        /// Oldest → newest.
        public var repLadders: [[Int]]
        /// Oldest → newest, working sets only.
        public var samples: [Sample]
        public var firstWorkingWeightKg: Double?

        public init(id: String, displayName: String, repLadders: [[Int]],
                    samples: [Sample], firstWorkingWeightKg: Double?) {
            self.id = WatchSetDefaultSnapshot.canonicalKey(id)
            self.displayName = displayName
            self.repLadders = WatchSetDefaultSnapshot.boundedLadders(
                repLadders, limit: WatchSetDefaultSnapshot.maxLadders)
            self.samples = Array(samples.filter(\.isValid).suffix(WatchSetDefaultSnapshot.maxSamples))
            if let w = firstWorkingWeightKg, w.isFinite, w > 0 {
                self.firstWorkingWeightKg = w
            } else {
                self.firstWorkingWeightKg = nil
            }
        }
    }

    public struct Sample: Codable, Equatable, Sendable {
        /// Canonical kilograms.
        public var weightKg: Double
        public var reps: Int

        public init(weightKg: Double, reps: Int) {
            self.weightKg = weightKg
            self.reps = reps
        }

        fileprivate var isValid: Bool { weightKg.isFinite && weightKg > 0 && reps > 0 }
    }

    public init(version: Int = WatchSetDefaultSnapshot.currentVersion,
                generatedAt: Date, performers: [Performer]) {
        self.version = version
        self.generatedAt = generatedAt
        var seen = Set<String>()
        self.performers = performers.compactMap { performer in
            guard Self.isValidPerformerID(performer.id), seen.insert(performer.id).inserted else {
                return nil
            }
            var exerciseSeen = Set<String>()
            let exercises = performer.exercises.compactMap { e -> Exercise? in
                let rebuilt = Exercise(id: e.id, displayName: e.displayName, repLadders: e.repLadders,
                                       samples: e.samples, firstWorkingWeightKg: e.firstWorkingWeightKg)
                guard !rebuilt.id.isEmpty, exerciseSeen.insert(rebuilt.id).inserted else { return nil }
                return rebuilt
            }
            return Performer(id: performer.id, displayName: performer.displayName,
                             exercises: exercises, generalRepLadders: performer.generalRepLadders)
        }
    }

    /// Single case/whitespace normalization shared by phone and Watch.
    public static func canonicalKey(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    fileprivate static func isValidPerformerID(_ id: String) -> Bool {
        id == ownerID || UUID(uuidString: id) != nil
    }

    fileprivate static func boundedLadders(_ ladders: [[Int]], limit: Int) -> [[Int]] {
        Array(ladders.map { $0.filter { $0 > 0 } }.filter { !$0.isEmpty }.suffix(limit))
    }

    public func history(exerciseKey: String, performerID: String) -> PerformerSetPlanner.History {
        guard let performer = performers.first(where: { $0.id == performerID }) else { return .empty }
        guard let exercise = performer.exercises.first(where: { $0.id == Self.canonicalKey(exerciseKey) })
        else {
            // No row for this movement: keep only the performer's own general rep habit.
            return PerformerSetPlanner.History(generalRepLadders: performer.generalRepLadders)
        }
        return PerformerSetPlanner.History(
            repLadders: exercise.repLadders,
            generalRepLadders: performer.generalRepLadders,
            firstWorkingWeightKg: exercise.firstWorkingWeightKg,
            weightSamples: exercise.samples.map {
                SetSample(weight: $0.weightKg, reps: $0.reps, date: generatedAt)
            })
    }

    /// WatchConnectivity accepts only property-list values; JSON gives one stable form.
    public var propertyList: [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let data = try? encoder.encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return [:] }
        return dictionary
    }

    /// Fails (nil) for malformed payloads or any version other than `currentVersion`.
    public init?(propertyList: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(propertyList),
              let data = try? JSONSerialization.data(withJSONObject: propertyList) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let raw = try? decoder.decode(Self.self, from: data),
              raw.version == Self.currentVersion else { return nil }
        self.init(version: raw.version, generatedAt: raw.generatedAt, performers: raw.performers)
    }
}
