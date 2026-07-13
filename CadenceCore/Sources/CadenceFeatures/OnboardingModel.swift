import Foundation
import Observation
import CadenceCore

/// The first-run flow's state machine, lifted out of `OnboardingView` (test-pyramid
/// Phase 4). Holds the collected selections + step index and exposes pure
/// transitions and derived state (footer title, primary action, schedule
/// preferences, program preview). The view binds to it and renders; the logic is
/// unit-tested instead of driven through nine flaky simulator tests.
@Observable
public final class OnboardingModel {
    /// What the primary footer button does on the current step.
    public enum PrimaryAction: Equatable {
        case advance      // go to the next page
        case complete     // final step → present the paywall / finish
    }

    public let lastStep: Int
    public var step: Int
    public var goal: TrainingGoal
    public var experience: ExperienceLevel
    public var unit: MeasurementUnitPreference
    public var strengthDays: Int
    public var cardioDays: Int
    public var age: Int
    public var ageProvided: Bool

    public init(goal: TrainingGoal = .strength,
                experience: ExperienceLevel = .intermediate,
                unit: MeasurementUnitPreference = .pounds,
                strengthDays: Int = 2,
                cardioDays: Int = 3,
                age: Int = 40,
                ageProvided: Bool = false,
                step: Int = 0,
                lastStep: Int = 6) {
        self.goal = goal
        self.experience = experience
        self.unit = unit
        self.strengthDays = strengthDays
        self.cardioDays = cardioDays
        self.age = age
        self.ageProvided = ageProvided
        self.step = step
        self.lastStep = lastStep
    }

    public var isLastStep: Bool { step >= lastStep }
    public var canGoBack: Bool { step > 0 }

    /// The final-step ("program ready") page presents the paywall; every other
    /// primary tap advances.
    public var primaryAction: PrimaryAction { isLastStep ? .complete : .advance }

    /// Footer button title per step (index 5 is the medical disclaimer).
    public var footerTitle: String {
        switch step {
        case lastStep: return "Start training with the Coach"
        case 5: return "I understand"
        default: return "Continue"
        }
    }

    public func advance() { if step < lastStep { step += 1 } }
    public func back() { if step > 0 { step -= 1 } }

    /// The schedule preferences the user's day choices imply.
    public var schedulePreferences: CoachSchedulePreferences {
        CoachSchedulePreferences(
            strengthDaysPerWeek: strengthDays,
            cardioDaysPerWeek: cardioDays,
            restPreference: .defaultRolling,
            allowsTwoADays: false,
            sameDayCardioTiming: .afterStrength)
    }

    /// The program preview shown on the final page — the pure weekly plan the
    /// chosen goal/experience/schedule generate.
    public func previewPlan(formula: OneRepMaxFormula) -> WeeklyPlan {
        let facts = CoachFacts.make(from: [], goal: goal, experience: experience, formula: formula)
        return WeeklyPlan.generate(from: facts, schedulePreferences: schedulePreferences)
    }

    /// The age to persist on finish — nil unless the user actually set it, so the
    /// HR-zone estimator keeps its 40-year default (US median).
    public var persistedAge: Int? { ageProvided ? age : nil }
}
