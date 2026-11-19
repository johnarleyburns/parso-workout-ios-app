import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct ThisWeekWorkoutsPresenterTests {
    @Test func summaryVariants() {
        #expect(ThisWeekWorkoutsPresenter.summary(planned: 3, done: 2) == "3 workouts planned, 2 workouts done")
        #expect(ThisWeekWorkoutsPresenter.summary(planned: 3, done: 0) == "3 workouts planned")
        #expect(ThisWeekWorkoutsPresenter.summary(planned: 0, done: 2) == "2 workouts done")
        #expect(ThisWeekWorkoutsPresenter.summary(planned: 0, done: 0) == "No workouts planned or done")
    }
}
