import Foundation
import CadenceCore

public struct VoiceExerciseRef: Equatable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

public struct VoicePerformerRef: Equatable, Sendable {
    public let name: String
    public init(name: String) { self.name = name }
}

public struct VoiceSetSpec: Equatable, Sendable {
    public let exercise: VoiceExerciseRef?
    public let weightKg: Double?
    public let reps: Int?
    public let rpe: Double?
    public let isWarmup: Bool
    public let performer: VoicePerformerRef?

    public init(exercise: VoiceExerciseRef? = nil, weightKg: Double? = nil,
                reps: Int? = nil, rpe: Double? = nil, isWarmup: Bool = false,
                performer: VoicePerformerRef? = nil) {
        self.exercise = exercise
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.performer = performer
    }
}

public struct VoiceAdjust: Equatable, Sendable {
    public let deltaKg: Double
    public init(deltaKg: Double) { self.deltaKg = deltaKg }
}

public enum VoiceCommand: Equatable, Sendable {
    case logSet(VoiceSetSpec)
    case repeatLastSet(performer: VoicePerformerRef?, adjust: VoiceAdjust?)
    case adjustNext(VoiceAdjust)
    case addExercise(VoiceExerciseRef)
    case switchExercise(VoiceExerciseRef)
    case setPerformer(VoicePerformerRef)
    case addPartner(VoicePerformerRef)
    case rest(seconds: Int?)
    case skipRest
    case pause
    case resume
    case undo
    case startWorkout(VoiceExerciseRef?)
    case finishWorkout
}

public enum VoiceConfidence: Equatable, Sendable {
    case exact
    case inferred
    case ambiguous
}

public struct VoiceParseResult: Equatable, Sendable {
    public let command: VoiceCommand?
    public let recognizedTerms: [String]
    public let unsupportedTerms: [String]
    public let confidence: VoiceConfidence
    public let clarification: String?

    public init(command: VoiceCommand?, recognizedTerms: [String] = [],
                unsupportedTerms: [String] = [], confidence: VoiceConfidence,
                clarification: String? = nil) {
        self.command = command
        self.recognizedTerms = recognizedTerms
        self.unsupportedTerms = unsupportedTerms
        self.confidence = confidence
        self.clarification = clarification
    }
}

/// The deliberately small, typed contract accepted from an optional on-device
/// language model. The model never returns prose or mutates a workout; its
/// output is validated and then passed through the same resolver as rules-based
/// speech. Keeping this type FoundationModels-free makes the safety boundary
/// testable on macOS and usable by older iOS deployments.
public enum VoiceModelCommandKind: String, Codable, Sendable {
    case logSet
    case repeatLastSet
    case adjustNext
    case addExercise
    case switchExercise
    case setPerformer
    case addPartner
    case rest
    case skipRest
    case pause
    case resume
    case undo
    case startWorkout
    case finishWorkout
}

public struct ModelVoiceCommand: Codable, Equatable, Sendable {
    public let kind: VoiceModelCommandKind
    public let exercise: String?
    public let performer: String?
    public let weightKg: Double?
    public let reps: Int?
    public let rpe: Double?
    public let adjustKg: Double?
    public let seconds: Int?
    public let isWarmup: Bool

    public init(kind: VoiceModelCommandKind, exercise: String? = nil,
                performer: String? = nil, weightKg: Double? = nil,
                reps: Int? = nil, rpe: Double? = nil, adjustKg: Double? = nil,
                seconds: Int? = nil, isWarmup: Bool = false) {
        self.kind = kind
        self.exercise = exercise
        self.performer = performer
        self.weightKg = weightKg
        self.reps = reps
        self.rpe = rpe
        self.adjustKg = adjustKg
        self.seconds = seconds
        self.isWarmup = isWarmup
    }
}

public struct VoiceModelContext: Sendable {
    public let currentExercise: String?
    public let exercises: [String]
    public let performers: [String]

