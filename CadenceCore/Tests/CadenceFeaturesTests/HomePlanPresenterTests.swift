import Foundation
import Testing
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct HomePlanPresenterTests {
    @Test func weekStripTapRoutesDirectlyToYourPlan() {
        #expect(HomePlanPresenter.weekStripTapRoute() == .yourPlan)
    }

    @Test func yourPlanDestinationUsesCachedPlan() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let facts = CoachFacts.make(from: [], goal: .hypertrophy, experience: .intermediate, now: now)
        let cached = WeeklyPlan.generate(from: facts, schedulePreferences: .default)

        #expect(HomePlanPresenter.yourPlanDestinationPlan(cachedPlan: cached) == cached)
    }
}
