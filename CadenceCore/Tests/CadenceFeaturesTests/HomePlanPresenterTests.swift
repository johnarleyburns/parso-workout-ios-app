import XCTest
import CadenceCore
import CadenceFeatures

final class HomePlanPresenterTests: XCTestCase {
    func testWeekStripTapRoutesDirectlyToYourPlan() {
        XCTAssertEqual(HomePlanPresenter.weekStripTapRoute(), .yourPlan)
    }

    func testYourPlanDestinationUsesCachedPlan() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let facts = CoachFacts.make(from: [], goal: .hypertrophy, experience: .intermediate, now: now)
        let cached = WeeklyPlan.generate(from: facts, schedulePreferences: .default)

        XCTAssertEqual(HomePlanPresenter.yourPlanDestinationPlan(cachedPlan: cached), cached)
    }
}
