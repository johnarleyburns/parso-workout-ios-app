import Foundation

// MARK: - Portable export DTOs (FR-6.2)
//
// A version-stamped, Codable snapshot of the user's strength + cardio data so
// they can leave with everything they own. Weights are canonical kg.

public struct CadenceExport: Codable, Equatable, Sendable {
    public var version: Int
    public var exportedAt: Date
    public var sessions: [ExportSession]
    public var cardio: [ExportCardio]
    public var assessments: [ExportAssessment]
    public var coachPreferences: ExportCoachPreferences?
    /// All app/user preferences (settings + schedule) so a fresh install round-trips
    /// completely (v4). nil for legacy exports.
    public var preferences: ExportPreferences?

    public init(version: Int = CadenceExport.currentVersion,
                exportedAt: Date = Date(),
                sessions: [ExportSession],
                cardio: [ExportCardio] = [],
                assessments: [ExportAssessment] = [],
                coachPreferences: ExportCoachPreferences? = nil,
                preferences: ExportPreferences? = nil) {
        self.version = version
        self.exportedAt = exportedAt
        self.sessions = sessions
        self.cardio = cardio
        self.assessments = assessments
        self.coachPreferences = coachPreferences
        self.preferences = preferences
    }

    enum CodingKeys: String, CodingKey {
        case version, exportedAt, sessions, cardio, assessments, coachPreferences, preferences
    }

    // Custom decode so older exports (v1–v3) that lack `cardio`/`assessments`/
    // `preferences` still decode cleanly.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        exportedAt = try c.decode(Date.self, forKey: .exportedAt)
        sessions = try c.decodeIfPresent([ExportSession].self, forKey: .sessions) ?? []
        cardio = try c.decodeIfPresent([ExportCardio].self, forKey: .cardio) ?? []
        assessments = try c.decodeIfPresent([ExportAssessment].self, forKey: .assessments) ?? []
        coachPreferences = try c.decodeIfPresent(ExportCoachPreferences.self, forKey: .coachPreferences)
        preferences = try c.decodeIfPresent(ExportPreferences.self, forKey: .preferences)
    }

    /// v4 adds full cardio (incl. HR/route samples), assessments, session/set
    /// metadata, and all user preferences — a fully lossless round-trip.
    public static let currentVersion = 4
}

public struct ExportSession: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var notes: String?
    public var sets: [ExportSet]
    // Metadata (v4, all optional for back-compat).
    public var endedAt: Date?
    public var isLogged: Bool?
    public var planKey: String?
    public var templateName: String?
    public var plannedExerciseNames: [String]?
    public var plannedRepLadder: [Int]?
    public var warmupSeconds: Double?
    public var cooldownSeconds: Double?
    public var prescribedLoadKg: Double?
    public var activePartnerIDs: [String]?
    public init(id: UUID, title: String, date: Date, notes: String?, sets: [ExportSet],
                endedAt: Date? = nil, isLogged: Bool? = nil, planKey: String? = nil,
                templateName: String? = nil, plannedExerciseNames: [String]? = nil,
                plannedRepLadder: [Int]? = nil, warmupSeconds: Double? = nil,
                cooldownSeconds: Double? = nil, prescribedLoadKg: Double? = nil,
                activePartnerIDs: [String]? = nil) {
        self.id = id; self.title = title; self.date = date; self.notes = notes; self.sets = sets
        self.endedAt = endedAt; self.isLogged = isLogged; self.planKey = planKey
        self.templateName = templateName; self.plannedExerciseNames = plannedExerciseNames
        self.plannedRepLadder = plannedRepLadder; self.warmupSeconds = warmupSeconds
        self.cooldownSeconds = cooldownSeconds; self.prescribedLoadKg = prescribedLoadKg
        self.activePartnerIDs = activePartnerIDs
    }
}

public struct ExportSet: Codable, Equatable, Sendable {
    public var id: UUID
    public var exerciseName: String
    public var category: String?
    public var weightKg: Double
    public var reps: Int
    public var order: Int
    public var isWarmup: Bool
    public var rpe: Double?
    public var note: String?
    public var completedAt: Date
    /// Partner name when the set was performed by someone other than the owner
    /// (field-testing §04, decision #14). nil ⇒ the owner.
    public var performedBy: String?
    /// Load accounting metadata (v3). nil for legacy pre-accounting exports.
    public var barWeightKg: Double?
    public var loadMultiplier: Double?
    public var loadAccountingMode: String?
    /// Bodyweight set flag (v4). nil for legacy exports.
    public var usesBodyweight: Bool?
    public init(id: UUID, exerciseName: String, category: String?, weightKg: Double,
                reps: Int, order: Int, isWarmup: Bool, rpe: Double?, note: String?, completedAt: Date,
                performedBy: String? = nil,
                barWeightKg: Double? = nil, loadMultiplier: Double? = nil,
                loadAccountingMode: String? = nil, usesBodyweight: Bool? = nil) {
        self.id = id; self.exerciseName = exerciseName; self.category = category
        self.weightKg = weightKg; self.reps = reps; self.order = order
        self.isWarmup = isWarmup; self.rpe = rpe; self.note = note; self.completedAt = completedAt
        self.performedBy = performedBy
        self.barWeightKg = barWeightKg; self.loadMultiplier = loadMultiplier
        self.loadAccountingMode = loadAccountingMode; self.usesBodyweight = usesBodyweight
    }
}

