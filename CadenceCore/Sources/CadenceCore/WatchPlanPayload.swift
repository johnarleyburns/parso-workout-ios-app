import Foundation

/// Versioned, property-list-safe plan data sent to the Watch.
///
/// The legacy exercise names, rep ladder, and cardio summary remain inside the
/// payload so an older Watch can continue to execute the plan. Newer Watches
/// use the rich prescriptions when present. Codable decoding intentionally
/// ignores keys added by a newer phone build.
public struct WatchPlanPayload: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let transportKey = "watch_plan_payload"

    public var version: Int
    public var planSessionID: UUID?
    public var title: String?
    public var strength: Strength?
    public var cardio: [Cardio]

    public init(version: Int = WatchPlanPayload.currentVersion,
                planSessionID: UUID? = nil,
                title: String? = nil,
                strength: Strength? = nil,
                cardio: [Cardio] = []) {
        self.version = version
        self.planSessionID = planSessionID
        self.title = title
        self.strength = strength
        self.cardio = cardio
    }

    public struct Strength: Codable, Equatable, Sendable {
        public var exerciseNames: [String]
        public var repLadder: [Int]
        public var prescriptions: [PlannedExercisePrescription]

        public init(exerciseNames: [String] = [], repLadder: [Int] = [],
                    prescriptions: [PlannedExercisePrescription] = []) {
            self.exerciseNames = exerciseNames
            self.repLadder = repLadder
            self.prescriptions = prescriptions
        }
    }

    public struct Cardio: Codable, Equatable, Sendable {
        public let id: UUID
        public var kind: String
        public var durationSeconds: Int?
        public var distanceMeters: Double?
        public var targetZone: Int?
        public var intervalPlanData: Data?

        public init(id: UUID = UUID(), kind: String,
                    durationSeconds: Int? = nil,
                    distanceMeters: Double? = nil,
                    targetZone: Int? = nil,
                    intervalPlanData: Data? = nil) {
            self.id = id
            self.kind = kind
            self.durationSeconds = durationSeconds
            self.distanceMeters = distanceMeters
            self.targetZone = targetZone
            self.intervalPlanData = intervalPlanData
        }
    }

    /// Builds the Watch shape from the pure runtime boundary. Percentage loads
    /// are already resolved by `RuntimePrescriptionAdapter` at this point.
    public static func make(
        from planSession: PlanSessionSnapshot,
        athlete: AthleteExecutionSnapshot
    ) throws -> WatchPlanPayload {
        let draft = try RuntimePrescriptionAdapter().materialize(
            planSession: planSession,
            athlete: athlete)
        let strength = draft.plannedPrescriptions.isEmpty ? nil : Strength(
            exerciseNames: draft.plannedExerciseNames,
            repLadder: draft.plannedRepLadder,
            prescriptions: draft.plannedPrescriptions)
        let cardio = planSession.items.compactMap { item -> Cardio? in
            guard case let .cardio(value) = item else { return nil }
            return Cardio(
                id: value.id,
                kind: value.kind,
                durationSeconds: value.durationSeconds,
                distanceMeters: value.distanceMeters,
                targetZone: value.targetZone,
                intervalPlanData: value.intervalPlanData)
        }
        return WatchPlanPayload(
            planSessionID: planSession.id,
            title: planSession.title,
            strength: strength,
            cardio: cardio)
    }

    /// WatchConnectivity accepts only property-list values. JSON gives this
    /// boundary one stable representation while preserving additive decoding.
    public var propertyList: [String: Any] {
        guard let data = try? JSONEncoder().encode(self),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    public init?(propertyList: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(propertyList),
              let data = try? JSONSerialization.data(withJSONObject: propertyList),
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            return nil
        }
        self = value
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case planSessionID
        case title
        case strength
        case cardio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        planSessionID = try container.decodeIfPresent(UUID.self, forKey: .planSessionID)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        strength = try container.decodeIfPresent(Strength.self, forKey: .strength)
        cardio = try container.decodeIfPresent([Cardio].self, forKey: .cardio) ?? []
    }
}
