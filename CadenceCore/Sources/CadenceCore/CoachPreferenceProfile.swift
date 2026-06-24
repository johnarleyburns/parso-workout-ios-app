import Foundation

public enum CoachPrescriptionIntent: String, Codable, Sendable, Equatable, CaseIterable {
    case easyAerobic
    case moderateAerobic
    case vigorousIntervals
    case recovery
    case strengthPattern
    case rest
    case assessment
}

public struct CoachPreferenceProfile: Codable, Equatable, Sendable {
    public var version: Int
    public var aerobicPreferences: [AerobicPreference]
    public var strengthPreferences: [StrengthPreference]
    public var avoidedTags: [String]
    public var selectionEvents: [CoachPreferenceEvent]

    public static let empty = CoachPreferenceProfile(
        version: 1,
        aerobicPreferences: [],
        strengthPreferences: [],
        avoidedTags: [],
        selectionEvents: []
    )

    public init(version: Int = 1,
                aerobicPreferences: [AerobicPreference] = [],
                strengthPreferences: [StrengthPreference] = [],
                avoidedTags: [String] = [],
                selectionEvents: [CoachPreferenceEvent] = []) {
        self.version = version
        self.aerobicPreferences = aerobicPreferences
        self.strengthPreferences = strengthPreferences
        self.avoidedTags = avoidedTags
        self.selectionEvents = selectionEvents
    }

    public mutating func recordSelection(_ session: CoachSession,
                                          from alternatives: [CoachSession],
                                          at date: Date = Date()) {
        let intent = Self.intent(for: session.kind)
        let event = CoachPreferenceEvent(
            id: UUID(),
            selectedSessionId: session.id,
            selectedTitle: session.title,
            selectedKind: session.kind,
            selectedModality: session.modality.map(AerobicModalityStorage.init(from:)),
            intent: intent,
            alternativeIdsShown: alternatives.map(\.id),
            createdAt: date
        )
        selectionEvents.append(event)

        if let modality = session.modality {
            let stored = AerobicModalityStorage(from: modality)
            if let idx = aerobicPreferences.firstIndex(where: { $0.intent == intent && $0.modality == stored }) {
                aerobicPreferences[idx].score += 1
                aerobicPreferences[idx].updatedAt = date
            } else {
                aerobicPreferences.append(AerobicPreference(
                    intent: intent, modality: stored, score: 1, updatedAt: date
                ))
            }
        }

        if session.kind == .strength, let exercises = session.exercises {
            for ex in exercises {
                let patterns = MovementPattern.patterns(forExerciseNamed: ex.name,
                                                         primaryMuscles: ex.primaryMuscles)
                for pattern in patterns {
                    if let idx = strengthPreferences.firstIndex(where: { $0.pattern == pattern && $0.exerciseName == ex.name }) {
                        strengthPreferences[idx].score += 1
                        strengthPreferences[idx].updatedAt = date
                    } else {
                        strengthPreferences.append(StrengthPreference(
                            pattern: pattern, exerciseName: ex.name, score: 1, updatedAt: date
                        ))
                    }
                }
            }
        }
    }

    public func preferenceScore(for session: CoachSession) -> Int {
        var score = 0
        let sessionIntent = Self.intent(for: session.kind)
        if let modality = session.modality {
            let stored = AerobicModalityStorage(from: modality)
            if let pref = aerobicPreferences.first(where: { $0.intent == sessionIntent && $0.modality == stored }) {
                score += pref.score
            }
        }
        if session.kind == .strength, let exercises = session.exercises {
            for ex in exercises {
                let patterns = MovementPattern.patterns(forExerciseNamed: ex.name,
                                                         primaryMuscles: ex.primaryMuscles)
                for pattern in patterns {
                    if let pref = strengthPreferences.first(where: { $0.pattern == pattern && $0.exerciseName == ex.name }) {
                        score += pref.score
                    }
                }
            }
        }
        for tag in session.trainingLoadTags {
            if avoidedTags.contains(tag) { score -= 2 }
        }
        return score
    }

    public static func intent(for kind: CoachSessionKind) -> CoachPrescriptionIntent {
        switch kind {
        case .strength: return .strengthPattern
        case .easyAerobic: return .easyAerobic
        case .moderateAerobic: return .moderateAerobic
        case .vo2Intervals: return .vigorousIntervals
        case .recovery: return .recovery
        case .rest: return .rest
        case .assessment: return .assessment
        }
    }
}

public struct AerobicPreference: Codable, Equatable, Sendable {
    public var intent: CoachPrescriptionIntent
    public var modality: AerobicModalityStorage
    public var score: Int
    public var updatedAt: Date

    public init(intent: CoachPrescriptionIntent, modality: AerobicModalityStorage,
                score: Int, updatedAt: Date) {
        self.intent = intent
        self.modality = modality
        self.score = score
        self.updatedAt = updatedAt
    }
}

public enum AerobicModalityStorage: String, Codable, Sendable, Equatable {
    case walk, run, cycle, swim, row, boxing, other

    public init(from sessionModality: CoachSession.AerobicModality) {
        switch sessionModality {
        case .walk: self = .walk
        case .run: self = .run
        case .cycle: self = .cycle
        case .swim: self = .swim
        case .row: self = .row
        case .boxing: self = .boxing
        case .other: self = .other
        }
    }

    public var sessionModality: CoachSession.AerobicModality {
        switch self {
        case .walk: return .walk
        case .run: return .run
        case .cycle: return .cycle
        case .swim: return .swim
        case .row: return .row
        case .boxing: return .boxing
        case .other: return .other
        }
    }
}

public struct StrengthPreference: Codable, Equatable, Sendable {
    public var pattern: MovementPattern
    public var exerciseName: String
    public var score: Int
    public var updatedAt: Date

    public init(pattern: MovementPattern, exerciseName: String, score: Int, updatedAt: Date) {
        self.pattern = pattern
        self.exerciseName = exerciseName
        self.score = score
        self.updatedAt = updatedAt
    }
}

public struct CoachPreferenceEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var selectedSessionId: String
    public var selectedTitle: String
    public var selectedKind: CoachSessionKind
    public var selectedModality: AerobicModalityStorage?
    public var intent: CoachPrescriptionIntent
    public var alternativeIdsShown: [String]
    public var createdAt: Date

    public init(id: UUID, selectedSessionId: String, selectedTitle: String,
                selectedKind: CoachSessionKind, selectedModality: AerobicModalityStorage?,
                intent: CoachPrescriptionIntent, alternativeIdsShown: [String],
                createdAt: Date) {
        self.id = id
        self.selectedSessionId = selectedSessionId
        self.selectedTitle = selectedTitle
        self.selectedKind = selectedKind
        self.selectedModality = selectedModality
        self.intent = intent
        self.alternativeIdsShown = alternativeIdsShown
        self.createdAt = createdAt
    }
}
