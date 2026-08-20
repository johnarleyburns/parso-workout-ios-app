import Foundation
import SwiftData

/// Encodes `[String]` as a single delimited `String` for SwiftData storage.
/// A plain `[String]` attribute is persisted via the legacy transformable,
/// which logs "Could not materialize Objective-C class named Array" faults and
/// the `NSKeyedUnarchiveFromData` deprecation. Storing a String avoids both.
/// The delimiter is U+0001 (Start of Heading), which never occurs in our data.
enum StringArray {
    static let separator = "\u{1}"
    static func encode(_ values: [String]) -> String { values.joined(separator: separator) }
    static func decode(_ raw: String) -> [String] {
        raw.isEmpty ? [] : raw.components(separatedBy: separator)
    }
}

/// The complete coach prescription for one exercise. Stored as JSON in the
/// session so each exercise can retain its own set ladder and load.
public struct PlannedSetPrescription: Codable, Equatable, Sendable {
    public var targetReps: Int
    public var targetWeightKg: Double?

    public init(targetReps: Int, targetWeightKg: Double? = nil) {
        self.targetReps = targetReps
        self.targetWeightKg = targetWeightKg
    }
}

public struct PlannedExercisePrescription: Codable, Equatable, Sendable {
    public var exerciseName: String
    public var sets: [PlannedSetPrescription]

    public init(exerciseName: String, sets: [PlannedSetPrescription]) {
        self.exerciseName = exerciseName
        self.sets = sets
    }
}

/// One performer's prescription for a session. `performerID` is a `Person.id`
/// UUID string; nil means the device owner. Additive (decision **D11**): the
/// owner's plan continues to live in `plannedPrescriptions`, and any performer
/// without an entry here falls back to it, so every legacy session and every
/// older JSON export keeps working untouched.
public struct PlannedPerformerPrescription: Codable, Equatable, Sendable {
    public var performerID: String?
    public var exercises: [PlannedExercisePrescription]