    public init(currentExercise: String?, exercises: [String], performers: [String]) {
        self.currentExercise = currentExercise
        self.exercises = exercises
        self.performers = performers
    }
}

public protocol VoiceModelInterpreting: Sendable {
    func interpret(_ phrase: String, context: VoiceModelContext) async -> ModelVoiceCommand?
}

public enum VoiceModelCommandMapper {
    /// Converts model output into the existing parser result, rejecting values
    /// outside the same safe bounds used by the handwritten parser. A mapped
    /// command is always `.inferred`, so the UI cannot auto-apply it as exact.
    public static func parse(_ model: ModelVoiceCommand) -> VoiceParseResult? {
        guard valid(model) else { return nil }
        let performer = model.performer.map(VoicePerformerRef.init(name:))
        let exercise = model.exercise.map(VoiceExerciseRef.init(name:))
        let setSpec = VoiceSetSpec(exercise: exercise, weightKg: model.weightKg,
                                   reps: model.reps, rpe: model.rpe,
                                   isWarmup: model.isWarmup, performer: performer)

        let command: VoiceCommand
        switch model.kind {
        case .logSet: command = .logSet(setSpec)
        case .repeatLastSet:
            command = .repeatLastSet(performer: performer,
                                     adjust: model.adjustKg.map(VoiceAdjust.init(deltaKg:)))
        case .adjustNext: command = .adjustNext(VoiceAdjust(deltaKg: model.adjustKg ?? 0))
        case .addExercise: command = .addExercise(exercise ?? VoiceExerciseRef(name: ""))
        case .switchExercise: command = .switchExercise(exercise ?? VoiceExerciseRef(name: ""))
        case .setPerformer: command = .setPerformer(performer ?? VoicePerformerRef(name: ""))
        case .addPartner: command = .addPartner(performer ?? VoicePerformerRef(name: ""))
        case .rest: command = .rest(seconds: model.seconds)
        case .skipRest: command = .skipRest
        case .pause: command = .pause
        case .resume: command = .resume
        case .undo: command = .undo
        case .startWorkout: command = .startWorkout(exercise)
        case .finishWorkout: command = .finishWorkout
        }
        return VoiceParseResult(command: command, confidence: .inferred)
    }

    private static func valid(_ model: ModelVoiceCommand) -> Bool {
        guard model.exercise?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true,
              model.performer?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true else {
            return false
        }
        if let reps = model.reps, !(1...100).contains(reps) { return false }
        if let weight = model.weightKg, !(0...1_000).contains(weight) || !weight.isFinite { return false }
        if let rpe = model.rpe, !(0...10).contains(rpe) || !rpe.isFinite { return false }
        if let adjustment = model.adjustKg, !(abs(adjustment) <= 1_000) || !adjustment.isFinite { return false }
        if let seconds = model.seconds, !(0...7_200).contains(seconds) { return false }
        switch model.kind {
        case .logSet:
            return model.reps != nil || model.weightKg != nil
        case .adjustNext:
            return model.adjustKg != nil
        case .addExercise, .switchExercise, .startWorkout:
            return model.exercise != nil || model.kind == .startWorkout
        case .setPerformer, .addPartner:
            return model.performer != nil
        default:
            return true
        }
    }
}

public enum VoiceModelFallback {
    /// Consults the model only when deterministic parsing could not produce a
    /// command. Errors, unavailable models, and invalid output all preserve the
    /// original parse result and therefore fail closed.
    public static func enhance(_ parsed: VoiceParseResult, phrase: String,
                               context: VoiceModelContext,
                               interpreter: (any VoiceModelInterpreting)?) async -> VoiceParseResult {
        guard parsed.command == nil, let interpreter,
              let model = await interpreter.interpret(phrase, context: context),
              let mapped = VoiceModelCommandMapper.parse(model) else { return parsed }
        return mapped
    }
}

