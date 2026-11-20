import CadenceCore
import CadenceFeatures
import Foundation

/// The phone-built, Watch-local source of truth for personalized suggestions.
///
/// The phone remains the only CloudKit writer. It builds this value from its
/// full training log, prunes strength/cardio history to the 12-week mesocycle
/// window, and transfers it when the content revision changes. The Watch stores
/// the latest envelope and generates strength/cardio suggestions locally from
/// it, with no Coach-suggestion snapshot involved.
public struct WatchMesocycleMirror: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    /// 12 weeks, matching `TrainingFacts.historyWindow`.
    public static let historyWindowDays = 84
    /// Keep the mirrored file bounded even if a corrupt store reports huge history.
    public static let maxStrengthSessions = 400
    public static let maxSetsPerSession = 60
    public static let maxCardioSessions = 400
    public static let maxCandidates = 6_000

    public struct StrengthSession: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var date: Date
        public var endedAt: Date?
        public var sets: [StrengthSet]

        public init(id: UUID, date: Date, endedAt: Date?, sets: [StrengthSet]) {
            self.id = id
            self.date = date
            self.endedAt = endedAt
            self.sets = sets
        }

        public var completionDate: Date { endedAt ?? date }
    }

    public struct StrengthSet: Codable, Equatable, Sendable {
        public var exerciseID: String
        public var exerciseName: String
        public var reps: Int
        public var weightKg: Double
        public var isWarmup: Bool

        public init(exerciseID: String, exerciseName: String, reps: Int,
                    weightKg: Double, isWarmup: Bool = false) {
            self.exerciseID = exerciseID
            self.exerciseName = exerciseName
            self.reps = max(0, reps)
            self.weightKg = max(0, weightKg)
            self.isWarmup = isWarmup
        }
    }

    /// Metadata used only to credit weekly volume from mirrored sets. Candidate
    /// metadata is carried separately in `candidates`.
    public struct Exercise: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var primaryMuscles: [String]
        public var secondaryMuscles: [String]
        /// DB++ role arrays when present. They take precedence over
        /// primary/secondary exactly like `Exercise.volumeCredits`.
        public var directMuscles: [String]
        public var indirectMuscles: [String]
        public var volumeEligible: Bool

        public init(id: String, name: String, primaryMuscles: [String],
                    secondaryMuscles: [String], directMuscles: [String] = [],
                    indirectMuscles: [String] = [], volumeEligible: Bool) {
            self.id = id
            self.name = name
            self.primaryMuscles = primaryMuscles
            self.secondaryMuscles = secondaryMuscles
            self.directMuscles = directMuscles
            self.indirectMuscles = indirectMuscles
            self.volumeEligible = volumeEligible
        }
    }

    public struct CardioSession: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var type: CardioType
        public var durationMinutes: Double
        public var moderateEquivalentMinutes: Double
        public var intensity: RelativeIntensity
        public var isInterval: Bool
        public var isIndoor: Bool?
        public var start: Date

        public init(id: UUID, type: CardioType, durationMinutes: Double,
                    moderateEquivalentMinutes: Double, intensity: RelativeIntensity,
                    isInterval: Bool, isIndoor: Bool?, start: Date) {
            self.id = id
            self.type = type
            self.durationMinutes = max(0, durationMinutes)
            self.moderateEquivalentMinutes = max(0, moderateEquivalentMinutes)
            self.intensity = intensity
            self.isInterval = isInterval
            self.isIndoor = isIndoor
            self.start = start
        }
    }

    /// Everything the phone's suggestion input needs from settings.
    public struct CoachSettings: Codable, Equatable, Sendable {
        public var trainingGoal: TrainingGoal
        public var experience: ExperienceLevel
        public var preferredStyle: SuggestedWorkoutStyle
        public var schedule: CoachSchedulePreferences
        public var trackedGroups: Set<MuscleGroup>
        public var preferredSetsPerExercise: Int
        public var unit: MeasurementUnitPreference
        public var warmupMinutes: Int
        public var cooldownMinutes: Int
        public var engineContext: SuggestedWorkoutEngineContext
        public var excludedCardioTypes: Set<CardioType>
        public var excludedHIITProtocolIDs: Set<String>
        public var weeklyCardioTargetMinutes: Double

        public init(trainingGoal: TrainingGoal,
                    experience: ExperienceLevel,
                    preferredStyle: SuggestedWorkoutStyle,
                    schedule: CoachSchedulePreferences,
                    trackedGroups: Set<MuscleGroup>,
                    preferredSetsPerExercise: Int,
                    unit: MeasurementUnitPreference,
                    warmupMinutes: Int,
                    cooldownMinutes: Int,
                    engineContext: SuggestedWorkoutEngineContext,
                    excludedCardioTypes: Set<CardioType>,
                    excludedHIITProtocolIDs: Set<String>,
                    weeklyCardioTargetMinutes: Double) {
            self.trainingGoal = trainingGoal
            self.experience = experience
            self.preferredStyle = preferredStyle
            self.schedule = schedule
            self.trackedGroups = trackedGroups
            self.preferredSetsPerExercise = max(1, preferredSetsPerExercise)
            self.unit = unit
            self.warmupMinutes = max(0, warmupMinutes)
            self.cooldownMinutes = max(0, cooldownMinutes)
            self.engineContext = engineContext
            self.excludedCardioTypes = excludedCardioTypes
            self.excludedHIITProtocolIDs = excludedHIITProtocolIDs
            self.weeklyCardioTargetMinutes = max(1, weeklyCardioTargetMinutes)
        }
    }

    public var schemaVersion: Int
    public var generatedAt: Date
    public var coachSettings: CoachSettings
    /// All-time counts, not just the 12-week window: the generator uses these
    /// for history-quality gates, and the phone uses all-time counts too.
    public var allTimeWorkoutCount: Int
    public var allTimeWorkingSetCount: Int
    /// All-history recent-exclusion signals. These are small parity metadata;
    /// the Watch still recomputes weekly volume from the mirrored sessions.
    public var recentlyCompletedCandidateIDs: Set<String>
    public var mostRecentExerciseWorkingSets: Int?
    public var strengthSessions: [StrengthSession]
    public var exercises: [String: Exercise]
    public var candidates: [SuggestedExerciseCandidate]
    public var cardioSessions: [CardioSession]

    /// Canonical, timestamp-free bytes for change detection. The phone should
    /// transfer only when this changes; the real `generatedAt` still orders the
    /// envelope on the Watch.
    public func contentRevisionData() throws -> Data {
        var copy = self
        copy.generatedAt = .distantPast
        let engine = copy.coachSettings.engineContext
        copy.coachSettings.engineContext = SuggestedWorkoutEngineContext(
            experience: engine.experience,
            schedule: engine.schedule,
            availableEquipment: engine.availableEquipment,
            environment: engine.environment,
            asOf: .distantPast)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(copy)
    }

    public init(schemaVersion: Int = Self.currentSchemaVersion,
                generatedAt: Date,
                coachSettings: CoachSettings,
                allTimeWorkoutCount: Int,
                allTimeWorkingSetCount: Int,
                recentlyCompletedCandidateIDs: Set<String> = [],
                mostRecentExerciseWorkingSets: Int? = nil,
                strengthSessions: [StrengthSession],
                exercises: [String: Exercise],
                candidates: [SuggestedExerciseCandidate],
                cardioSessions: [CardioSession]) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.coachSettings = coachSettings
        self.allTimeWorkoutCount = max(0, allTimeWorkoutCount)
        self.allTimeWorkingSetCount = max(0, allTimeWorkingSetCount)
        self.recentlyCompletedCandidateIDs = recentlyCompletedCandidateIDs
        self.mostRecentExerciseWorkingSets = mostRecentExerciseWorkingSets
        self.strengthSessions = Array(strengthSessions.prefix(Self.maxStrengthSessions))
        self.exercises = exercises
        self.candidates = Array(candidates.prefix(Self.maxCandidates))
        self.cardioSessions = Array(cardioSessions.prefix(Self.maxCardioSessions))
    }
}

