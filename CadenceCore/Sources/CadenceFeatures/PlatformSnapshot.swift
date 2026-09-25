import Foundation

/// Small, privacy-preserving projection shared by the iPhone app and its
/// platform surfaces. It deliberately contains presentation text and stable
/// identifiers only; prescriptions and workout history remain in the app store.
public struct CadenceWeeklyMuscleSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let sets: Double
    public let target: Double

    public init(id: String, sets: Double, target: Double) {
        self.id = id
        self.sets = sets
        self.target = target
    }
}

public struct CadenceTodaySnapshot: Codable, Equatable, Sendable {
    public let dayKey: String
    public let planTitle: String
    public let sessionTitles: [String]
    public let readinessLabel: String?
    public let estimatedMinutes: Int?
    public let setsCompleted: Double?
    public let setsTarget: Double?
    public let cardioMinutes: Double?
    public let cardioTarget: Double?
    public let sessionsCompleted: Double?
    public let sessionsTarget: Double?
    public let weeklyMuscles: [CadenceWeeklyMuscleSnapshot]
    public let updatedAt: Date

    public init(dayKey: String, planTitle: String, sessionTitles: [String],
                readinessLabel: String? = nil, estimatedMinutes: Int? = nil,
                setsCompleted: Double? = nil, setsTarget: Double? = nil,
                cardioMinutes: Double? = nil, cardioTarget: Double? = nil,
                sessionsCompleted: Double? = nil, sessionsTarget: Double? = nil,
                weeklyMuscles: [CadenceWeeklyMuscleSnapshot] = [],
                updatedAt: Date = Date()) {
        self.dayKey = dayKey
        self.planTitle = planTitle
        self.sessionTitles = sessionTitles
        self.readinessLabel = readinessLabel
        self.estimatedMinutes = estimatedMinutes
        self.setsCompleted = setsCompleted
        self.setsTarget = setsTarget
        self.cardioMinutes = cardioMinutes
        self.cardioTarget = cardioTarget
        self.sessionsCompleted = sessionsCompleted
        self.sessionsTarget = sessionsTarget
        self.weeklyMuscles = weeklyMuscles
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case dayKey, planTitle, sessionTitles, readinessLabel, estimatedMinutes
        case setsCompleted, setsTarget, cardioMinutes, cardioTarget
        case sessionsCompleted, sessionsTarget, weeklyMuscles, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        dayKey = try values.decode(String.self, forKey: .dayKey)
        planTitle = try values.decode(String.self, forKey: .planTitle)
        sessionTitles = try values.decode([String].self, forKey: .sessionTitles)
        readinessLabel = try values.decodeIfPresent(String.self, forKey: .readinessLabel)
        estimatedMinutes = try values.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        setsCompleted = try values.decodeIfPresent(Double.self, forKey: .setsCompleted)
        setsTarget = try values.decodeIfPresent(Double.self, forKey: .setsTarget)
        cardioMinutes = try values.decodeIfPresent(Double.self, forKey: .cardioMinutes)
        cardioTarget = try values.decodeIfPresent(Double.self, forKey: .cardioTarget)
        sessionsCompleted = try values.decodeIfPresent(Double.self, forKey: .sessionsCompleted)
        sessionsTarget = try values.decodeIfPresent(Double.self, forKey: .sessionsTarget)
        weeklyMuscles = try values.decodeIfPresent([CadenceWeeklyMuscleSnapshot].self,
                                                   forKey: .weeklyMuscles) ?? []
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
    }
}

public enum CadencePlatformRequestStore {
    private static let startKey = "cadence.platform.startWorkout.requestedAt"
    private static let logKey = "cadence.platform.logSet.request"

    public struct LogSetRequest: Codable, Equatable, Sendable {
        public let exerciseName: String
        public let weightKg: Double
        public let reps: Int

        public init(exerciseName: String, weightKg: Double, reps: Int) {
            self.exerciseName = exerciseName
            self.weightKg = weightKg
            self.reps = reps
        }
    }

    public static func requestStartWorkout(defaults: UserDefaults? = nil) {
        store(defaults).set(Date(), forKey: startKey)
    }

    public static func consumeStartWorkout(defaults: UserDefaults? = nil) -> Bool {
        let defaults = store(defaults)
        guard defaults.object(forKey: startKey) != nil else { return false }
        defaults.removeObject(forKey: startKey)
        return true
    }

    public static func requestLogSet(_ request: LogSetRequest, defaults: UserDefaults? = nil) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        store(defaults).set(data, forKey: logKey)
    }

    public static func consumeLogSet(defaults: UserDefaults? = nil) -> LogSetRequest? {
        let defaults = store(defaults)
        guard let data = defaults.data(forKey: logKey),
              let request = try? JSONDecoder().decode(LogSetRequest.self, from: data) else { return nil }
        defaults.removeObject(forKey: logKey)
        return request
    }

    private static func store(_ defaults: UserDefaults?) -> UserDefaults {
        defaults ?? (UserDefaults(suiteName: CadencePlatformSnapshotStore.appGroupIdentifier) ?? .standard)
    }
}

/// App-group transport for widgets and other extensions. The fallback to
/// standard defaults keeps previews and unsigned local builds useful; the
/// shipped app and extension both use the shared suite when entitlements are
/// present.
public enum CadencePlatformSnapshotStore {
    public static let appGroupIdentifier = "group.guru.parso.ios-workout-app"
    public static let snapshotKey = "cadence.todaySnapshot.v1"

    public static func save(_ snapshot: CadenceTodaySnapshot,
                            defaults: UserDefaults? = nil) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        (defaults ?? sharedDefaults()).set(data, forKey: snapshotKey)
    }

    public static func load(defaults: UserDefaults? = nil) -> CadenceTodaySnapshot? {
        guard let data = (defaults ?? sharedDefaults()).data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(CadenceTodaySnapshot.self, from: data)
    }

    private static func sharedDefaults() -> UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}
