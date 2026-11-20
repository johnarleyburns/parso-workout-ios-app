import Foundation

/// `UserDefaults`-shaped storage seam for the platform transport contracts.
/// Kept separate from `CadenceCore.DefaultsStoring` because this module is
/// deliberately dependency-free (widgets/Live Activities only link it).
public protocol PlatformDefaultsStoring: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func string(forKey defaultName: String) -> String?
    func data(forKey defaultName: String) -> Data?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: PlatformDefaultsStoring {}

/// Process-local test double for `PlatformDefaultsStoring`; no preferences
/// daemon or plist file is touched.
public final class InMemoryPlatformDefaultsStore: PlatformDefaultsStoring, @unchecked Sendable {
    private var values: [String: Any] = [:]

    public init() {}

    public func object(forKey defaultName: String) -> Any? { values[defaultName] }
    public func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    public func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    public func set(_ value: Any?, forKey defaultName: String) {
        if let value { values[defaultName] = value } else { values.removeValue(forKey: defaultName) }
    }
    public func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
}

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
    private static let liveActivityActionKey = "cadence.platform.liveActivity.action"
    private static let thisWeekSectionKey = "cadence.platform.thisWeek.section"

    /// Actions are written by a Live Activity or Control Center extension and
    /// consumed by the foreground workout surface. They are intentionally
    /// small, idempotent commands rather than serialized SwiftData objects:
    /// the extension must never open or mutate the user's training store.
    public enum LiveActivityAction: String, Codable, Equatable, Sendable {
        case logPlannedSet
        case addRest
        case skipRest
    }

    public struct LiveActivityRequest: Codable, Equatable, Sendable {
        public let action: LiveActivityAction
        public let token: String?

        public init(action: LiveActivityAction, token: String? = nil) {
            self.action = action
            self.token = token
        }
    }

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

    public static func requestStartWorkout(defaults: PlatformDefaultsStoring? = nil) {
        store(defaults).set(Date(), forKey: startKey)
    }

    public static func consumeStartWorkout(defaults: PlatformDefaultsStoring? = nil) -> Bool {
        let defaults = store(defaults)
        guard defaults.object(forKey: startKey) != nil else { return false }
        defaults.removeObject(forKey: startKey)
        return true
    }

    public static func requestLogSet(_ request: LogSetRequest, defaults: PlatformDefaultsStoring? = nil) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        store(defaults).set(data, forKey: logKey)
    }

    public static func consumeLogSet(defaults: PlatformDefaultsStoring? = nil) -> LogSetRequest? {
        let defaults = store(defaults)
        guard let data = defaults.data(forKey: logKey),
              let request = try? JSONDecoder().decode(LogSetRequest.self, from: data) else { return nil }
        defaults.removeObject(forKey: logKey)
        return request
    }

    /// Requests that an active workout present the in-app Quick Talk recorder.
    /// The iOS 18 AudioRecordingIntent uses this handoff and never writes
    /// workout data or accesses the microphone while the app is locked.
    /// Records which This Week section a Today tap should open. Written by the
    /// weekly rings and consumed by the This Week surface as it appears, so the
    /// tab switch and the scroll/expand land together.
    public static func requestThisWeekSection(_ destination: ThisWeekDestination,
                                              defaults: PlatformDefaultsStoring? = nil) {
        store(defaults).set(destination.rawValue, forKey: thisWeekSectionKey)
    }

    public static func consumeThisWeekSection(defaults: PlatformDefaultsStoring? = nil) -> ThisWeekDestination? {
        let defaults = store(defaults)
        guard let raw = defaults.string(forKey: thisWeekSectionKey) else { return nil }
        defaults.removeObject(forKey: thisWeekSectionKey)
        return ThisWeekDestination(rawValue: raw)
    }



    public static func requestLiveActivity(_ action: LiveActivityAction,
                                           token: String? = nil,
                                           defaults: PlatformDefaultsStoring? = nil) {
        guard let data = try? JSONEncoder().encode(LiveActivityRequest(action: action, token: token)) else {
            return
        }
        store(defaults).set(data, forKey: liveActivityActionKey)
    }

    public static func consumeLiveActivity(defaults: PlatformDefaultsStoring? = nil) -> LiveActivityAction? {
        consumeLiveActivityRequest(defaults: defaults)?.action
    }

    public static func consumeLiveActivityRequest(defaults: PlatformDefaultsStoring? = nil) -> LiveActivityRequest? {
        let defaults = store(defaults)
        guard let data = defaults.data(forKey: liveActivityActionKey),
              let request = try? JSONDecoder().decode(LiveActivityRequest.self, from: data) else {
            // Remove pre-release string values after a version upgrade rather
            // than replaying an action without a verified request envelope.
            defaults.removeObject(forKey: liveActivityActionKey)
            return nil
        }
        defaults.removeObject(forKey: liveActivityActionKey)
        return request
    }

    private static func store(_ defaults: PlatformDefaultsStoring?) -> PlatformDefaultsStoring {
        if let defaults { return defaults }
        return UserDefaults(suiteName: CadencePlatformSnapshotStore.appGroupIdentifier) ?? UserDefaults.standard
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
                            defaults: PlatformDefaultsStoring? = nil) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        (defaults ?? sharedDefaults()).set(data, forKey: snapshotKey)
    }

    public static func load(defaults: PlatformDefaultsStoring? = nil) -> CadenceTodaySnapshot? {
        guard let data = (defaults ?? sharedDefaults()).data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(CadenceTodaySnapshot.self, from: data)
    }

    private static func sharedDefaults() -> PlatformDefaultsStoring {
        UserDefaults(suiteName: appGroupIdentifier) ?? UserDefaults.standard
    }
}

