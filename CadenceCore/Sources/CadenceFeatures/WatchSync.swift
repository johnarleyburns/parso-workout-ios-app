import Foundation
import CadenceCore

public struct WeightIncrement {
    /// Plate-sized shortcuts shown in the single watch adjustment picker.
    public let plateOptions: [Double]
    public let crownDetent: Double
    public let range: ClosedRange<Double>

    public init(unit: MeasurementUnitPreference) {
        switch unit {
        case .pounds:
            self.plateOptions = [45, 35, 25, 10, 5, 2.5]
            self.range = 0...650
        case .kilograms:
            self.plateOptions = [45, 35, 25, 10, 5, 2.5]
            self.range = 0...300
        }
        // The crown is the precision input, independent of the selected plate
        // shortcut. A tenth permits arbitrary practical decimal stack weights
        // such as 12.5 or 17.7 instead of locking entry to 2.5-unit steps.
        self.crownDetent = 0.1
    }

    /// Signed chip label, e.g. "-2.5" / "+2.5" / "+5". Trims a trailing ".0".
    public func chipLabel(_ value: Double) -> String {
        let mag = abs(value)
        let magStr = mag == mag.rounded() ? String(format: "%.0f", mag)
                                          : String(format: "%.1f", mag)
        return (value < 0 ? "-" : "+") + magStr
    }

    public static func unitDefault() -> MeasurementUnitPreference {
        Locale.current.measurementSystem == .us ? .pounds : .kilograms
    }
}

public enum WatchSync {
    public enum Key {
        public static let command = "command"
        public static let requestSettingsSync = "request_settings_sync"
        public static let contextUpdatedAt = "watchSync.contextUpdatedAt"

        public static let unit = "settings.unit"
        public static let distanceUnit = "settings.distanceUnit"
        public static let intervalColorBlind = "settings.intervalColorBlind"
        public static let restSeconds = "settings.restSeconds"
        public static let warmupMinutes = "settings.warmupMinutes"
        public static let cooldownMinutes = "settings.cooldownMinutes"
        public static let workoutSounds = "settings.workoutSounds"
        public static let recentPartners = "partners.recent"
        public static let customExercises = "exercises.custom"

        public static let todayPlanSessions = "todayPlan.sessions"
        public static let todayPlanUpdatedAt = "todayPlan.updatedAt"
    }

    /// Property-list-safe snapshot of a user-created exercise sent from the
    /// phone to the watch. The watch has its own local SwiftData store, so
    /// CloudKit cannot be relied on for the low-latency picker path.
    public struct CustomExercise: Equatable, Sendable {
        public var id: UUID
        public var name: String
        public var category: String?
        public var equipment: String?
        public var mechanics: String?
        public var force: String?
        public var primaryMuscles: [String]
        public var secondaryMuscles: [String]
        public var searchKeywords: [String]
        public var isLateral: Bool
        public var updatedAt: Date

        public init(id: UUID, name: String, category: String? = nil,
                    equipment: String? = nil, mechanics: String? = nil,
                    force: String? = nil, primaryMuscles: [String] = [],
                    secondaryMuscles: [String] = [], searchKeywords: [String] = [],
                    isLateral: Bool = false, updatedAt: Date = Date()) {
            self.id = id; self.name = name; self.category = category
            self.equipment = equipment; self.mechanics = mechanics; self.force = force
            self.primaryMuscles = primaryMuscles; self.secondaryMuscles = secondaryMuscles
            self.searchKeywords = searchKeywords; self.isLateral = isLateral
            self.updatedAt = updatedAt
        }

        public init(exercise: Exercise) {
            self.init(id: exercise.id, name: exercise.name, category: exercise.category,
                      equipment: exercise.equipment, mechanics: exercise.mechanics,
                      force: exercise.force, primaryMuscles: exercise.primaryMuscles,
                      secondaryMuscles: exercise.secondaryMuscles,
                      searchKeywords: exercise.searchKeywords, isLateral: exercise.isLateral,
                      updatedAt: exercise.updatedAt)
        }

