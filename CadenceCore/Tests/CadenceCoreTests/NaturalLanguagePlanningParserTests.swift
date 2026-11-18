import Foundation
import Testing
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
@testable import CadenceCore

/// These are phrase-level acceptance cases for the bounded natural-language
/// adapter. The same Apple NaturalLanguage framework is available on macOS and
/// iOS; macOS tokenization is used here as a fast headless parity check while
/// the semantic assertions remain deterministic and app-owned.
struct NaturalLanguagePlanningParserTests {
    private struct PhraseCase {
        let phrase: String
        let goal: TrainingGoal
        let experience: ExperienceLevel
        let days: Int
        let conditioning: Bool
        let progression: ProgressionIntent?
        let periodization: PeriodizationModel?
        let equipment: [Equipment]
    }

    @Test func macOSNaturalLanguageTokenizesEverySupportedPlanningPhrase() {
#if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        for item in phraseCases {
            tagger.string = item.phrase
            var wordCount = 0
            tagger.enumerateTags(
                in: item.phrase.startIndex..<item.phrase.endIndex,
                unit: .word,
                scheme: .lexicalClass,
                options: []) { _, _ in
                    wordCount += 1
                    return true
                }
            #expect(wordCount > 0, "\(item.phrase)")
        }
#else
        #expect(Bool(true), "NaturalLanguage is unavailable on this host; parser cases still run below.")
#endif
    }

    @Test func sixtyNaturalLanguagePlanningPhrasesMapToStructuredIntent() throws {
        #expect(phraseCases.count >= 60)
        for item in phraseCases {
            let result = BoundedPlanningRequestParser.parse(item.phrase)
            #expect(result.isActionable, "Expected actionable phrase: \(item.phrase)\n\(result)")
            let request = try #require(result.request, "\(item.phrase)")
            #expect(request.goal == item.goal, "\(item.phrase)")
            #expect(request.experience == item.experience, "\(item.phrase)")
            #expect(request.daysPerWeek == item.days, "\(item.phrase)")
            #expect(request.wantsConditioning == item.conditioning, "\(item.phrase)")
            #expect(request.progression == item.progression, "\(item.phrase)")
            #expect(request.periodization == item.periodization, "\(item.phrase)")
            #expect(request.equipmentProfile == item.equipment, "\(item.phrase)")
        }
    }

    @Test func naturalLanguageVariantsPreserveDurationsHorizonsPreferencesAndConstraints() throws {
        let durationPhrases: [(String, Int, PlanHorizon)] = [
            ("four days, 30 minutes", 30, .singleWeek),
            ("four days, 45 min", 45, .singleWeek),
            ("four days, 60 minutes", 60, .singleWeek),
            ("four days for 8 weeks", 0, .mesocycle(weeks: 8)),
            ("three days for twelve weeks", 0, .mesocycle(weeks: 12)),
            ("two day, 6 week block", 0, .mesocycle(weeks: 6)),
            ("seven days, 4 weeks", 0, .mesocycle(weeks: 4)),
            ("one day, 90 minutes", 90, .singleWeek)
        ]
        for (phrase, minutes, horizon) in durationPhrases {
            let request = try #require(BoundedPlanningRequestParser.parse(phrase).request, "\(phrase)")
            if minutes > 0 { #expect(request.sessionLengthMinutes == minutes, "\(phrase)") }
            #expect(request.horizon == horizon, "\(phrase)")
        }

        let upperLower = try #require(BoundedPlanningRequestParser.parse("four days upper lower split").request)
        #expect(upperLower.preferences == ["upper/lower"])
        let fullBody = try #require(BoundedPlanningRequestParser.parse("three days full body").request)
        #expect(fullBody.preferences == ["full body"])

        let noSquats = try #require(BoundedPlanningRequestParser.parse("four days, no squats").request)
        #expect(noSquats.constraints == [.avoidMovementPattern(.squat)])
        let noLats = try #require(BoundedPlanningRequestParser.parse("four days, avoid lats").request)
        #expect(noLats.constraints == [.avoidMuscleGroup(.lats)])
        let noBarbells = try #require(BoundedPlanningRequestParser.parse("four days without barbells").request)
        #expect(noBarbells.constraints == [.unavailableEquipment(.barbell)])
    }

    private var phraseCases: [PhraseCase] {
        [
            PhraseCase(phrase: "strength one day", goal: .strength, experience: .intermediate, days: 1, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength two days", goal: .strength, experience: .intermediate, days: 2, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength three days", goal: .strength, experience: .intermediate, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength four days", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength five days", goal: .strength, experience: .intermediate, days: 5, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength six days", goal: .strength, experience: .intermediate, days: 6, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength seven days", goal: .strength, experience: .intermediate, days: 7, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "powerlifting three days", goal: .strength, experience: .intermediate, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "power four days", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "hypertrophy one day", goal: .hypertrophy, experience: .intermediate, days: 1, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "hypertrophy two days", goal: .hypertrophy, experience: .intermediate, days: 2, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "hypertrophy three days", goal: .hypertrophy, experience: .intermediate, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "hypertrophy four days", goal: .hypertrophy, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "muscle building five days", goal: .hypertrophy, experience: .intermediate, days: 5, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "bodybuilding six days", goal: .hypertrophy, experience: .intermediate, days: 6, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "endurance one day", goal: .endurance, experience: .intermediate, days: 1, conditioning: true, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "endurance two days", goal: .endurance, experience: .intermediate, days: 2, conditioning: true, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "conditioning three days", goal: .endurance, experience: .intermediate, days: 3, conditioning: true, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "cardio four days", goal: .endurance, experience: .intermediate, days: 4, conditioning: true, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "aerobic five days", goal: .endurance, experience: .intermediate, days: 5, conditioning: true, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "beginner strength two days", goal: .strength, experience: .beginner, days: 2, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "novice hypertrophy three days", goal: .hypertrophy, experience: .beginner, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "intermediate strength four days", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "advanced hypertrophy five days", goal: .hypertrophy, experience: .advanced, days: 5, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "experienced conditioning six days", goal: .endurance, experience: .advanced, days: 6, conditioning: true, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength three days linear", goal: .strength, experience: .intermediate, days: 3, conditioning: false, progression: .linearLoad, periodization: .linear, equipment: []),
            PhraseCase(phrase: "hypertrophy four days double progression", goal: .hypertrophy, experience: .intermediate, days: 4, conditioning: false, progression: .doubleProgression, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength four days autoregulated", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: .autoregulated, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength four days autoregulation", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: .autoregulated, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength four days RPE", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: .autoregulated, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength four days RIR", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: .autoregulated, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength four days percentage", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: .percentageBased, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength four days percent 1RM", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: .percentageBased, periodization: nil, equipment: []),
            PhraseCase(phrase: "hypertrophy four days volume", goal: .hypertrophy, experience: .intermediate, days: 4, conditioning: false, progression: .volume, periodization: nil, equipment: []),
            PhraseCase(phrase: "hypertrophy four days deload", goal: .hypertrophy, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: .accumulationIntensificationDeload, equipment: []),
            PhraseCase(phrase: "strength four days deloading", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: .accumulationIntensificationDeload, equipment: []),
            PhraseCase(phrase: "strength four days with barbells", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: [.barbell]),
            PhraseCase(phrase: "strength four days with dumbbells", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: [.dumbbell]),
            PhraseCase(phrase: "strength four days with cables", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: [.cable]),
            PhraseCase(phrase: "strength four days with machines", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: [.machine]),
            PhraseCase(phrase: "strength four days with kettlebells", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: [.kettlebell]),
            PhraseCase(phrase: "strength four days with bands", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: [.band]),
            PhraseCase(phrase: "strength four days with a barbell", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: [.barbell]),
            PhraseCase(phrase: "strength four days with a dumbbell", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: [.dumbbell]),
            PhraseCase(phrase: "hypertrophy three days dumbbell cable", goal: .hypertrophy, experience: .intermediate, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: [.dumbbell, .cable]),
            PhraseCase(phrase: "hypertrophy three days barbell machine", goal: .hypertrophy, experience: .intermediate, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: [.barbell, .machine]),
            PhraseCase(phrase: "strength three days kettlebell band", goal: .strength, experience: .intermediate, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: [.kettlebell, .band]),
            PhraseCase(phrase: "conditioning three days bodyweight", goal: .endurance, experience: .intermediate, days: 3, conditioning: true, progression: nil, periodization: nil, equipment: [.bodyweight]),
            PhraseCase(phrase: "strength two days smith", goal: .strength, experience: .intermediate, days: 2, conditioning: false, progression: nil, periodization: nil, equipment: [.smith]),
            PhraseCase(phrase: "powerlifting four days with barbell, linear", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: .linearLoad, periodization: .linear, equipment: [.barbell]),
            PhraseCase(phrase: "beginner muscle building three days dumbbell", goal: .hypertrophy, experience: .beginner, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: [.dumbbell]),
            PhraseCase(phrase: "novice cardio two days with bands", goal: .endurance, experience: .beginner, days: 2, conditioning: true, progression: nil, periodization: nil, equipment: [.band]),
            PhraseCase(phrase: "advanced strength five days with machines, RPE", goal: .strength, experience: .advanced, days: 5, conditioning: false, progression: .autoregulated, periodization: nil, equipment: [.machine]),
            PhraseCase(phrase: "experienced hypertrophy six days with cables, double progression", goal: .hypertrophy, experience: .advanced, days: 6, conditioning: false, progression: .doubleProgression, periodization: nil, equipment: [.cable]),
            PhraseCase(phrase: "intermediate endurance four days, deload", goal: .endurance, experience: .intermediate, days: 4, conditioning: true, progression: nil, periodization: .accumulationIntensificationDeload, equipment: []),
            PhraseCase(phrase: "strength three days, full body", goal: .strength, experience: .intermediate, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "hypertrophy four days, upper lower", goal: .hypertrophy, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "muscle three days, 45 minutes", goal: .hypertrophy, experience: .intermediate, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "power four days, 60 minutes", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "aerobic two days, 30 minutes", goal: .endurance, experience: .intermediate, days: 2, conditioning: true, progression: nil, periodization: nil, equipment: []),
            PhraseCase(phrase: "conditioning five days, double progression", goal: .endurance, experience: .intermediate, days: 5, conditioning: true, progression: .doubleProgression, periodization: nil, equipment: []),
            PhraseCase(phrase: "strength one day, percentage based", goal: .strength, experience: .intermediate, days: 1, conditioning: false, progression: .percentageBased, periodization: nil, equipment: []),
            PhraseCase(phrase: "hypertrophy seven days, volume progression", goal: .hypertrophy, experience: .intermediate, days: 7, conditioning: false, progression: .volume, periodization: nil, equipment: []),
            PhraseCase(phrase: "beginner endurance three days, linear", goal: .endurance, experience: .beginner, days: 3, conditioning: true, progression: .linearLoad, periodization: .linear, equipment: []),
            PhraseCase(phrase: "advanced powerlifting six days, deload", goal: .strength, experience: .advanced, days: 6, conditioning: false, progression: nil, periodization: .accumulationIntensificationDeload, equipment: []),
            PhraseCase(phrase: "intermediate bodybuilding five days with smith machine", goal: .hypertrophy, experience: .intermediate, days: 5, conditioning: false, progression: nil, periodization: nil, equipment: [.smith, .machine]),
            PhraseCase(phrase: "strength four days with dumbbell and cable", goal: .strength, experience: .intermediate, days: 4, conditioning: false, progression: nil, periodization: nil, equipment: [.dumbbell, .cable]),
            PhraseCase(phrase: "hypertrophy three days with kettlebell and band", goal: .hypertrophy, experience: .intermediate, days: 3, conditioning: false, progression: nil, periodization: nil, equipment: [.kettlebell, .band]),
            PhraseCase(phrase: "cardio two days with bodyweight, autoregulated", goal: .endurance, experience: .intermediate, days: 2, conditioning: true, progression: .autoregulated, periodization: nil, equipment: [.bodyweight])
        ]
    }
}