public struct ExportCardio: Codable, Equatable, Sendable {
    public var id: UUID
    public var type: String
    public var start: Date
    public var end: Date?
    public var distanceMeters: Double?
    public var activeEnergyKcal: Double?
    public var avgHeartRate: Double?
    public var source: String
    // Metadata + samples (v4, all optional for back-compat).
    public var maxHeartRate: Double?
    public var laps: Int?
    public var targetLaps: Int?
    public var targetDistance: Double?
    public var notes: String?
    public var isLogged: Bool?
    public var customTitle: String?
    public var importedWorkoutKindRaw: String?
    public var intervalDetailData: String?
    public var hrSamples: [ExportHRSample]?
    public var routeSamples: [ExportRouteSample]?
    public init(id: UUID, type: String, start: Date, end: Date?, distanceMeters: Double?,
                activeEnergyKcal: Double?, avgHeartRate: Double?, source: String,
                maxHeartRate: Double? = nil, laps: Int? = nil, targetLaps: Int? = nil,
                targetDistance: Double? = nil, notes: String? = nil, isLogged: Bool? = nil,
                customTitle: String? = nil, importedWorkoutKindRaw: String? = nil,
                intervalDetailData: String? = nil,
                hrSamples: [ExportHRSample]? = nil, routeSamples: [ExportRouteSample]? = nil) {
        self.id = id; self.type = type; self.start = start; self.end = end
        self.distanceMeters = distanceMeters; self.activeEnergyKcal = activeEnergyKcal
        self.avgHeartRate = avgHeartRate; self.source = source
        self.maxHeartRate = maxHeartRate; self.laps = laps; self.targetLaps = targetLaps
        self.targetDistance = targetDistance; self.notes = notes; self.isLogged = isLogged
        self.customTitle = customTitle; self.importedWorkoutKindRaw = importedWorkoutKindRaw
        self.intervalDetailData = intervalDetailData
        self.hrSamples = hrSamples; self.routeSamples = routeSamples
    }
}

public struct ExportHRSample: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var bpm: Double
    public init(t: TimeInterval, bpm: Double) { self.t = t; self.bpm = bpm }
}

public struct ExportRouteSample: Codable, Equatable, Sendable {
    public var t: TimeInterval
    public var lat: Double
    public var lon: Double
    public var elevation: Double
    public init(t: TimeInterval, lat: Double, lon: Double, elevation: Double) {
        self.t = t; self.lat = lat; self.lon = lon; self.elevation = elevation
    }
}

public struct ExportAssessment: Codable, Equatable, Sendable {
    public var id: UUID
    public var date: Date
    public var kind: String
    public var value: Double
    public var inputWeight: Double?
    public var inputReps: Int?
    public var exerciseName: String?
    public var protocolName: String?
    public var notes: String?
    public var inputDistance: Double?
    public var inputTime: Double?
    public var inputEndingHR: Double?
    public var inputAge: Int?
    public var inputSex: Int?
    public init(id: UUID, date: Date, kind: String, value: Double,
                inputWeight: Double? = nil, inputReps: Int? = nil, exerciseName: String? = nil,
                protocolName: String? = nil, notes: String? = nil, inputDistance: Double? = nil,
                inputTime: Double? = nil, inputEndingHR: Double? = nil,
                inputAge: Int? = nil, inputSex: Int? = nil) {
        self.id = id; self.date = date; self.kind = kind; self.value = value
        self.inputWeight = inputWeight; self.inputReps = inputReps; self.exerciseName = exerciseName
        self.protocolName = protocolName; self.notes = notes; self.inputDistance = inputDistance
        self.inputTime = inputTime; self.inputEndingHR = inputEndingHR
        self.inputAge = inputAge; self.inputSex = inputSex
    }
}

