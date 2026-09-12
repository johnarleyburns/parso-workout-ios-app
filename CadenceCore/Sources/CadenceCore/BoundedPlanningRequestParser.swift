import Foundation

/// The result of the bounded natural-language adapter.
///
/// This adapter only translates a small, inspectable vocabulary into the
/// existing `PlanningRequest`. It never selects exercises, set schemes, loads,
/// or prescriptions. The deterministic planning engine remains the sole
/// prescription authority.
public struct BoundedPlanningParseResult: Equatable, Sendable {
    public let request: PlanningRequest?
    public let recognizedTerms: [String]
    public let unsupportedTerms: [String]
    public let clarification: String?

    public var isActionable: Bool { request != nil && unsupportedTerms.isEmpty }

    public init(request: PlanningRequest?, recognizedTerms: [String],
                unsupportedTerms: [String], clarification: String? = nil) {
        self.request = request
        self.recognizedTerms = recognizedTerms
        self.unsupportedTerms = unsupportedTerms
        self.clarification = clarification
    }
}

/// A deliberately bounded parser for planning requests.
///
/// Supported examples include:
/// - "4 days of hypertrophy with dumbbells, 45 minutes"
/// - "beginner strength, 3 days, 4 weeks, double progression"
/// - "conditioning with no squats and a deload"
///
/// Unknown conversational filler is ignored, while retired product requests
/// are surfaced as unsupported instead of being guessed at. This makes the
/// natural-language layer an input adapter, not a second coaching engine.
public enum BoundedPlanningRequestParser {
    public static func parse(_ input: String,
                             referenceDate: Date = Date()) -> BoundedPlanningParseResult {
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tokens = normalized.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        guard !tokens.isEmpty else {
            return BoundedPlanningParseResult(
                request: nil, recognizedTerms: [], unsupportedTerms: [],
                clarification: "Describe a goal, number of training days, or conditioning preference.")
        }

        var recognized: [String] = []
        var unsupported: [String] = []
        var goal: TrainingGoal = .hypertrophy
        var explicitGoal = false
        var experience: ExperienceLevel = .intermediate
        var daysPerWeek = 3
        var sessionLengthMinutes: Int?
        var equipment: [Equipment] = []
        var constraints: [PlanningConstraint] = []
        var preferences: [String] = []
        var horizon: PlanHorizon = .singleWeek
        var progression: ProgressionIntent?
        var periodization: PeriodizationModel?
        var wantsConditioning = false

        func record(_ term: String) {
            if !recognized.contains(term) { recognized.append(term) }
        }

        func addEquipment(_ value: Equipment) {
            if !equipment.contains(value) { equipment.append(value) }
        }

        func addConstraint(_ value: PlanningConstraint) {
            if !constraints.contains(where: { sameConstraint($0, value) }) {
                constraints.append(value)
            }
        }

        let retiredTerms = ["trainer", "client", "clients", "pro", "paywall", "trial", "share"]
        for term in retiredTerms where tokens.contains(term) {
            unsupported.append(term)
        }

        for (index, token) in tokens.enumerated() {
            switch token {
            case "strength", "powerlifting", "power":
                goal = .strength
                explicitGoal = true
                record("strength")
            case "hypertrophy", "muscle", "musclebuilding", "bodybuilding":
                goal = .hypertrophy
                explicitGoal = true
                record("hypertrophy")
            case "endurance", "conditioning", "cardio", "aerobic":
                if !explicitGoal { goal = .endurance }
                wantsConditioning = true
                record("conditioning")
            case "beginner", "novice":
                experience = .beginner
                record("beginner")
            case "intermediate":
                experience = .intermediate
                record("intermediate")
            case "advanced", "experienced":
                experience = .advanced
                record("advanced")
            case "deload", "deloading":
                periodization = .accumulationIntensificationDeload
                record("deload")
            case "linear":
                progression = .linearLoad
                periodization = periodization ?? .linear
                record("linear progression")
            case "double" where tokens.dropFirst(index + 1).first == "progression":
                progression = .doubleProgression
                record("double progression")
            case "autoregulated", "autoregulation", "rpe", "rir":
                progression = .autoregulated
                record("autoregulation")
            case "percentage", "percent", "1rm":
                progression = .percentageBased
                record("percentage-based progression")
            case "volume":
                progression = .volume
                record("volume progression")
            case "upper" where tokens.dropFirst(index + 1).first == "lower":
                addPreference("upper/lower", to: &preferences)
                record("upper/lower")
            case "full" where tokens.dropFirst(index + 1).first == "body":
                addPreference("full body", to: &preferences)
                record("full body")
            default:
                break
            }

            if let value = planningNumber(for: token) {
                if let next = tokens[safe: index + 1] {
                    switch next {
                    case "day", "days":
                        if (1...7).contains(value) {
                            daysPerWeek = value
                            record("\(value) days")
                        }
                    case "minute", "minutes", "min":
                        if value > 0 {
                            sessionLengthMinutes = value
                            record("\(value) minutes")
                        }
                    case "week", "weeks":
                        if (1...52).contains(value) {
                            horizon = .mesocycle(weeks: value)
                            record("\(value) weeks")
                        }
                    default:
                        break
                    }
                }
            }

            if let found = equipmentFor(token) {
                addEquipment(found)
                record(found.displayName.lowercased())
            }

            if ["no", "avoid", "without"].contains(token),
               let next = tokens[safe: index + 1] {
                if let pattern = movementPattern(for: next) {
                    addConstraint(.avoidMovementPattern(pattern))
                    record("avoid \(pattern.displayName.lowercased())")
                } else if let muscle = MuscleGroup.canonical(next) {
                    addConstraint(.avoidMuscleGroup(muscle))
                    record("avoid \(muscle.displayName.lowercased())")
                } else if let unavailable = equipmentFor(next) {
                    addConstraint(.unavailableEquipment(unavailable))
                    record("without \(unavailable.displayName.lowercased())")
                }
            }
        }

        unsupported = Array(Set(unsupported)).sorted()
        guard !unsupported.isEmpty || !recognized.isEmpty else {
            return BoundedPlanningParseResult(
                request: nil, recognizedTerms: [], unsupportedTerms: [],
                clarification: "I can use goal, experience, days, duration, equipment, constraints, progression, periodization, and conditioning terms.")
        }

        let request = PlanningRequest(
            goal: goal,
            experience: experience,
            daysPerWeek: daysPerWeek,
            sessionLengthMinutes: sessionLengthMinutes,
            equipmentProfile: equipment,
            constraints: constraints,
            preferences: preferences,
            horizon: horizon,
            progression: progression,
            periodization: periodization,
            wantsConditioning: wantsConditioning,
            referenceDate: referenceDate)

        if !unsupported.isEmpty {
            return BoundedPlanningParseResult(
                request: nil, recognizedTerms: recognized, unsupportedTerms: unsupported,
                clarification: "That request belongs to a retired product surface. Ask for an individual plan instead.")
        }

        do {
            try request.validate()
            return BoundedPlanningParseResult(
                request: request, recognizedTerms: recognized, unsupportedTerms: [], clarification: nil)
        } catch {
            return BoundedPlanningParseResult(
                request: nil, recognizedTerms: recognized, unsupportedTerms: [],
                clarification: "The request needs a valid day count, duration, or readiness value.")
        }
    }