/// The transported unit. The revision is a content hash so the phone can skip
/// an unchanged transfer and the Watch can reject older/duplicate files.
public struct WatchMesocycleEnvelope: Codable, Equatable, Sendable {
    public var revision: String
    public var mirror: WatchMesocycleMirror

    public init(revision: String, mirror: WatchMesocycleMirror) {
        self.revision = revision
        self.mirror = mirror
    }

    public func isNewer(than other: WatchMesocycleEnvelope?) -> Bool {
        guard let other else { return true }
        if mirror.generatedAt != other.mirror.generatedAt {
            return mirror.generatedAt > other.mirror.generatedAt
        }
        // Equal timestamps: the phone is authoritative for a changed payload.
        return revision != other.revision
    }
}

public enum WatchMesocycleHash {
    public static func make(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}

public enum WatchMesocycleTransfer {
    public static let revisionMetadataKey = "mesocycleRevision"
    public static let generatedAtMetadataKey = "mesocycleGeneratedAt"
}

public enum WatchMesocycleCodec {
    public static func encode(_ envelope: WatchMesocycleEnvelope) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(envelope)
    }

    public static func decode(_ data: Data) -> WatchMesocycleEnvelope? {
        guard let envelope = try? PropertyListDecoder().decode(WatchMesocycleEnvelope.self, from: data),
              envelope.mirror.schemaVersion == WatchMesocycleMirror.currentSchemaVersion,
              !envelope.revision.isEmpty else { return nil }
        return envelope
    }
}

/// Durable Watch-side mirror. One file, atomically replaced only by a newer
/// envelope. File IO is deliberately simple: this is a bounded value payload,
/// not a second SwiftData store.
public struct WatchMesocycleMirrorStore {
    public static let fileName = "watch-mesocycle-mirror-v1.plist"
    public static let updatedNotification = Notification.Name("cadence.watchMesocycleMirrorUpdated")

    private let url: URL

    public init(url: URL = WatchMesocycleMirrorStore.defaultURL()) {
        self.url = url
    }

    public func load() -> WatchMesocycleEnvelope? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return WatchMesocycleCodec.decode(data)
    }

    public var currentRevision: String? { load()?.revision }

    /// Returns true only when the incoming envelope was applied. Older or
    /// duplicate deliveries are ignored, so the phone always wins.
    @discardableResult
    public func apply(data: Data) -> Bool {
        guard let envelope = WatchMesocycleCodec.decode(data) else { return false }
        return apply(envelope)
    }

    @discardableResult
    public func apply(_ incoming: WatchMesocycleEnvelope) -> Bool {
        guard let data = try? WatchMesocycleCodec.encode(incoming) else { return false }
        let existing = load()
        guard incoming.isNewer(than: existing) else { return false }
        do {
            try data.write(to: url, options: [.atomic])
            NotificationCenter.default.post(name: Self.updatedNotification, object: nil)
            return true
        } catch {
            return false
        }
    }

    public static func defaultURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(fileName)
    }
}
