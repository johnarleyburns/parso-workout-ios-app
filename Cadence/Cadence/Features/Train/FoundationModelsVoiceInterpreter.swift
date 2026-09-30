#if canImport(FoundationModels)
import Foundation
import FoundationModels
import CadenceFeatures

/// Optional iOS 26+ adapter. The app still works on every supported device
/// without this framework: deterministic parsing is always attempted first and
/// the typed response is sent through `VoiceModelCommandMapper` before review.
@available(iOS 26.0, *)
actor FoundationModelsVoiceInterpreter: VoiceModelInterpreting {
    @Generable(description: "A single workout voice command. Never return prose.")
    struct Output {
        var kind: String
        var exercise: String?
        var performer: String?
        var weightKg: Double?
        var reps: Int?
        var rpe: Double?
        var adjustKg: Double?
        var seconds: Int?
        var isWarmup: Bool
    }

    func interpret(_ phrase: String, context: VoiceModelContext) async -> ModelVoiceCommand? {
        let model = SystemLanguageModel.default
        guard model.isAvailable, model.supportsLocale(Locale.current) else { return nil }

        let exerciseList = context.exercises.joined(separator: ", ")
        let performerList = context.performers.joined(separator: ", ")
        let instructions = """
        You map one workout utterance to one typed command. Never explain, coach,
        or invent names. Allowed kind values are: logSet, repeatLastSet,
        adjustNext, addExercise, switchExercise, setPerformer, addPartner, rest,
        skipRest, pause, resume, undo, startWorkout, finishWorkout. Use only
        exercises and performers from the supplied lists. Weight is kilograms.
        Return nil fields when absent. Reps must describe the user's command,
        not a recommendation.
        Current exercise: \(context.currentExercise ?? "none")
        Exercises: \(exerciseList)
        Performers: \(performerList)
        """
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: phrase, generating: Output.self)
            let output = response.content
            guard let kind = VoiceModelCommandKind(rawValue: output.kind) else { return nil }
            return ModelVoiceCommand(kind: kind, exercise: output.exercise,
                                     performer: output.performer, weightKg: output.weightKg,
                                     reps: output.reps, rpe: output.rpe,
                                     adjustKg: output.adjustKg, seconds: output.seconds,
                                     isWarmup: output.isWarmup)
        } catch {
            return nil
        }
    }
}
#endif
