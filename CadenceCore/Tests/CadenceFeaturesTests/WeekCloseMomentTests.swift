import Testing
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct WeekCloseMomentTests {
    @Test func weekCloseRequiresBothGoals() {
        #expect(WeekCloseMoment.make(workingSets: 12, setTarget: 12,
                                      cardioMinutes: 20, cardioTarget: 30) == nil)
        #expect(WeekCloseMoment.make(workingSets: 12, setTarget: 12,
                                      cardioMinutes: 30, cardioTarget: 30)?.title == "Week complete")
    }
}