public enum VoiceCommandParser {
    public static func parse(_ phrase: String,
                             unit: MeasurementUnitPreference = .pounds,
                             bodyweight: Bool = false) -> VoiceParseResult {
        let normalized = phrase.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "×", with: " x ")
            .replacingOccurrences(of: "@", with: " at ")
            .split(whereSeparator: { $0.isWhitespace || ",.!?".contains($0) })
            .map(String.init)
        guard !normalized.isEmpty else {
            return VoiceParseResult(command: nil, confidence: .ambiguous,
                                    clarification: "What would you like to log?")
        }

        if normalized == ["undo"] || normalized == ["undo", "that"] {
            return exact(.undo, recognized: normalized)
        }
        if normalized.contains("skip") && normalized.contains("rest") {
            return exact(.skipRest, recognized: normalized)
        }
        if normalized.first == "pause" { return exact(.pause, recognized: normalized) }
        if normalized.first == "resume" { return exact(.resume, recognized: normalized) }
        if normalized.first == "finish" || normalized.prefix(2) == ["end", "workout"] {
            return exact(.finishWorkout, recognized: normalized)
        }
        if normalized.first == "rest" {
            let value = number(in: normalized.dropFirst())?.value
            return exact(.rest(seconds: value.map { Int($0 * 60) }), recognized: normalized)
        }
        if normalized.first == "add", normalized.dropFirst().first == "exercise" {
            let name = normalized.dropFirst(2).joined(separator: " ")
            return commandForExercise(name, kind: .add, recognized: normalized)
        }
        if normalized.first == "add",
           normalized.dropFirst().first != "partner",
           normalized.dropFirst().first != "exercise",
           number(in: normalized.dropFirst()) == nil {
            return commandForExercise(normalized.dropFirst().joined(separator: " "), kind: .add,
                                      recognized: normalized)
        }
        if normalized.first == "switch", normalized.dropFirst().first == "to" {
            let name = normalized.dropFirst(2).joined(separator: " ")
            return commandForExercise(name, kind: .switch, recognized: normalized)
        }
        if normalized.first == "add", normalized.dropFirst().first == "partner" {
            let name = normalized.dropFirst(2).joined(separator: " ")
            return commandForPerformer(name, kind: .addPartner, recognized: normalized)
        }
        if normalized.count >= 2, normalized[1] == "turn" || normalized.last == "turn" {
            let name = normalized.first == "my" ? normalized.dropFirst().dropLast().joined(separator: " ") : normalized.dropLast().joined(separator: " ")
            return commandForPerformer(name, kind: .setPerformer, recognized: normalized)
        }
        if normalized.first == "same" || (normalized.first == "repeat" && normalized.count <= 3) {
            let performer = performerFromPrefix(normalized)
            return exact(.repeatLastSet(performer: performer, adjust: nil), recognized: normalized)
        }
        if normalized.first == "plus" || normalized.first == "add" || normalized.first == "drop" || normalized.first == "minus" {
            let amount = number(in: normalized.dropFirst())
            guard let amount else { return ambiguous("How much should I adjust?") }
            let sign = (normalized.first == "drop" || normalized.first == "minus") ? -1.0 : 1.0
            let kg = canonicalWeight(amount.value * sign, explicitUnit: amount.unit, preference: unit)
            return exact(.adjustNext(VoiceAdjust(deltaKg: kg)), recognized: normalized)
        }
        if normalized.first == "start" {
            let name = normalized.dropFirst().joined(separator: " ")
            return exact(.startWorkout(name.isEmpty ? nil : VoiceExerciseRef(name: name)), recognized: normalized)
        }