    public init(performerID: String?, exercises: [PlannedExercisePrescription]) {
        self.performerID = performerID
        self.exercises = exercises
    }
}

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
    /// Muscle-group tags (e.g. "chest"). Delimited-String storage (see `StringArray`).
    private var muscleGroupsData: String = ""
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
    /// Canonical muscle ids + search tokens; delimited-String storage.
    private var primaryMusclesData: String = ""
    private var secondaryMusclesData: String = ""
    private var searchKeywordsData: String = ""
    // P2 (CC0 library) facets — public-domain instructions/image/level from
    // free-exercise-db. Optional/defaulted for CloudKit + back-compat.
    /// Step-by-step instructions; delimited-String storage (see `StringArray`).
    private var instructionsData: String = ""
    /// Bundled demonstration-image asset id (the source exercise id), if any.
    public var imageName: String?
    /// Difficulty: beginner / intermediate / expert.
    public var level: String?
    public var isFavorite: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var originDevice: String = ""
    /// Default load-accounting mode for sets of this exercise. Raw `LoadAccountingMode`.
    public var loadAccountingMode: String?
    /// Default bar weight in kg (canonical). For barbell exercises, this is the bar
    /// weight added to the user-entered plate load. Default 0 = not set / no bar.
    public var defaultBarWeightKg: Double = 0
    /// True when the user has explicitly set the accounting mode, overriding the seed.
    public var loadAccountingUserOverride: Bool = false

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
                instructions: [String] = [],
                imageName: String? = nil,
                level: String? = nil,
                isFavorite: Bool = false,
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                originDevice: String = "",
                loadAccountingMode: LoadAccountingMode? = nil,
                defaultBarWeightKg: Double = 0,
                loadAccountingUserOverride: Bool = false) {
        self.id = id
        self.name = name
        self.category = category?.rawValue
        self.muscleGroupsData = StringArray.encode(muscleGroups)
        self.isCustom = isCustom
        self.equipment = equipment?.rawValue
        self.isLateral = isLateral
        self.mechanics = mechanics?.rawValue
        self.force = force?.rawValue
        self.primaryMusclesData = StringArray.encode(primaryMuscles)
        self.secondaryMusclesData = StringArray.encode(secondaryMuscles)
        self.searchKeywordsData = StringArray.encode(searchKeywords)
        self.instructionsData = StringArray.encode(instructions)
        self.imageName = imageName
        self.level = level
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originDevice = originDevice
        self.loadAccountingMode = loadAccountingMode?.rawValue
        self.defaultBarWeightKg = defaultBarWeightKg
        self.loadAccountingUserOverride = loadAccountingUserOverride
    }

    public var muscleGroups: [String] {
        get { StringArray.decode(muscleGroupsData) }
        set { muscleGroupsData = StringArray.encode(newValue) }
    }
    public var primaryMuscles: [String] {
        get { StringArray.decode(primaryMusclesData) }
        set { primaryMusclesData = StringArray.encode(newValue) }
    }
    public var secondaryMuscles: [String] {
        get { StringArray.decode(secondaryMusclesData) }
        set { secondaryMusclesData = StringArray.encode(newValue) }
    }
    public var searchKeywords: [String] {
        get { StringArray.decode(searchKeywordsData) }
        set { searchKeywordsData = StringArray.encode(newValue) }
    }
    public var instructions: [String] {
        get { StringArray.decode(instructionsData) }
        set { instructionsData = StringArray.encode(newValue) }
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

    public var loadAccountingModeValue: LoadAccountingMode? {
        get { loadAccountingMode.flatMap(LoadAccountingMode.init(rawValue:)) }
        set { loadAccountingMode = newValue?.rawValue }
    }

    /// Derives the default load-accounting mode from equipment, isLateral, and
    /// exercise name. Returns nil for equipment types that don't need accounting
    /// (machine, cable, kettlebell, band).
    public var resolvedLoadAccountingMode: LoadAccountingMode? {
        if let mode = loadAccountingModeValue { return mode }
        return Exercise.defaultLoadAccountingMode(equipment: equipmentValue, isLateral: isLateral, name: name)
    }

    /// Seeds the default accounting mode from equipment + name heuristics.
    /// Returns nil for equipment where the raw entered weight is already correct.
    public static func defaultLoadAccountingMode(equipment: Equipment?, isLateral: Bool, name: String) -> LoadAccountingMode? {
        guard let equipment else { return nil }
        switch equipment {
        case .barbell, .smith:
            return .barbell
        case .bodyweight:
            return .bodyweight
        case .dumbbell:
            if isLateral { return .isolateralDumbbell }
            if Exercise.isSingleDumbbellMovement(name) { return .singleDumbbell }
            return .dualDumbbell
        case .kettlebell:
            if isLateral { return .isolateralKettlebell }
            if Exercise.isSingleKettlebellMovement(name) { return .singleKettlebell }
            // Phase 4: most two-kettlebell movements (clean, press, front squat, etc.)
            // use dual-kettlebell accounting — entered weight = one bell, doubled.
            return .dualKettlebell
        case .machine, .cable, .band, .plyometric:
            return nil
        }
    }

    /// Standard bar weight in kg (20.4117 kg ≈ 45 lb).
    public static let defaultBarWeightKg: Double = 45.0 / 2.2046226218487757

    /// Returns the effective default bar weight for this exercise.
    public var effectiveDefaultBarWeightKg: Double {
        if defaultBarWeightKg > 0 { return defaultBarWeightKg }
        if equipmentValue == .barbell { return Exercise.defaultBarWeightKg }
        return 0
    }

    /// Computes the prospective effective load for a new set with the given
    /// user-entered weight, using this exercise's accounting defaults.
    public func prospectiveEffectiveLoadKg(rawWeightKg: Double, barWeightKg: Double? = nil) -> Double {
        guard let mode = resolvedLoadAccountingMode else { return rawWeightKg }
        let bar = barWeightKg ?? effectiveDefaultBarWeightKg
        switch mode {
        case .barbell: return (rawWeightKg + bar)
        case .bodyweight: return rawWeightKg
        case .dualDumbbell: return rawWeightKg * 2.0
        case .singleDumbbell: return rawWeightKg
        case .isolateralDumbbell: return rawWeightKg * 2.0
        case .dualKettlebell: return rawWeightKg * 2.0
        case .singleKettlebell: return rawWeightKg
        case .isolateralKettlebell: return rawWeightKg * 2.0
        }
    }

    /// Known single-dumbbell movement name patterns (case-insensitive).
    private static let singleDumbbellPatterns: [String] = [
        "skullcrusher", "goblet", "concentration curl", "kickback",
        "one-arm", "single-arm", "single arm", "overhead tricep extension",
        "tate press", "pull-over", "pullover"
    ]

    private static func isSingleDumbbellMovement(_ name: String) -> Bool {
        let lower = name.lowercased()
        return singleDumbbellPatterns.contains { lower.contains($0) }
    }

    /// Known single-kettlebell movement name patterns (case-insensitive).
    /// Phase 4: patterns that indicate the exercise uses one kettlebell at a time
    /// (typically unilateral or alternating movements).
    private static let singleKettlebellPatterns: [String] = [
        "single-arm kettlebell", "single arm kettlebell",
        "one-arm kettlebell", "one arm kettlebell",
        "kettlebell swing", "kettlebell snatch",
        "turkish get-up", "kettlebell halo",
        "kettlebell windmill",
    ]

    private static func isSingleKettlebellMovement(_ name: String) -> Bool {
        let lower = name.lowercased()
        return singleKettlebellPatterns.contains { lower.contains($0) }
    }

    public static let cnsLiftNames: Set<String> = [
        "Clean and Jerk", "Snatch", "Power Clean", "Clean and Press",
        "Clean", "Turkish Get-Up", "Kettlebell Clean", "Kettlebell Swing"
    ]
}

