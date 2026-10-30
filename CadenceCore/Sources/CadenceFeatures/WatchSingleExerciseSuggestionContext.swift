import Foundation
import CadenceCore

/// Versioned, property-list-safe snapshot of everything
/// `SuggestedWorkoutGenerator.suggestSingleExercise` needs, so the Watch can run
/// it offline. Pure value mirrors only: no SwiftData models cross this boundary,
/// enums travel as raw strings and are decoded defensively, and a malformed or
/// future payload yields `nil` rather than an invented fallback policy.
///
/// Contract only — nothing emits or consumes `WatchSync.Key.singleExerciseSuggestionContext` yet.
public struct WatchSingleExerciseSuggestionContext: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    /// Upper bounds that keep a corrupt payload from becoming unbounded work.
    public static let maxCandidates = 6_000
    public static let maxMusclesPerCandidate = 40
    public static let maxFacetsPerCandidate = 40
    public static let maxStringLength = 256
    public static let maxHistoryDataBytes = 512 * 1024
    public static let maxSetsPerExercise = 12
    public static let maxSetsPerMuscle = 1_000.0

    public var version: Int
    public var generatedAt: Date
    public var baseInput: Input

    public init(version: Int = WatchSingleExerciseSuggestionContext.currentVersion,
                generatedAt: Date,
                baseInput: Input) {
        self.version = version
        self.generatedAt = generatedAt
        self.baseInput = baseInput
    }

    public struct Input: Codable, Equatable, Sendable {
        public var completedSetsByMuscle: [String: Double]
        public var candidates: [Candidate]
        public var historyData: Data?
        public var historyWorkoutCount: Int
        public var historyWorkingSetCount: Int
        public var recentlyCompletedCandidateIDs: Set<String>
        public var trackedGroupIDs: Set<String>
        public var preferredSetsPerExercise: Int
        public var mostRecentExerciseWorkingSets: Int?
        public var trainingGoalRawValue: String
        public var preferredStyleRawValue: String
        public var engineContext: EngineContext

        public init(completedSetsByMuscle: [String: Double],
                    candidates: [Candidate],
                    historyData: Data? = nil,
                    historyWorkoutCount: Int = 0,
                    historyWorkingSetCount: Int = 0,
                    recentlyCompletedCandidateIDs: Set<String> = [],
                    trackedGroupIDs: Set<String>,
                    preferredSetsPerExercise: Int,
                    mostRecentExerciseWorkingSets: Int? = nil,
                    trainingGoalRawValue: String,
                    preferredStyleRawValue: String,
                    engineContext: EngineContext) {
            self.completedSetsByMuscle = completedSetsByMuscle
            self.candidates = candidates
            self.historyData = historyData
            self.historyWorkoutCount = historyWorkoutCount
            self.historyWorkingSetCount = historyWorkingSetCount
            self.recentlyCompletedCandidateIDs = recentlyCompletedCandidateIDs
            self.trackedGroupIDs = trackedGroupIDs
            self.preferredSetsPerExercise = preferredSetsPerExercise
            self.mostRecentExerciseWorkingSets = mostRecentExerciseWorkingSets
            self.trainingGoalRawValue = trainingGoalRawValue
            self.preferredStyleRawValue = preferredStyleRawValue
            self.engineContext = engineContext
        }
    }

    /// Mirror of `SuggestedExerciseCandidate`. `id` is the canonical
    /// `ExerciseSuggestionExclusionKey`, never a Watch UUID or display name.
    public struct Candidate: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var mechanicsRawValue: String
        public var primaryMuscles: [String]
        public var secondaryMuscles: [String]
        public var equipmentRawValue: String?
        public var volumeEligible: Bool
        public var trainingTypeRawValues: [String]
        public var modalityRawValues: [String]
        public var sportContextRawValues: [String]
        public var isPersonalized: Bool

        public init(id: String, name: String, mechanicsRawValue: String,
                    primaryMuscles: [String], secondaryMuscles: [String] = [],
                    equipmentRawValue: String? = nil, volumeEligible: Bool = true,
                    trainingTypeRawValues: [String] = [], modalityRawValues: [String] = [],
                    sportContextRawValues: [String] = [], isPersonalized: Bool = false) {
            self.id = id
            self.name = name
            self.mechanicsRawValue = mechanicsRawValue
            self.primaryMuscles = primaryMuscles
            self.secondaryMuscles = secondaryMuscles
            self.equipmentRawValue = equipmentRawValue
            self.volumeEligible = volumeEligible
            self.trainingTypeRawValues = trainingTypeRawValues
            self.modalityRawValues = modalityRawValues
            self.sportContextRawValues = sportContextRawValues
            self.isPersonalized = isPersonalized
        }

        public init(_ candidate: SuggestedExerciseCandidate) {
            self.init(id: candidate.id, name: candidate.name,
                      mechanicsRawValue: candidate.mechanics.rawValue,
                      primaryMuscles: candidate.primaryMuscles,
                      secondaryMuscles: candidate.secondaryMuscles,
                      equipmentRawValue: candidate.equipment?.rawValue,
                      volumeEligible: candidate.volumeEligible,
                      trainingTypeRawValues: candidate.trainingTypes.map(\.rawValue),
                      modalityRawValues: candidate.modalities.map(\.rawValue),
                      sportContextRawValues: candidate.sportContexts.map(\.rawValue),
                      isPersonalized: candidate.isPersonalized)
        }
    }

    /// Mirror of `SuggestedWorkoutEngineContext` with the schedule flattened to
    /// primitives.
    public struct EngineContext: Codable, Equatable, Sendable {
        public var experienceRawValue: String
        public var schedule: Schedule
        public var availableEquipmentRawValues: [String]
        public var environment: String
        public var asOf: Date

        public init(experienceRawValue: String, schedule: Schedule,
                    availableEquipmentRawValues: [String], environment: String, asOf: Date) {
            self.experienceRawValue = experienceRawValue
            self.schedule = schedule
            self.availableEquipmentRawValues = availableEquipmentRawValues
            self.environment = environment
            self.asOf = asOf
        }

        public init(_ context: SuggestedWorkoutEngineContext) {
            self.init(experienceRawValue: context.experience.rawValue,
                      schedule: Schedule(context.schedule),
                      availableEquipmentRawValues: context.availableEquipment.map(\.rawValue),
                      environment: context.environment,
                      asOf: context.asOf)
        }
    }

    public struct Schedule: Codable, Equatable, Sendable {
        public static let fixedRestKind = "fixed"
        public static let rollingRestKind = "rolling"

        public var restKind: String
        /// `Weekday` raw values (1...7) when `restKind` is fixed.
        public var fixedRestWeekdays: [Int]
        /// Interval when `restKind` is rolling.
        public var rollingEveryNDays: Int
        public var allowsTwoADays: Bool
        public var sameDayCardioTimingRawValue: String
        public var dailyStepTarget: Int
        public var desiredSetsPerExercise: Int
        public var trackedMuscleGroupRawValues: [String]

        public init(restKind: String, fixedRestWeekdays: [Int] = [], rollingEveryNDays: Int = 3,
                    allowsTwoADays: Bool, sameDayCardioTimingRawValue: String,
                    dailyStepTarget: Int, desiredSetsPerExercise: Int,
                    trackedMuscleGroupRawValues: [String]) {
            self.restKind = restKind
            self.fixedRestWeekdays = fixedRestWeekdays
            self.rollingEveryNDays = rollingEveryNDays
            self.allowsTwoADays = allowsTwoADays
            self.sameDayCardioTimingRawValue = sameDayCardioTimingRawValue
            self.dailyStepTarget = dailyStepTarget
            self.desiredSetsPerExercise = desiredSetsPerExercise
            self.trackedMuscleGroupRawValues = trackedMuscleGroupRawValues
        }

        public init(_ schedule: CoachSchedulePreferences) {
            let kind: String
            var days: [Int] = []
            var every = 3
            switch schedule.restPreference {
            case .fixed(let set):
                kind = Self.fixedRestKind
                days = set.map(\.rawValue).sorted()
            case .rolling(let n):
                kind = Self.rollingRestKind
                every = n
            }
            self.init(restKind: kind, fixedRestWeekdays: days, rollingEveryNDays: every,
                      allowsTwoADays: schedule.allowsTwoADays,
                      sameDayCardioTimingRawValue: schedule.sameDayCardioTiming.rawValue,
                      dailyStepTarget: schedule.dailyStepTarget,
                      desiredSetsPerExercise: schedule.desiredSetsPerExercise,
                      trackedMuscleGroupRawValues: schedule.trackedMuscleGroups.map(\.rawValue).sorted())
        }

        func decoded() -> CoachSchedulePreferences? {
            let rest: RestPreference
            switch restKind {
            case Self.fixedRestKind:
                let days = fixedRestWeekdays.compactMap(Weekday.init(rawValue:))
                guard days.count == fixedRestWeekdays.count else { return nil }
                rest = .fixed(days: Set(days))
            case Self.rollingRestKind:
                guard (1...30).contains(rollingEveryNDays) else { return nil }
                rest = .rolling(everyNDays: rollingEveryNDays)
            default:
                return nil
            }
            guard let timing = SameDayCardioTiming(rawValue: sameDayCardioTimingRawValue),
                  let tracked = WatchSingleExerciseSuggestionContext.decodeAll(
                    trackedMuscleGroupRawValues, as: MuscleGroup.self),
                  !tracked.isEmpty else { return nil }
            return CoachSchedulePreferences(restPreference: rest,
                                            allowsTwoADays: allowsTwoADays,
                                            sameDayCardioTiming: timing,
                                            dailyStepTarget: dailyStepTarget,
                                            desiredSetsPerExercise: desiredSetsPerExercise,
                                            trackedMuscleGroups: Set(tracked))
        }
    }

    // MARK: - Adapter

    /// Builds the generator input, or `nil` when the version is unsupported or a
    /// required setting is invalid. `allocated` (sets already planned/performed in
    /// the current workout) is added to the completed-set vector; `excluding`
    /// removes canonical candidate IDs from the pool. Candidates whose own facets
    /// cannot be decoded are dropped individually.
    public func suggestedWorkoutInput(allocated: [String: Double],
                                      excluding: Set<String>) -> SuggestedWorkoutInput? {
        guard version == Self.currentVersion, generatedAt.timeIntervalSinceReferenceDate.isFinite,
              baseInput.candidates.count <= Self.maxCandidates else { return nil }
        let base = baseInput
        guard let goal = TrainingGoal(rawValue: base.trainingGoalRawValue),
              let style = SuggestedWorkoutStyle(rawValue: base.preferredStyleRawValue),
              (1...Self.maxSetsPerExercise).contains(base.preferredSetsPerExercise),
              let experience = ExperienceLevel(rawValue: base.engineContext.experienceRawValue),
              let equipment = Self.decodeAll(base.engineContext.availableEquipmentRawValues, as: Equipment.self),
              let schedule = base.engineContext.schedule.decoded(),
              base.engineContext.asOf.timeIntervalSinceReferenceDate.isFinite,
              base.engineContext.environment.count <= Self.maxStringLength,
              !base.engineContext.environment.isEmpty,
              base.historyData.map({ $0.count <= Self.maxHistoryDataBytes }) ?? true,
              let tracked = Self.decodeAll(Array(base.trackedGroupIDs), as: MuscleGroup.self),
              !tracked.isEmpty else { return nil }

        var sets = Self.sanitized(base.completedSetsByMuscle)
        for (muscle, value) in Self.sanitized(allocated) {
            sets[muscle] = min(Self.maxSetsPerMuscle, (sets[muscle] ?? 0) + value)
        }
        let candidates = base.candidates.compactMap(Self.decode)
        let input = SuggestedWorkoutInput(
            completedSetsByMuscle: sets,
            candidates: candidates,
            historyData: base.historyData,
            historyWorkoutCount: base.historyWorkoutCount,
            historyWorkingSetCount: base.historyWorkingSetCount,
            recentlyCompletedCandidateIDs: base.recentlyCompletedCandidateIDs,
            trackedGroups: Set(tracked),
            preferredSetsPerExercise: base.preferredSetsPerExercise,
            mostRecentExerciseWorkingSets: base.mostRecentExerciseWorkingSets,
            trainingGoal: goal,
            preferredStyle: style,
            engineContext: SuggestedWorkoutEngineContext(
                experience: experience, schedule: schedule,
                availableEquipment: equipment,
                environment: base.engineContext.environment,
                asOf: base.engineContext.asOf))
        return input.excluding(candidateIDs: excluding)
    }

    // MARK: - Helpers

    /// Drops non-finite and negative values and caps the rest.
    static func sanitized(_ values: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (key, value) in values where value.isFinite && !key.isEmpty
            && key.count <= maxStringLength {
            out[key] = min(maxSetsPerMuscle, max(0, value))
        }
        return out
    }

    /// All-or-nothing decode for required enum lists.
    static func decodeAll<E: RawRepresentable>(_ raws: [String], as: E.Type) -> [E]? where E.RawValue == String {
        guard raws.count <= maxFacetsPerCandidate * 2 else { return nil }
        let values = raws.compactMap(E.init(rawValue:))
        return values.count == raws.count ? values : nil
    }

    /// Lenient decode for optional candidate facets: unknown values are skipped.
    private static func decodeKnown<E: RawRepresentable>(_ raws: [String], as: E.Type) -> [E] where E.RawValue == String {
        raws.prefix(maxFacetsPerCandidate).compactMap(E.init(rawValue:))
    }

    private static func decode(_ c: Candidate) -> SuggestedExerciseCandidate? {
        guard !c.id.isEmpty, c.id.count <= maxStringLength, c.name.count <= maxStringLength,
              c.primaryMuscles.count <= maxMusclesPerCandidate,
              c.secondaryMuscles.count <= maxMusclesPerCandidate,
              let mechanics = Mechanics(rawValue: c.mechanicsRawValue) else { return nil }
        let equipment: Equipment?
        if let raw = c.equipmentRawValue {
            guard let known = Equipment(rawValue: raw) else { return nil }
            equipment = known
        } else {
            equipment = nil
        }
        return SuggestedExerciseCandidate(
            id: c.id, name: c.name, mechanics: mechanics,
            primaryMuscles: c.primaryMuscles, secondaryMuscles: c.secondaryMuscles,
            equipment: equipment, volumeEligible: c.volumeEligible,
            trainingTypes: decodeKnown(c.trainingTypeRawValues, as: ExerciseTrainingType.self),
            modalities: decodeKnown(c.modalityRawValues, as: ExerciseModality.self),
            sportContexts: decodeKnown(c.sportContextRawValues, as: ExerciseSportContext.self),
            isPersonalized: c.isPersonalized)
    }
}