        public var propertyList: [String: Any] {
            var result: [String: Any] = [
                "id": id.uuidString, "name": name, "primaryMuscles": primaryMuscles,
                "secondaryMuscles": secondaryMuscles, "searchKeywords": searchKeywords,
                "isLateral": isLateral, "updatedAt": updatedAt
            ]
            if let category { result["category"] = category }
            if let equipment { result["equipment"] = equipment }
            if let mechanics { result["mechanics"] = mechanics }
            if let force { result["force"] = force }
            return result
        }

        public init?(propertyList: [String: Any]) {
            guard let rawID = propertyList["id"] as? String, let id = UUID(uuidString: rawID),
                  let name = propertyList["name"] as? String else { return nil }
            self.init(id: id, name: name, category: propertyList["category"] as? String,
                      equipment: propertyList["equipment"] as? String,
                      mechanics: propertyList["mechanics"] as? String,
                      force: propertyList["force"] as? String,
                      primaryMuscles: propertyList["primaryMuscles"] as? [String] ?? [],
                      secondaryMuscles: propertyList["secondaryMuscles"] as? [String] ?? [],
                      searchKeywords: propertyList["searchKeywords"] as? [String] ?? [],
                      isLateral: propertyList["isLateral"] as? Bool ?? false,
                      updatedAt: propertyList["updatedAt"] as? Date ?? Date())
        }
    }

    public static func customExercisesContext(_ exercises: [Exercise]) -> [[String: Any]] {
        exercises.filter(\.isCustom).map { CustomExercise(exercise: $0).propertyList }
    }

    public struct TodayPlan: Equatable, Sendable {
        public struct Session: Equatable, Sendable, Identifiable {
            public enum Kind: String, Equatable, Sendable {
                case strength
                case cardio
                case rest
            }

            public var id: String
            public var kind: Kind
            public var label: String
            public var exerciseNames: [String]
            public var repLadder: [Int]
            public var cardioType: String?
            public var durationMinutes: Int?
            public var zone: Int?
            /// Rich, versioned plan data. Legacy fields above remain populated
            /// so an older Watch can still launch the workout.
            public var planPayload: WatchPlanPayload?

            public init(id: String, kind: Kind, label: String,
                        exerciseNames: [String] = [], repLadder: [Int] = [],
                        cardioType: String? = nil, durationMinutes: Int? = nil,
                        zone: Int? = nil, planPayload: WatchPlanPayload? = nil) {
                self.id = id
                self.kind = kind
                self.label = label
                self.exerciseNames = exerciseNames
                self.repLadder = repLadder
                self.cardioType = cardioType
                self.durationMinutes = durationMinutes
                self.zone = zone
                self.planPayload = planPayload
            }

            public var isStrength: Bool { kind == .strength }
            public var isRest: Bool { kind == .rest }
        }

        public var sessions: [Session]
        public var updatedAt: Date

        public init(sessions: [Session] = [], updatedAt: Date = Date()) {
            self.sessions = sessions
            self.updatedAt = updatedAt
        }

        public var isRestDay: Bool {
            !sessions.isEmpty && sessions.allSatisfy(\.isRest)
        }

        public var strengthSessions: [Session] {
            sessions.filter(\.isStrength)
        }

        public static func from(day: WeeklyPlan.DayOutline?, updatedAt: Date = Date()) -> TodayPlan {
            guard let day else { return TodayPlan(sessions: [], updatedAt: updatedAt) }
            let sessions = day.sessions.enumerated().map { idx, session -> Session in
                if session.kind == .strength {
                    let exercises = session.exercises?.map(\.name) ?? []
                    let ladder = session.exercises?.first?.repLadder ?? []
                    return Session(
                        id: session.id.isEmpty ? "strength-\(idx)" : session.id,
                        kind: .strength,
                        label: session.label.isEmpty ? "Strength" : session.label,
                        exerciseNames: exercises,
                        repLadder: ladder
                    )
                }
                if session.kind == .rest || session.isRest {
                    return Session(
                        id: session.id.isEmpty ? "rest-\(idx)" : session.id,
                        kind: .rest,
                        label: session.label.isEmpty ? "Rest" : session.label
                    )
                }
                return Session(
                    id: session.id.isEmpty ? "cardio-\(idx)" : session.id,
                    kind: .cardio,
                    label: session.label,
                    cardioType: cardioTypeHint(for: session),
                    durationMinutes: session.cardioDurationMinutes,
                    zone: session.cardioZone,
                    planPayload: nil
                )
            }
            return TodayPlan(sessions: sessions, updatedAt: updatedAt)
        }

