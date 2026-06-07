import Foundation
import SwiftData

// MARK: - Models
//
// CloudKit compatibility rules (REQUIREMENTS §7, FR-9):
//  • every stored property is optional OR has a default value
//  • every relationship is optional
//  • no @Attribute(.unique) — CloudKit does not support unique constraints
//  • inverse is declared on exactly one side of each relationship
//
// Every entity carries a stable `id` (UUID), `updatedAt`, and `originDevice`
// for CloudKit reconciliation across devices (FR-9.2). De-duplication is by
// `id` in the repository layer, not by a DB unique constraint.
//
// Rich set/rep/weight detail lives here in SwiftData. HealthKit only ever
// receives a summary HKWorkout (FR-4.3).

// MARK: Exercise

@Model
public final class Exercise {
    public var id: UUID = UUID()
    public var name: String = ""
    /// Raw value of `ExerciseCategory`; stored as String for CloudKit friendliness.
    public var category: String?
    /// Free-form muscle-group tags (e.g. "chest", "triceps").
    public var muscleGroups: [String] = []
    public var isCustom: Bool = false
    // Field-testing §03 facets (all optional/defaulted for CloudKit + back-compat).
    /// Raw value of `Equipment`.
    public var equipment: String?
    /// Isolateral / unilateral movement (decision #11).
    public var isLateral: Bool = false
    /// Raw value of `Mechanics` (compound/isolation).
    public var mechanics: String?
    /// Raw value of `Force` (push/pull/static).
    public var force: String?
    /// Canonical muscle ids (see `MuscleCatalog`).
    public var primaryMuscles: [String] = []
    public var secondaryMuscles: [String] = []
    /// Flattened, lowercased search tokens derived at seed/create time.
    public var searchKeywords: [String] = []
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var originDevice: String = ""

    @Relationship(deleteRule: .nullify, inverse: \SetEntry.exercise)
    public var sets: [SetEntry]? = []

    public init(id: UUID = UUID(),
                name: String = "",
                category: ExerciseCategory? = nil,
                muscleGroups: [String] = [],
                isCustom: Bool = false,
                equipment: Equipment? = nil,
                isLateral: Bool = false,
                mechanics: Mechanics? = nil,
                force: Force? = nil,
                primaryMuscles: [String] = [],
                secondaryMuscles: [String] = [],
                searchKeywords: [String] = [],
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                originDevice: String = "") {
        self.id = id
        self.name = name
        self.category = category?.rawValue
        self.muscleGroups = muscleGroups
        self.isCustom = isCustom
        self.equipment = equipment?.rawValue
        self.isLateral = isLateral
        self.mechanics = mechanics?.rawValue
        self.force = force?.rawValue
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.searchKeywords = searchKeywords
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    public var categoryValue: ExerciseCategory? {
        get { category.flatMap(ExerciseCategory.init(rawValue:)) }
        set { category = newValue?.rawValue }
    }
    public var equipmentValue: Equipment? {
        get { equipment.flatMap(Equipment.init(rawValue:)) }
        set { equipment = newValue?.rawValue }
    }
    public var mechanicsValue: Mechanics? {
        get { mechanics.flatMap(Mechanics.init(rawValue:)) }
        set { mechanics = newValue?.rawValue }
    }
    public var forceValue: Force? {
        get { force.flatMap(Force.init(rawValue:)) }
        set { force = newValue?.rawValue }
    }
}

/// Coarse training split categories (FR-1.1).
public enum ExerciseCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case push, pull, legs, core, cardio, other
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .core: return "Core"
        case .cardio: return "Cardio"
        case .other: return "Other"
        }
    }
}

// MARK: Session