/// All app/user preferences for a lossless round-trip (v4). The coach's *learned*
/// profile travels in `CadenceExport.coachPreferences`; this carries the rest.
public struct ExportPreferences: Codable, Equatable, Sendable {
    public var unit: String?
    public var prRule: String?
    public var oneRepMaxFormula: String?
    public var stepGoal: Int?
    public var weeklyCardioMinutesGoal: Int?
    public var restSeconds: Int?
    public var warmupMinutes: Int?
    public var cooldownMinutes: Int?
    public var autoStartRest: Bool?
    public var idleTimeoutMinutes: Int?
    public var gpsHighAccuracy: Bool?
    public var autoPause: Bool?
    public var intervalColorBlind: Bool?
    public var spokenCues: Bool?
    public var plateRounding: Bool?
    public var autoSaveHealth: Bool?
    public var autoEndOnIdle: Bool?
    public var workoutSounds: Bool?
    public var preWorkoutCountdown: Int?
    public var trainingGoal: String?
    public var experienceLevel: String?
    public var useHRMonitoring: Bool?
    public var recoveryAwareCoachV2: Bool?
    public var favoriteRoutineIDs: [String]?
    public var hasCompletedOnboarding: Bool?
    public var schedulePreferences: CoachSchedulePreferences?
    /// The coach's learned preference profile, carried losslessly as its own
    /// Codable type (the top-level `coachPreferences` DTO stays for back-compat).
    public var coachProfile: CoachPreferenceProfile?
    public init(unit: String? = nil, prRule: String? = nil, oneRepMaxFormula: String? = nil,
                stepGoal: Int? = nil, weeklyCardioMinutesGoal: Int? = nil, restSeconds: Int? = nil,
                warmupMinutes: Int? = nil, cooldownMinutes: Int? = nil, autoStartRest: Bool? = nil,
                idleTimeoutMinutes: Int? = nil, gpsHighAccuracy: Bool? = nil, autoPause: Bool? = nil,
                intervalColorBlind: Bool? = nil, spokenCues: Bool? = nil, plateRounding: Bool? = nil,
                autoSaveHealth: Bool? = nil, autoEndOnIdle: Bool? = nil, workoutSounds: Bool? = nil,
                preWorkoutCountdown: Int? = nil, trainingGoal: String? = nil, experienceLevel: String? = nil,
                useHRMonitoring: Bool? = nil, recoveryAwareCoachV2: Bool? = nil,
                favoriteRoutineIDs: [String]? = nil, hasCompletedOnboarding: Bool? = nil,
                schedulePreferences: CoachSchedulePreferences? = nil,
                coachProfile: CoachPreferenceProfile? = nil) {
        self.unit = unit; self.prRule = prRule; self.oneRepMaxFormula = oneRepMaxFormula
        self.stepGoal = stepGoal; self.weeklyCardioMinutesGoal = weeklyCardioMinutesGoal
        self.restSeconds = restSeconds; self.warmupMinutes = warmupMinutes; self.cooldownMinutes = cooldownMinutes
        self.autoStartRest = autoStartRest; self.idleTimeoutMinutes = idleTimeoutMinutes
        self.gpsHighAccuracy = gpsHighAccuracy; self.autoPause = autoPause
        self.intervalColorBlind = intervalColorBlind; self.spokenCues = spokenCues; self.plateRounding = plateRounding
        self.autoSaveHealth = autoSaveHealth; self.autoEndOnIdle = autoEndOnIdle; self.workoutSounds = workoutSounds
        self.preWorkoutCountdown = preWorkoutCountdown; self.trainingGoal = trainingGoal
        self.experienceLevel = experienceLevel; self.useHRMonitoring = useHRMonitoring
        self.recoveryAwareCoachV2 = recoveryAwareCoachV2; self.favoriteRoutineIDs = favoriteRoutineIDs
        self.hasCompletedOnboarding = hasCompletedOnboarding; self.schedulePreferences = schedulePreferences
        self.coachProfile = coachProfile
    }
}

// MARK: - Coach preference export DTOs (v2)

public struct ExportCoachPreferences: Codable, Equatable, Sendable {
    public var profileVersion: Int
    public var aerobicPreferences: [ExportAerobicPreference]
    public var strengthPreferences: [ExportStrengthPreference]
    public var avoidedTags: [String]
    public var selectionEvents: [ExportCoachPreferenceEvent]

    public init(profileVersion: Int,
                aerobicPreferences: [ExportAerobicPreference],
                strengthPreferences: [ExportStrengthPreference],
                avoidedTags: [String],
                selectionEvents: [ExportCoachPreferenceEvent]) {
        self.profileVersion = profileVersion
        self.aerobicPreferences = aerobicPreferences
        self.strengthPreferences = strengthPreferences
        self.avoidedTags = avoidedTags
        self.selectionEvents = selectionEvents
    }
}

public struct ExportAerobicPreference: Codable, Equatable, Sendable {
    public var intent: String
    public var modality: String
    public var score: Int
    public var updatedAt: Date

    public init(intent: String, modality: String, score: Int, updatedAt: Date) {
        self.intent = intent; self.modality = modality; self.score = score; self.updatedAt = updatedAt
    }
}