        public static func contextDict(_ plan: TodayPlan) -> [String: Any] {
            [
                Key.todayPlanUpdatedAt: plan.updatedAt,
                Key.todayPlanSessions: plan.sessions.map { session -> [String: Any] in
                    var dict: [String: Any] = [
                        "id": session.id,
                        "kind": session.kind.rawValue,
                        "label": session.label,
                        "exerciseNames": session.exerciseNames,
                        "repLadder": session.repLadder,
                    ]
                    if let cardioType = session.cardioType { dict["cardioType"] = cardioType }
                    if let duration = session.durationMinutes { dict["durationMinutes"] = duration }
                    if let zone = session.zone { dict["zone"] = zone }
                    if let payload = session.planPayload {
                        let propertyList = payload.propertyList
                        if !propertyList.isEmpty { dict[WatchPlanPayload.transportKey] = propertyList }
                    }
                    return dict
                },
            ]
        }

        public static func from(context: [String: Any]) -> TodayPlan? {
            guard let rows = context[Key.todayPlanSessions] as? [[String: Any]] else { return nil }
            let sessions = rows.compactMap { row -> Session? in
                guard let id = row["id"] as? String,
                      let rawKind = row["kind"] as? String,
                      let kind = Session.Kind(rawValue: rawKind),
                      let label = row["label"] as? String else { return nil }
                return Session(
                    id: id,
                    kind: kind,
                    label: label,
                    exerciseNames: row["exerciseNames"] as? [String] ?? [],
                    repLadder: row["repLadder"] as? [Int] ?? [],
                    cardioType: row["cardioType"] as? String,
                    durationMinutes: row["durationMinutes"] as? Int,
                    zone: row["zone"] as? Int,
                    planPayload: (row[WatchPlanPayload.transportKey] as? [String: Any]).flatMap(WatchPlanPayload.init(propertyList:))
                )
            }
            let updatedAt = (context[Key.todayPlanUpdatedAt] as? Date) ?? Date()
            return TodayPlan(sessions: sessions, updatedAt: updatedAt)
        }

        private static func cardioTypeHint(for session: PlannedSession) -> String {
            let lower = session.label.lowercased()
            if lower.contains("box") { return "boxing" }
            if lower.contains("row") { return "rowing" }
            if lower.contains("swim") { return "swim" }
            if lower.contains("cycle") || lower.contains("bike") { return "cycle" }
            if lower.contains("walk") { return "walk" }
            if lower.contains("run") { return "run" }
            if session.kind == .vo2Intervals || lower.contains("interval") { return "hiit" }
            return "other"
        }
    }

    public enum Status: Equatable, Sendable {
        case idle
        case syncing(Date)
        case synced(Date)
        case failed(String, Date?)

        public var isInProgress: Bool {
            if case .syncing = self { return true }
            return false
        }

        public var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }

        public var toastText: String? {
            switch self {
            case .idle: return nil
            case .syncing: return "Syncing to Watch"
            case .synced: return "Watch synced"
            case .failed(let message, _):
                return message.isEmpty ? "Watch sync failed" : "Watch sync failed: \(message)"
            }
        }