@Model
public final class WorkoutSession {
    public var id: UUID = UUID()
    public var title: String = ""
    public var date: Date = Date()
    public var notes: String?
    /// Name of the template this session was started from, if any (FR-1.6).
    public var templateName: String?
    /// Links to the summary HKWorkout written for this session (FR-4.3) or the
    /// Watch-ingested workout this came from (FR-2.1). Used for de-dup.
    public var healthKitWorkoutUUID: UUID?
    public var updatedAt: Date = Date()
    public var originDevice: String = ""

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.session)
    public var sets: [SetEntry]? = []

    public init(id: UUID = UUID(),
                title: String = "",
                date: Date = Date(),
                notes: String? = nil,
                templateName: String? = nil,
                healthKitWorkoutUUID: UUID? = nil,
                updatedAt: Date = Date(),
                originDevice: String = "") {
        self.id = id
        self.title = title
        self.date = date
        self.notes = notes
        self.templateName = templateName
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    /// Sets in logged order.
    public var orderedSets: [SetEntry] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    /// Distinct exercises in this session, in first-appearance order.
    public var exercisesInOrder: [Exercise] {
        var seen = Set<UUID>()
        var result: [Exercise] = []
        for set in orderedSets {
            guard let ex = set.exercise else { continue }
            if seen.insert(ex.id).inserted { result.append(ex) }
        }
        return result
    }

    /// Total working volume (kg) across all non-warmup sets.
    public var totalVolume: Double {
        orderedSets.filter { !$0.isWarmup }
            .reduce(0) { $0 + WorkoutMath.volume(weight: $1.weight, reps: $1.reps) }
    }
}

// MARK: SetEntry

@Model
public final class SetEntry {
    public var id: UUID = UUID()
    /// Canonical weight in kilograms. UI converts to/from the display unit.
    public var weight: Double = 0
    public var reps: Int = 0
    public var order: Int = 0
    public var isWarmup: Bool = false
    /// Rate of perceived exertion, 1...10 (FR-1.2). Optional.
    public var rpe: Double?
    public var note: String?
    public var completedAt: Date = Date()
    public var updatedAt: Date = Date()
    public var originDevice: String = ""

    // To-one relationships (inverses declared on the parents above).
    public var session: WorkoutSession?
    public var exercise: Exercise?

    public init(id: UUID = UUID(),
                weight: Double = 0,
                reps: Int = 0,
                order: Int = 0,
                isWarmup: Bool = false,
                rpe: Double? = nil,
                note: String? = nil,
                completedAt: Date = Date(),
                updatedAt: Date = Date(),
                originDevice: String = "",
                session: WorkoutSession? = nil,
                exercise: Exercise? = nil) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.order = order
        self.isWarmup = isWarmup
        self.rpe = rpe
        self.note = note
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.originDevice = originDevice
        self.session = session
        self.exercise = exercise
    }
}

// MARK: Templates (FR-1.6)

@Model
public final class SessionTemplate {
    public var id: UUID = UUID()
    public var name: String = ""
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var originDevice: String = ""

    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    public var exercises: [TemplateExercise]? = []

    public init(id: UUID = UUID(),
                name: String = "",
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                originDevice: String = "") {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    public var orderedExercises: [TemplateExercise] {
        (exercises ?? []).sorted { $0.order < $1.order }
    }
}

@Model
public final class TemplateExercise {
    public var id: UUID = UUID()
    public var exerciseName: String = ""
    public var order: Int = 0
    public var targetSets: Int = 3
    public var targetReps: Int = 8
    public var template: SessionTemplate?

    public init(id: UUID = UUID(),
                exerciseName: String = "",
                order: Int = 0,
                targetSets: Int = 3,
                targetReps: Int = 8,
                template: SessionTemplate? = nil) {
        self.id = id
        self.exerciseName = exerciseName
        self.order = order
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.template = template
    }
}

// MARK: Cardio (FR-2 / FR-5.3)

@Model
public final class CardioWorkout {
    public var id: UUID = UUID()
    /// Raw value of `CardioType`.
    public var type: String = CardioType.other.rawValue
    public var start: Date = Date()
    public var end: Date?
    /// Meters.
    public var distance: Double?
    public var activeEnergy: Double?      // kcal
    public var avgHeartRate: Double?      // bpm
    public var maxHeartRate: Double?      // bpm
    /// Raw value of `CardioSource`.
    public var source: String = CardioSource.iphone.rawValue
    public var healthKitWorkoutUUID: UUID?
    public var notes: String?
    public var updatedAt: Date = Date()
    public var originDevice: String = ""

    @Relationship(deleteRule: .cascade, inverse: \HRSample.cardio)
    public var hrSamples: [HRSample]? = []