/// Small shared state for the watch Smart Stack surface. The watch app writes
/// the active workout/rest projection and the watch widget reads it without
/// needing access to SwiftData or HealthKit.
public struct CadenceWatchWidgetState: Codable, Equatable, Sendable {
    public let workoutTitle: String
    public let restEndsAt: Date?
    /// Watch redesign A2: the rest's full length (for the Smart Stack ring) and the next set.
    public let restTotalSeconds: Int?
    public let nextSet: String?

    public init(workoutTitle: String, restEndsAt: Date? = nil, restTotalSeconds: Int? = nil,
                nextSet: String? = nil) {
        self.workoutTitle = workoutTitle
        self.restEndsAt = restEndsAt
        self.restTotalSeconds = restTotalSeconds
        self.nextSet = nextSet
    }
}

public enum CadenceWatchWidgetStore {
    public static let stateKey = "cadence.watchWidgetState.v1"

    public static func save(_ state: CadenceWatchWidgetState,
                            defaults: PlatformDefaultsStoring? = nil) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        (defaults ?? sharedDefaults()).set(data, forKey: stateKey)
    }

    public static func load(defaults: PlatformDefaultsStoring? = nil) -> CadenceWatchWidgetState? {
        guard let data = (defaults ?? sharedDefaults()).data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(CadenceWatchWidgetState.self, from: data)
    }

    public static func clear(defaults: PlatformDefaultsStoring? = nil) {
        (defaults ?? sharedDefaults()).removeObject(forKey: stateKey)
    }

    private static func sharedDefaults() -> PlatformDefaultsStoring {
        UserDefaults(suiteName: CadencePlatformSnapshotStore.appGroupIdentifier) ?? UserDefaults.standard
    }
}

/// Watch complication (W5): the durable "a workout is running" marker the watch app writes and the
/// widget extension reads out-of-process. The app clears it the moment the session ends, and the
/// reader additionally ignores a marker older than `maxAge` so a crash can never leave it stuck.
public struct CadenceWatchActiveWorkout: Codable, Equatable, Sendable {
    public let workoutType: String
    public let startedAt: Date
    public init(workoutType: String, startedAt: Date) {
        self.workoutType = workoutType
        self.startedAt = startedAt
    }
}

public enum CadenceWatchComplicationState: Equatable, Sendable {
    case active(workoutType: String, startedAt: Date)
    case idle

    public static let maxAge: TimeInterval = 12 * 3600
    public static let activeKey = "cadence.watchActiveWorkout.v1"

    /// Deep link used by the complication; lands on the live workout via the root routing.
    public static let deepLink = "cladiron://workout"

    public static func current(defaults: PlatformDefaultsStoring? = nil, now: Date = Date()) -> Self {
        let store = resolvedStore(defaults)
        guard let data = store.data(forKey: activeKey),
              let marker = try? JSONDecoder().decode(CadenceWatchActiveWorkout.self, from: data),
              marker.startedAt <= now.addingTimeInterval(60),
              now.timeIntervalSince(marker.startedAt) < maxAge else { return .idle }
        return .active(workoutType: marker.workoutType, startedAt: marker.startedAt)
    }

    public static func setActive(_ marker: CadenceWatchActiveWorkout?, defaults: PlatformDefaultsStoring? = nil) {
        let store = resolvedStore(defaults)
        if let marker, let data = try? JSONEncoder().encode(marker) {
            store.set(data, forKey: activeKey)
        } else {
            store.removeObject(forKey: activeKey)
        }
    }

    private static func resolvedStore(_ defaults: PlatformDefaultsStoring?) -> PlatformDefaultsStoring {
        if let defaults { return defaults }
        return UserDefaults(suiteName: CadencePlatformSnapshotStore.appGroupIdentifier) ?? UserDefaults.standard
    }
}