        public func settingsText(lastSyncAt: Date?) -> String {
            switch self {
            case .syncing:
                return "Syncing..."
            case .synced(let date):
                return "Synced \(Self.relativeText(for: date))"
            case .failed(let message, _):
                return message.isEmpty ? "Failed" : message
            case .idle:
                guard let lastSyncAt else { return "Never synced" }
                return "Synced \(Self.relativeText(for: lastSyncAt))"
            }
        }

        public static func lastSyncText(_ date: Date?) -> String {
            guard let date else { return "Never" }
            return date.formatted(date: .abbreviated, time: .shortened)
        }

        private static func relativeText(for date: Date, now: Date = Date()) -> String {
            let seconds = max(0, Int(now.timeIntervalSince(date)))
            if seconds < 5 { return "just now" }
            if seconds < 60 { return "\(seconds)s ago" }
            let minutes = seconds / 60
            if minutes < 60 { return "\(minutes)m ago" }
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    public struct Preferences: Equatable, Sendable {
        public var unit: MeasurementUnitPreference
        public var distanceUnit: DistanceUnitPreference
        public var intervalColorBlind: Bool
        public var restSeconds: Int
        public var warmupMinutes: Int
        public var cooldownMinutes: Int
        public var workoutSounds: Bool
        public var recentPartnerNames: [String]

        public init(unit: MeasurementUnitPreference = .kilograms,
                    distanceUnit: DistanceUnitPreference = .kilometers,
                    intervalColorBlind: Bool = false,
                    restSeconds: Int = 90,
                    warmupMinutes: Int = 5,
                    cooldownMinutes: Int = 5,
                    workoutSounds: Bool = true,
                    recentPartnerNames: [String] = []) {
            self.unit = unit
            self.distanceUnit = distanceUnit
            self.intervalColorBlind = intervalColorBlind
            self.restSeconds = restSeconds
            self.warmupMinutes = warmupMinutes
            self.cooldownMinutes = cooldownMinutes
            self.workoutSounds = workoutSounds
            self.recentPartnerNames = recentPartnerNames
        }

        public static func contextDict(_ prefs: Preferences) -> [String: Any] {
            var dict: [String: Any] = [
                Key.unit: prefs.unit.rawValue,
                Key.distanceUnit: prefs.distanceUnit.rawValue,
                Key.intervalColorBlind: prefs.intervalColorBlind,
                Key.restSeconds: prefs.restSeconds,
                Key.warmupMinutes: prefs.warmupMinutes,
                Key.cooldownMinutes: prefs.cooldownMinutes,
                Key.workoutSounds: prefs.workoutSounds,
            ]
            if !prefs.recentPartnerNames.isEmpty {
                dict[Key.recentPartners] = prefs.recentPartnerNames
            }
            return dict
        }

        public static func contextDict(_ prefs: Preferences, updatedAt: Date) -> [String: Any] {
            var dict = contextDict(prefs)
            dict[Key.contextUpdatedAt] = updatedAt
            return dict
        }

        public func applying(context: [String: Any]) -> Preferences {
            var copy = self
            if let raw = context[Key.unit] as? String,
               let u = MeasurementUnitPreference(rawValue: raw) {
                copy.unit = u
            }
            if let raw = context[Key.distanceUnit] as? String,
               let du = DistanceUnitPreference(rawValue: raw) {
                copy.distanceUnit = du
            }
            if let cb = context[Key.intervalColorBlind] as? Bool {
                copy.intervalColorBlind = cb
            }
            if let rs = context[Key.restSeconds] as? Int {
                copy.restSeconds = rs
            }
            if let wm = context[Key.warmupMinutes] as? Int {
                copy.warmupMinutes = wm
            }
            if let cm = context[Key.cooldownMinutes] as? Int {
                copy.cooldownMinutes = cm
            }
            if let sounds = context[Key.workoutSounds] as? Bool {
                copy.workoutSounds = sounds
            }
            if let names = context[Key.recentPartners] as? [String] {
                copy.recentPartnerNames = names
            }
            return copy
        }
    }

    public static func requestSettingsSyncMessage() -> [String: Any] {
        [Key.command: Key.requestSettingsSync]
    }
}