/// Coarse training split categories (FR-1.1).
public enum ExerciseCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case push, pull, legs, core, cardio, plyometrics, other
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .push: return "Push"
        case .pull: return "Pull"
        case .legs: return "Legs"
        case .core: return "Core"
        case .cardio: return "Cardio"
        case .plyometrics: return "Plyometrics"
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
    /// When the workout was finalized (field-testing §02). Optional for
    /// CloudKit + back-compat; nil means in-progress or a legacy session.
    public var endedAt: Date?
    /// Exercise names pre-loaded when reusing a past workout (field-testing §04,
    /// decision #16). Delimited-String storage (see `StringArray`).
    private var plannedExerciseNamesData: String = ""
    /// Chosen rep scheme (a per-set ladder, e.g. [12,10,8]) applied to every
    /// planned movement when launched from a flexible library template
    /// (feedback batch 3). Empty for fixed presets / ad-hoc sessions.
    /// Delimited-String storage (see `StringArray`).
    private var plannedRepLadderData: String = ""
    /// JSON encoded per-exercise/per-set prescription. Additive and defaulted
    /// for CloudKit and legacy sessions.
    private var plannedPrescriptionsData: String = ""
    /// JSON encoded per-performer prescriptions (field test 2026-08-18 #4,
    /// decision **D11**). Additive and defaulted for CloudKit and legacy
    /// sessions; `plannedPrescriptions` stays the owner's plan and the fallback.
    private var plannedPerformerPrescriptionsData: String = ""
    public var notes: String?
    /// Name of the template this session was started from, if any (FR-1.6).
    public var templateName: String?
    /// Stable key of the `WorkoutPlan` that launched this session (round4b §B-1):
    /// a strength preset ("preset-5x5"). Resolved via `PlanCatalog`; nil for
    /// ad-hoc sessions and legacy keys (e.g. a removed CrossFit benchmark).
    /// Additive + optional for CloudKit + back-compat.
    public var planKey: String?
    /// Links to the summary HKWorkout written for this session (FR-4.3) or the
    /// Watch-ingested workout this came from (FR-2.1). Used for de-dup.
    public var healthKitWorkoutUUID: UUID?
    /// Manually logged after the fact, rather than recorded live (feedback batch 6).
    /// History shows a "Logged" tag. Additive/defaulted for CloudKit + back-compat.
    public var isLogged: Bool = false
    public var deletedAt: Date?
    /// Actual warm-up / cool-down time consumed for this session, in seconds; 0 when
    /// none was run (feedback batch 6). Surfaced in the summary alongside duration.
    public var warmupSeconds: Double = 0
    public var cooldownSeconds: Double = 0
    /// Working load (canonical kg) prescribed by the coach when this session was
    /// launched via "Do this workout" (strength-pivot P5.3); 0 = none. Pre-fills the
    /// set keypad for the prescribed movement. Additive/defaulted for CloudKit + back-compat.
    public var prescribedLoadKg: Double = 0
    /// UUID strings of active training partners for this session. When empty,
    /// all known partners are shown (backward-compat). Delimited-String storage.
    private var activePartnerIDsData: String = ""
    public var activePartnerIDs: [String] {
        get { StringArray.decode(activePartnerIDsData) }
        set { activePartnerIDsData = StringArray.encode(newValue) }
    }
    public var updatedAt: Date = Date()
    public var originDevice: String = ""

    @Relationship(deleteRule: .cascade, inverse: \SetEntry.session)
    public var sets: [SetEntry]? = []

    public init(id: UUID = UUID(),
                title: String = "",
                date: Date = Date(),
                endedAt: Date? = nil,
                notes: String? = nil,
                templateName: String? = nil,
                healthKitWorkoutUUID: UUID? = nil,
                isLogged: Bool = false,
                warmupSeconds: Double = 0,
                cooldownSeconds: Double = 0,
                activePartnerIDsData: String = "",
                updatedAt: Date = Date(),
                originDevice: String = "") {
        self.id = id
        self.title = title
        self.date = date
        self.endedAt = endedAt
        self.notes = notes
        self.templateName = templateName
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.isLogged = isLogged
        self.warmupSeconds = warmupSeconds
        self.cooldownSeconds = cooldownSeconds
        self.activePartnerIDsData = activePartnerIDsData
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    public var plannedExerciseNames: [String] {
        get { StringArray.decode(plannedExerciseNamesData) }
        set { plannedExerciseNamesData = StringArray.encode(newValue) }
    }

    /// The chosen per-set rep ladder for a flexible-template launch (e.g. 12-10-8).
    public var plannedRepLadder: [Int] {
        get { StringArray.decode(plannedRepLadderData).compactMap(Int.init) }
        set { plannedRepLadderData = StringArray.encode(newValue.map(String.init)) }
    }

    /// Full prescription when available; otherwise a backward-compatible
    /// synthesis from the legacy session fields.
    public var plannedPrescriptions: [PlannedExercisePrescription] {
        get {
            if !plannedPrescriptionsData.isEmpty,
               let data = plannedPrescriptionsData.data(using: .utf8),
               let value = try? JSONDecoder().decode([PlannedExercisePrescription].self, from: data) {
                return value
            }
            guard !plannedExerciseNames.isEmpty, !plannedRepLadder.isEmpty else { return [] }
            return plannedExerciseNames.map { name in
                PlannedExercisePrescription(
                    exerciseName: name,
                    sets: plannedRepLadder.map { PlannedSetPrescription(targetReps: $0, targetWeightKg: prescribedLoadKg > 0 ? prescribedLoadKg : nil) })
            }
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else {
                plannedPrescriptionsData = ""
                return
            }
            plannedPrescriptionsData = String(decoding: data, as: UTF8.self)
        }
    }

    /// Every performer's prescription, including the owner's (`performerID` nil).
    /// Empty for any session planned before this field existed.
    public var plannedPerformerPrescriptions: [PlannedPerformerPrescription] {
        get {
            guard !plannedPerformerPrescriptionsData.isEmpty,
                  let data = plannedPerformerPrescriptionsData.data(using: .utf8),
                  let value = try? JSONDecoder().decode([PlannedPerformerPrescription].self, from: data)
            else { return [] }
            return value
        }
        set {
            guard !newValue.isEmpty, let data = try? JSONEncoder().encode(newValue) else {
                plannedPerformerPrescriptionsData = ""
                return
            }
            plannedPerformerPrescriptionsData = String(decoding: data, as: UTF8.self)
        }
    }

    /// The sets one performer was **explicitly planned** for on one movement, or
    /// nil when nothing was planned for them there. Unlike
    /// `plannedPrescriptions(forPerformerID:)` this never substitutes the owner's
    /// plan, so a caller can tell "the user asked for this" from "nobody said".
    /// That distinction is what lets an entered plan outrank logged history
    /// (field test 2026-08-19 #1).
    public func explicitPlannedSets(forPerformerID id: UUID?,
                                    exerciseName: String) -> [PlannedSetPrescription]? {
        let match: [PlannedExercisePrescription]
        if let stored = plannedPerformerPrescriptions.first(where: { $0.performerID == id?.uuidString }) {
            match = stored.exercises
        } else if id == nil {
            match = plannedPrescriptions
        } else {
            return nil
        }
        let sets = match.first {
            $0.exerciseName.caseInsensitiveCompare(exerciseName) == .orderedSame
        }?.sets
        return (sets?.isEmpty ?? true) ? nil : sets
    }

    /// The prescription for one performer, falling back to the owner's plan when
    /// that performer has no stored entry (legacy sessions, or a partner added
    /// after planning).
    public func plannedPrescriptions(forPerformerID id: UUID?) -> [PlannedExercisePrescription] {
        if let match = plannedPerformerPrescriptions.first(where: { $0.performerID == id?.uuidString }) {
            return match.exercises
        }
        return plannedPrescriptions
    }

    /// Sets in logged order.
    public var orderedSets: [SetEntry] {
        (sets ?? []).sorted { $0.order < $1.order }
    }

    /// Wall-clock duration from start to finalize (field-testing §02). Falls
    /// back to the span between first and last logged set when `endedAt` is
    /// absent (legacy sessions), else zero.
    public var duration: TimeInterval {
        if let endedAt { return max(0, endedAt.timeIntervalSince(date)) }
        let stamps = orderedSets.map(\.completedAt)
        guard let first = stamps.min(), let last = stamps.max() else { return 0 }
        return max(0, last.timeIntervalSince(first))
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

    /// SF Symbol for history rows (feedback batch 6): an all-bodyweight session →
    /// the traditional-strength figure, otherwise the dumbbell. Gives strength
    /// rows the leading glyph they lacked. Legacy CrossFit sessions (logged before
    /// the feature was removed) still map to the functional-training glyph.
    public var symbol: String {
        if title.localizedCaseInsensitiveContains("crossfit") {
            return "figure.strengthtraining.functional"
        }
        let working = orderedSets.filter { !$0.isWarmup }
        if !working.isEmpty, working.allSatisfy({ $0.usesBodyweight }) {
            return "figure.strengthtraining.traditional"
        }
        return "dumbbell"
    }

    /// Single source of truth for "workout in progress" (field-test-fixes Phase A).
    /// Ended implies finalized; deleted is soft-deleted; isLogged is a manual
    /// after-the-fact log. Both the coach pipeline and the Resume card use this
    /// predicate exclusively.
    public var isResumable: Bool {
        endedAt == nil && deletedAt == nil && !isLogged
    }

    /// Total working volume (kg) across the owner's non-warmup sets. Partner
    /// sets are excluded (field-testing §04, decision #13). Uses effective load
    /// for new-accounting sets, raw weight for legacy sets.
    public var totalVolume: Double {
        orderedSets.filter { !$0.isWarmup && $0.isOwnerSet }
            .reduce(0) { $0 + WorkoutMath.volume(weight: $1.effectiveLoadKg, reps: $1.reps) }
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
    /// A bodyweight set (feedback batch 3): the movement is performed at body
    /// weight and `weight` holds only the *added* external load (0 = pure
    /// bodyweight, e.g. a strict pull-up; >0 = a weighted variant like a
    /// weighted dip). Optional/defaulted for CloudKit + back-compat.
    public var usesBodyweight: Bool = false
    /// Rate of perceived exertion, 1...10 (FR-1.2). Optional.
    public var rpe: Double?
    public var note: String?
    public var completedAt: Date = Date()
    public var updatedAt: Date = Date()
    public var originDevice: String = ""
    /// Snapshotted bar weight in kg for barbell exercises. The bar weight added to
    /// the user-entered plate load when computing effective load. Default 0.
    public var barWeightKg: Double = 0
    /// Snapshotted load multiplier (default 1.0). Used for dumbbell pairing, etc.
    public var loadMultiplier: Double = 1.0
    /// Snapshotted load-accounting mode. Raw `LoadAccountingMode`. nil = legacy set
    /// without accounting metadata (effective load = weight).
    public var loadAccountingMode: String?

    // To-one relationships (inverses declared on the parents above).
    public var session: WorkoutSession?
    public var exercise: Exercise?
    /// Who performed the set (field-testing §04). nil ⇒ the owner ("me").
    /// Partner sets are kept distinct: excluded from the owner's PRs/volume/
    /// trends and never written to the owner's HealthKit (decision #13).
    public var performedBy: Person?

    public init(id: UUID = UUID(),
                weight: Double = 0,
                reps: Int = 0,
                order: Int = 0,
                isWarmup: Bool = false,
                usesBodyweight: Bool = false,
                rpe: Double? = nil,
                note: String? = nil,
                completedAt: Date = Date(),
                updatedAt: Date = Date(),
                originDevice: String = "",
                session: WorkoutSession? = nil,
                exercise: Exercise? = nil,
                performedBy: Person? = nil,
                barWeightKg: Double = 0,
                loadMultiplier: Double = 1.0,
                loadAccountingMode: String? = nil) {
        self.id = id
        self.weight = weight
        self.reps = reps
        self.order = order
        self.isWarmup = isWarmup
        self.usesBodyweight = usesBodyweight
        self.rpe = rpe
        self.note = note
        self.completedAt = completedAt
        self.updatedAt = updatedAt
        self.originDevice = originDevice
        self.session = session
        self.exercise = exercise
        self.performedBy = performedBy
        self.barWeightKg = barWeightKg
        self.loadMultiplier = loadMultiplier
        self.loadAccountingMode = loadAccountingMode
    }

    /// True when the set belongs to the device owner (nobody attributed, or the
    /// "me" person). Partner sets are false.
    public var isOwnerSet: Bool {
        guard let p = performedBy else { return true }
        return p.isMe
    }

    public var loadAccountingModeValue: LoadAccountingMode? {
        get { loadAccountingMode.flatMap(LoadAccountingMode.init(rawValue:)) }
        set { loadAccountingMode = newValue?.rawValue }
    }

    /// The effective load in kg for calculations (PRs, volume, trends, etc.).
    /// For new-accounting sets, transforms the user-entered weight by the
    /// accounting mode, bar weight, and multiplier. Legacy sets without
    /// accounting metadata return the stored weight as-is.
    public var effectiveLoadKg: Double {
        guard let mode = loadAccountingModeValue else { return weight }
        switch mode {
        case .barbell:
            return (weight + barWeightKg) * loadMultiplier
        case .bodyweight:
            return weight * loadMultiplier
        case .dualDumbbell:
            return weight * 2.0
        case .singleDumbbell:
            return weight * 1.0
        case .isolateralDumbbell:
            return weight * 2.0
        case .dualKettlebell:
            return weight * 2.0
        case .singleKettlebell:
            return weight * 1.0
        case .isolateralKettlebell:
            return weight * 2.0
        }
    }
}

// MARK: Person (training partners, field-testing §04)

@Model
public final class Person {
    public var id: UUID = UUID()
    public var name: String = ""
    /// The device owner. Exactly one Person should be `isMe`; nil attribution
    /// also means the owner.
    public var isMe: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var originDevice: String = ""

    @Relationship(deleteRule: .nullify, inverse: \SetEntry.performedBy)
    public var sets: [SetEntry]? = []

    public init(id: UUID = UUID(),
                name: String = "",
                isMe: Bool = false,
                createdAt: Date = Date(),
                updatedAt: Date = Date(),
                originDevice: String = "") {
        self.id = id
        self.name = name
        self.isMe = isMe
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.originDevice = originDevice
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
    /// Swimming (round4b feedback #3): completed laps and the lap goal, if set.
    /// Optional/additive for CloudKit + back-compat; nil for non-swim workouts.
    public var laps: Int?
    public var targetLaps: Int?
    /// Optional distance goal in meters for a run/walk/cycle (feedback batch 8): the
    /// user can target e.g. 5K/10K when starting; the live screen shows progress and
    /// history shows whether it was met. Additive/optional for CloudKit + back-compat.
    public var targetDistance: Double?
    /// Raw value of `CardioSource`.
    public var source: String = CardioSource.iphone.rawValue
    public var healthKitWorkoutUUID: UUID?
    public var notes: String?
    /// Manually logged after the fact, rather than recorded live (feedback batch 6).
    /// History shows a "Logged" tag. Additive/defaulted for CloudKit + back-compat.
    public var isLogged: Bool = false
    public var deletedAt: Date?
    /// Free-text label for an "Other Cardio" workout (e.g. "Rowing", "Yardwork");
    /// nil ⇒ use the type's display name (feedback batch 6).
    public var customTitle: String?
    /// Preserved HKWorkoutActivityType for imported workouts so the coach can
    /// distinguish imported strength from unknown cardio. nil for app-authored
    /// workouts. Additive/defaulted for CloudKit + back-compat.
    public var importedWorkoutKindRaw: String?
    public var updatedAt: Date = Date()
    public var originDevice: String = ""
    /// Interval (HIIT/boxing) structure as JSON (`IntervalSummary`), so history can
    /// show rounds + work/rest + warm-up/cool-down. Additive; "" for non-interval
    /// workouts (feedback batch 4 / roadmap P5).
    public var intervalDetailData: String = ""

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
                laps: Int? = nil,
                targetLaps: Int? = nil,
                targetDistance: Double? = nil,
                source: CardioSource = .iphone,
                healthKitWorkoutUUID: UUID? = nil,
                notes: String? = nil,
                 isLogged: Bool = false,
                 customTitle: String? = nil,
                 importedWorkoutKind: ImportedWorkoutKind? = nil,
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
        self.laps = laps
        self.targetLaps = targetLaps
        self.targetDistance = targetDistance
        self.source = source.rawValue
        self.healthKitWorkoutUUID = healthKitWorkoutUUID
        self.notes = notes
        self.isLogged = isLogged
        self.customTitle = customTitle
        self.importedWorkoutKindRaw = importedWorkoutKind?.rawValue
        self.updatedAt = updatedAt
        self.originDevice = originDevice
    }

    /// Display title — the free-text label for an "Other Cardio" workout, else the
    /// type's name (feedback batch 6).
    public var displayTitle: String {
        if let t = customTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        return typeValue.displayName
    }

    public var typeValue: CardioType {
        get { CardioType(rawValue: type) ?? .other }
        set { type = newValue.rawValue }
    }

    public var sourceValue: CardioSource {
        get { CardioSource(rawValue: source) ?? .iphone }
        set { source = newValue.rawValue }
    }

    public var importedWorkoutKind: ImportedWorkoutKind? {
        get { importedWorkoutKindRaw.flatMap(ImportedWorkoutKind.init(rawValue:)) }
        set { importedWorkoutKindRaw = newValue?.rawValue }
    }

    public var duration: TimeInterval {
        guard let end else { return 0 }
        return end.timeIntervalSince(start)
    }

    /// Typed view over `intervalDetailData` (JSON in/out); nil when absent.
    public var intervalSummary: IntervalSummary? {
        get {
            guard !intervalDetailData.isEmpty,
                  let data = intervalDetailData.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(IntervalSummary.self, from: data)
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue),
                  let json = String(data: data, encoding: .utf8) else {
                intervalDetailData = ""
                return
            }
            intervalDetailData = json
        }
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

// MARK: - Readiness check-in (recovery-aware redesign)

/// Optional once-daily self-assessment. Never required — missing readiness
/// lowers Coach's confidence and keeps conservative time gates.
@Model
public final class ReadinessEntry {
    public var id: UUID = UUID()
    public var date: Date = Date()
    /// 1 (very sore) to 5 (no soreness at all).
    public var muscleSoreness: Int = 3
    /// 1 (exhausted) to 5 (full of energy).
    public var fatigueEnergy: Int = 3
    /// 1 (terrible) to 5 (great).
    public var sleepQuality: Int = 3
    /// 1 (very stressed) to 5 (completely relaxed).
    public var stressMood: Int = 3
    /// Safety flag: the user reports pain or illness concern. If true, Coach
    /// suppresses hard recommendations and shows neutral safety copy.
    public var hasPainOrIllnessConcern: Bool = false
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), date: Date = Date(),
                muscleSoreness: Int = 3, fatigueEnergy: Int = 3,
                sleepQuality: Int = 3, stressMood: Int = 3,
                hasPainOrIllnessConcern: Bool = false, updatedAt: Date = Date()) {
        self.id = id
        self.date = date
        self.muscleSoreness = muscleSoreness
        self.fatigueEnergy = fatigueEnergy
        self.sleepQuality = sleepQuality
        self.stressMood = stressMood
        self.hasPainOrIllnessConcern = hasPainOrIllnessConcern
        self.updatedAt = updatedAt
    }
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
