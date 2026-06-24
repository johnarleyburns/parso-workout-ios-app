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
    public var coachPreferences: ExportCoachPreferences?

    public init(version: Int = CadenceExport.currentVersion,
                exportedAt: Date = Date(),
                sessions: [ExportSession],
                cardio: [ExportCardio] = [],
                coachPreferences: ExportCoachPreferences? = nil) {
        self.version = version
        self.exportedAt = exportedAt
        self.sessions = sessions
        self.cardio = cardio
        self.coachPreferences = coachPreferences
    }

    public static let currentVersion = 2
}

public struct ExportSession: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var date: Date
    public var notes: String?
    public var sets: [ExportSet]
    public init(id: UUID, title: String, date: Date, notes: String?, sets: [ExportSet]) {
        self.id = id; self.title = title; self.date = date; self.notes = notes; self.sets = sets
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
    public init(id: UUID, exerciseName: String, category: String?, weightKg: Double,
                reps: Int, order: Int, isWarmup: Bool, rpe: Double?, note: String?, completedAt: Date,
                performedBy: String? = nil) {
        self.id = id; self.exerciseName = exerciseName; self.category = category
        self.weightKg = weightKg; self.reps = reps; self.order = order
        self.isWarmup = isWarmup; self.rpe = rpe; self.note = note; self.completedAt = completedAt
        self.performedBy = performedBy
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
    public init(id: UUID, type: String, start: Date, end: Date?, distanceMeters: Double?,
                activeEnergyKcal: Double?, avgHeartRate: Double?, source: String) {
        self.id = id; self.type = type; self.start = start; self.end = end
        self.distanceMeters = distanceMeters; self.activeEnergyKcal = activeEnergyKcal
        self.avgHeartRate = avgHeartRate; self.source = source
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
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
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

    public static func decodeJSON(_ data: Data) throws -> CadenceExport {
        try jsonDecoder().decode(CadenceExport.self, from: data)
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