    private static func addPreference(_ value: String, to values: inout [String]) {
        if !values.contains(value) { values.append(value) }
    }

    private static func equipmentFor(_ token: String) -> Equipment? {
        switch token {
        case "barbell", "barbells": return .barbell
        case "dumbbell", "dumbbells": return .dumbbell
        case "cable", "cables": return .cable
        case "machine", "machines": return .machine
        case "kettlebell", "kettlebells": return .kettlebell
        case "band", "bands": return .band
        case "smith": return .smith
        default: return Equipment(rawValue: token)
        }
    }

    private static func planningNumber(for token: String) -> Int? {
        if let value = Int(token) { return value }
        switch token {
        case "one": return 1
        case "two": return 2
        case "three": return 3
        case "four": return 4
        case "five": return 5
        case "six": return 6
        case "seven": return 7
        case "eight": return 8
        case "nine": return 9
        case "ten": return 10
        case "eleven": return 11
        case "twelve": return 12
        default: return nil
        }
    }

    private static func movementPattern(for token: String) -> MovementPattern? {
        switch token {
        case "squat", "squats": return .squat
        case "hinge", "hinges", "deadlift", "deadlifts": return .hinge
        case "push", "press", "presses": return .horizontalPush
        case "pull", "pulls": return .horizontalPull
        default: return MovementPattern(rawValue: token)
        }
    }

    private static func sameConstraint(_ lhs: PlanningConstraint,
                                      _ rhs: PlanningConstraint) -> Bool {
        switch (lhs, rhs) {
        case let (.unavailableExercise(a), .unavailableExercise(b)): return a == b
        case let (.unavailableEquipment(a), .unavailableEquipment(b)): return a == b
        case let (.avoidMovementPattern(a), .avoidMovementPattern(b)): return a == b
        case let (.avoidMuscleGroup(a), .avoidMuscleGroup(b)): return a == b
        case let (.excludedWeekdays(a), .excludedWeekdays(b)): return a == b
        case let (.maximumSessionMinutes(a), .maximumSessionMinutes(b)): return a == b
        case let (.note(a), .note(b)): return a == b
        default: return false
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