    @Relationship(deleteRule: .cascade, inverse: \RouteSample.cardio)
    public var routeSamples: [RouteSample]? = []

    public init(id: UUID = UUID(),
                type: CardioType = .other,
                start: Date = Date(),
                end: Date? = nil,
                distance: Double? = nil,
                activeEnergy: Double? = nil,
                avgHeartRate: Double? = nil,
                maxHeartRate: Double? = nil,
                source: CardioSource = .iphone,
                healthKitWorkoutUUID: UUID? = nil,
                notes: String? = nil,
                updatedAt: Date = Date(),
                originDevice: String = "") {
        self.id = id
        self.type = type.rawValue
        self.start = start
        self.end = end
        self.distance = distance
        self.activeEnergy = activeEnergy
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.source = source.rawValue
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.notes = notes
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    public var typeValue: CardioType {
        get { CardioType(rawValue: type) ?? .other }
        set { type = newValue.rawValue }
    }

    public var sourceValue: CardioSource {
        get { CardioSource(rawValue: source) ?? .iphone }
        set { source = newValue.rawValue }
    }

    public var duration: TimeInterval {
        guard let end else { return 0 }
        return end.timeIntervalSince(start)
    }

    public var orderedHRSamples: [HRSample] {
        (hrSamples ?? []).sorted { $0.t < $1.t }
    }

    public var orderedRouteSamples: [RouteSample] {
        (routeSamples ?? []).sorted { $0.t < $1.t }
    }
}

public enum CardioType: String, CaseIterable, Codable, Sendable, Identifiable {
    case run, cycle, swim, boxing, hiit, walk, rowing, other
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .run: return "Run"
        case .cycle: return "Cycle"
        case .swim: return "Swim"
        case .boxing: return "Boxing"
        case .hiit: return "HIIT"
        case .walk: return "Walk"
        case .rowing: return "Rowing"
        case .other: return "Other"
        }
    }
    public var symbol: String {
        switch self {
        case .run: return "figure.run"
        case .cycle: return "figure.outdoor.cycle"
        case .swim: return "figure.pool.swim"
        case .boxing: return "figure.boxing"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .walk: return "figure.walk"
        case .rowing: return "figure.rower"
        case .other: return "figure.mixed.cardio"
        }
    }
    /// Outdoor types benefit from GPS route tracking (FR-2.2).
    public var usesGPS: Bool {
        switch self {
        case .run, .cycle, .walk: return true
        default: return false
        }
    }
}

public enum CardioSource: String, CaseIterable, Codable, Sendable {
    case watch, iphone, strap, machine
}

@Model
public final class HRSample {
    public var id: UUID = UUID()
    /// Seconds since workout start.
    public var t: TimeInterval = 0
    public var bpm: Double = 0
    public var cardio: CardioWorkout?

    public init(id: UUID = UUID(), t: TimeInterval = 0, bpm: Double = 0, cardio: CardioWorkout? = nil) {
        self.id = id
        self.t = t
        self.bpm = bpm
        self.cardio = cardio
    }
}

@Model
public final class RouteSample {
    public var id: UUID = UUID()
    public var t: TimeInterval = 0
    public var lat: Double = 0
    public var lon: Double = 0
    public var elevation: Double = 0
    public var cardio: CardioWorkout?

    public init(id: UUID = UUID(), t: TimeInterval = 0, lat: Double = 0, lon: Double = 0, elevation: Double = 0, cardio: CardioWorkout? = nil) {
        self.id = id
        self.t = t
        self.lat = lat
        self.lon = lon
        self.elevation = elevation
        self.cardio = cardio
    }
}

// MARK: HRM Device (FR-4.4)

@Model
public final class HRMDevice {
    /// CoreBluetooth peripheral identifier.
    public var id: UUID = UUID()
    public var name: String = ""
    public var lastBattery: Int?
    public var isDefault: Bool = false
    public var lastConnectedAt: Date?
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(),
                name: String = "",
                lastBattery: Int? = nil,
                isDefault: Bool = false,
                lastConnectedAt: Date? = nil,
                updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.lastBattery = lastBattery
        self.isDefault = isDefault
        self.lastConnectedAt = lastConnectedAt
        self.updatedAt = updatedAt
    }
}