        return parseSet(normalized, unit: unit, bodyweight: bodyweight)
    }

    private enum ExerciseCommand { case add, `switch` }
    private enum PerformerCommand { case addPartner, setPerformer }
    private struct ParsedNumber { let value: Double; let unit: WeightUnit?; let range: Range<Int> }
    private enum WeightUnit { case kg, lb }

    private static func parseSet(_ words: [String], unit: MeasurementUnitPreference,
                                 bodyweight: Bool) -> VoiceParseResult {
        var tokens = words
        var performer: VoicePerformerRef?
        if tokens.count >= 2, tokens[1] == "did" {
            performer = VoicePerformerRef(name: tokens[0].capitalized)
            tokens.removeFirst(2)
        }
        let numbers = allNumbers(in: tokens)
        let repsIndex = tokens.firstIndex(where: { $0 == "rep" || $0 == "reps" || $0 == "repetitions" })
        let weightIndex = tokens.firstIndex(where: { ["pound", "pounds", "lb", "lbs", "kilo", "kilos", "kg", "kilograms"].contains($0) })
        let repsNumber = repsIndex.flatMap { index in numbers.last(where: { $0.range.lowerBound < index }) }
        let weightNumber = weightIndex.flatMap { index in numbers.last(where: { $0.range.lowerBound < index }) }
        var reps: Int?
        var weight: Double?
        var confidence: VoiceConfidence = .inferred
        var recognized = words

        if let repsNumber {
            reps = Int(repsNumber.value)
            recognized.append("reps")
        }
        if !bodyweight, let weightNumber {
            weight = canonicalWeight(weightNumber.value, explicitUnit: weightNumber.unit, preference: unit)
            recognized.append(weightNumber.unit == .kg ? "kg" : "lb")
        }
        if reps == nil, let weightNumber, numbers.count >= 2 {
            reps = Int(numbers.last(where: { $0.range.lowerBound != weightNumber.range.lowerBound })?.value ?? 0)
            recognized.append("reps")
        }
        if reps == nil && weight == nil && numbers.count >= 2 {
            let sorted = numbers.sorted { $0.value > $1.value }
            if bodyweight {
                reps = Int(sorted.last?.value ?? 0)
            } else {
                weight = canonicalWeight(sorted[0].value, explicitUnit: sorted[0].unit, preference: unit)
                reps = Int(sorted[1].value)
                confidence = .inferred
            }
        }
        if reps == nil && numbers.count == 1 {
            reps = Int(numbers[0].value)
        }
        if let reps, !(1...100).contains(reps) {
            return ambiguous("How many reps should I log?")
        }
        if reps == nil && weight == nil {
            return ambiguous("Say an exercise, weight, and reps, or say ‘same again’.")
        }
        let exerciseWords = exerciseWords(from: tokens, numbers: numbers)
        let exercise = exerciseWords.isEmpty ? nil : VoiceExerciseRef(name: exerciseWords)
        if reps != nil && (weight != nil || bodyweight)
            && (repsIndex != nil || (weightIndex != nil && numbers.count >= 2)) {
            confidence = .exact
        }
        let spec = VoiceSetSpec(exercise: exercise, weightKg: weight, reps: reps,
                               isWarmup: tokens.contains("warmup") || tokens.contains("warm-up"),
                               performer: performer)
        return VoiceParseResult(command: .logSet(spec), recognizedTerms: recognized,
                                confidence: confidence)
    }

    private static func exerciseWords(from tokens: [String], numbers: [ParsedNumber]) -> String {
        let firstNumber = numbers.map(\.range.lowerBound).min() ?? tokens.count
        let ignored: Set<String> = ["did", "for", "at", "by", "times", "x", "reps", "rep", "pounds", "pound", "lb", "lbs", "kg", "kilos", "kilo", "kilograms", "warmup", "warm-up"]
        return tokens[..<firstNumber].filter { !ignored.contains($0) }.joined(separator: " ")
    }

    private static func allNumbers(in words: [String]) -> [ParsedNumber] {
        var result: [ParsedNumber] = []
        var index = 0
        while index < words.count {
            if let parsed = number(in: words[index...]) {
                result.append(ParsedNumber(value: parsed.value, unit: parsed.unit,
                                           range: index..<(index + parsed.consumed)))
                index += parsed.consumed
            } else { index += 1 }
        }
        return result
    }

    private struct NumberResult { let value: Double; let unit: WeightUnit?; let consumed: Int }
    private static func number<S: Sequence>(in words: S) -> NumberResult? where S.Element == String {
        let words = Array(words)
        guard let first = words.first else { return nil }
        if let value = Double(first.replacingOccurrences(of: ",", with: "")) {
            return NumberResult(value: value, unit: explicitUnit(after: words, offset: 1), consumed: 1)
        }
        let small: [String: Double] = ["a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19]
        let tens: [String: Double] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        if first == "hundred" { return NumberResult(value: 100, unit: explicitUnit(after: words, offset: 1), consumed: 1) }
        if let firstValue = small[first], words.dropFirst().first == "hundred" {
            return NumberResult(value: firstValue * 100, unit: explicitUnit(after: words, offset: 2), consumed: 2)
        }
        if let firstValue = small[first], words.count >= 2, let second = tens[words[1]] {
            let third = words.count >= 3 ? small[words[2]] ?? 0 : 0
            let consumed = third > 0 ? 3 : 2
            return NumberResult(value: firstValue * 100 + second + third,
                                unit: explicitUnit(after: words, offset: consumed), consumed: consumed)
        }
        if let value = tens[first] {
            let second = words.count >= 2 ? small[words[1]] : nil
            let consumed = second == nil ? 1 : 2
            return NumberResult(value: value + (second ?? 0), unit: explicitUnit(after: words, offset: consumed), consumed: consumed)
        }
        if let value = small[first] {
            return NumberResult(value: value, unit: explicitUnit(after: words, offset: 1), consumed: 1)
        }
        return nil
    }

    private static func explicitUnit(after words: [String], offset: Int) -> WeightUnit? {
        guard words.indices.contains(offset) else { return nil }
        switch words[offset] {
        case "kg", "kilo", "kilos", "kilogram", "kilograms": return .kg
        case "lb", "lbs", "pound", "pounds": return .lb
        default: return nil
        }
    }

    private static func canonicalWeight(_ value: Double, explicitUnit: WeightUnit?, preference: MeasurementUnitPreference) -> Double {
        let selected = explicitUnit ?? (preference == .kilograms ? .kg : .lb)
        return selected == .kg ? value : WorkoutMath.lbToKg(value)
    }

    private static func performerFromPrefix(_ words: [String]) -> VoicePerformerRef? {
        guard words.count > 2, words[1] != "again" else { return nil }
        return VoicePerformerRef(name: words.dropFirst().dropLast().joined(separator: " ").capitalized)
    }

    private static func commandForExercise(_ name: String, kind: ExerciseCommand,
                                           recognized: [String]) -> VoiceParseResult {
        guard !name.isEmpty else { return ambiguous("Which exercise?") }
        let ref = VoiceExerciseRef(name: name)
        return exact(kind == .add ? .addExercise(ref) : .switchExercise(ref), recognized: recognized)
    }

    private static func commandForPerformer(_ name: String, kind: PerformerCommand,
                                            recognized: [String]) -> VoiceParseResult {
        guard !name.isEmpty else { return ambiguous("Which person?") }
        let ref = VoicePerformerRef(name: name.capitalized)
        return exact(kind == .addPartner ? .addPartner(ref) : .setPerformer(ref), recognized: recognized)
    }

    private static func exact(_ command: VoiceCommand, recognized: [String]) -> VoiceParseResult {
        VoiceParseResult(command: command, recognizedTerms: recognized, confidence: .exact)
    }

    private static func ambiguous(_ clarification: String) -> VoiceParseResult {
        VoiceParseResult(command: nil, confidence: .ambiguous, clarification: clarification)
    }
}