public struct ExportStrengthPreference: Codable, Equatable, Sendable {
    public var pattern: String
    public var exerciseName: String
    public var score: Int
    public var updatedAt: Date

    public init(pattern: String, exerciseName: String, score: Int, updatedAt: Date) {
        self.pattern = pattern; self.exerciseName = exerciseName; self.score = score; self.updatedAt = updatedAt
    }
}

public struct ExportCoachPreferenceEvent: Codable, Equatable, Sendable {
    public var selectedSessionId: String
    public var selectedTitle: String
    public var selectedKind: String
    public var selectedModality: String?
    public var intent: String
    public var alternativeIdsShown: [String]
    public var createdAt: Date

    public init(selectedSessionId: String, selectedTitle: String,
                selectedKind: String, selectedModality: String?,
                intent: String, alternativeIdsShown: [String],
                createdAt: Date) {
        self.selectedSessionId = selectedSessionId
        self.selectedTitle = selectedTitle
        self.selectedKind = selectedKind
        self.selectedModality = selectedModality
        self.intent = intent
        self.alternativeIdsShown = alternativeIdsShown
        self.createdAt = createdAt
    }
}

public extension CoachPreferenceProfile {
    var exportDTO: ExportCoachPreferences {
        ExportCoachPreferences(
            profileVersion: version,
            aerobicPreferences: aerobicPreferences.map { pref in
                ExportAerobicPreference(
                    intent: pref.intent.rawValue,
                    modality: pref.modality.rawValue,
                    score: pref.score,
                    updatedAt: pref.updatedAt
                )
            },
            strengthPreferences: strengthPreferences.map { pref in
                ExportStrengthPreference(
                    pattern: pref.pattern.rawValue,
                    exerciseName: pref.exerciseName,
                    score: pref.score,
                    updatedAt: pref.updatedAt
                )
            },
            avoidedTags: avoidedTags,
            selectionEvents: selectionEvents.map { event in
                ExportCoachPreferenceEvent(
                    selectedSessionId: event.selectedSessionId,
                    selectedTitle: event.selectedTitle,
                    selectedKind: event.selectedKind.rawValue,
                    selectedModality: event.selectedModality?.rawValue,
                    intent: event.intent.rawValue,
                    alternativeIdsShown: event.alternativeIdsShown,
                    createdAt: event.createdAt
                )
            }
        )
    }
}

public enum DataExport {

    private static func jsonEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        // Compact (no pretty-print): the payload is never rendered as text, it is
        // written to a file and gzipped. Sorted keys keep output deterministic;
        // withoutEscapingSlashes shrinks ISO dates. Round-trip is byte-agnostic —
        // tests compare decoded structs, not formatting.
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    private static func jsonDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: JSON

    public static func encodeJSON(_ export: CadenceExport) throws -> Data {
        try jsonEncoder().encode(export)
    }

    /// Compact JSON compressed as a standard gzip (`.json.gz`) container — the
    /// default share/backup format. HR/route-heavy payloads compress ~15–20×.
    public static func encodeJSONGzipped(_ export: CadenceExport) throws -> Data {
        try DataCompression.gzip(encodeJSON(export))
    }

    public static func decodeJSON(_ data: Data) throws -> CadenceExport {
        try jsonDecoder().decode(CadenceExport.self, from: data)
    }

    /// Decodes an exported file regardless of container, sniffing magic bytes so
    /// every historical export stays importable forever:
    /// - `1F 8B` → gzip: inflate, then decode JSON.
    /// - otherwise → plain JSON (all v1–v4 exports), decode directly.
    public static func decodeAny(_ data: Data) throws -> CadenceExport {
        if data.count >= 2, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b {
            return try decodeJSON(DataCompression.gunzip(data))
        }
        return try decodeJSON(data)
    }

    // MARK: CSV (sets, one row per set — the most portable strength format)

    public static func encodeCSV(_ export: CadenceExport) -> String {
        var rows = ["session_id,session_title,session_date,exercise,category,weight_kg,reps,order,is_warmup,rpe,note,completed_at,performed_by"]
        let iso = ISO8601DateFormatter()
        for session in export.sessions {
            for set in session.sets.sorted(by: { $0.order < $1.order }) {
                let fields: [String] = [
                    session.id.uuidString,
                    session.title,
                    iso.string(from: session.date),
                    set.exerciseName,
                    set.category ?? "",
                    String(set.weightKg),
                    String(set.reps),
                    String(set.order),
                    set.isWarmup ? "true" : "false",
                    set.rpe.map { String($0) } ?? "",
                    set.note ?? "",
                    iso.string(from: set.completedAt),
                    set.performedBy ?? ""
                ]
                rows.append(fields.map(csvEscape).joined(separator: ","))
            }
        }
        return rows.joined(separator: "\n")
    }

    static func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
