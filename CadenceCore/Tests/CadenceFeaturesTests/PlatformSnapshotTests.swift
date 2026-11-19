import Testing
import CadenceCore
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct PlatformReadinessTests {
    @Test func readinessPresenterKeepsSafetyCopySeparate() {
        let concern = ReadinessEntry(muscleSoreness: 1, fatigueEnergy: 2,
                                     sleepQuality: 2, stressMood: 1,
                                     hasPainOrIllnessConcern: true)
        #expect(ReadinessCheckInPresenter.summary(for: concern) == "Pain or illness noted")
        #expect(ReadinessCheckInPresenter.detail(for: concern).contains("/5"))
        #expect(ReadinessCheckInPresenter.validate(muscleSoreness: 1,
                                                         fatigueEnergy: 5,
                                                         sleepQuality: 3,
                                                         stressMood: 4))
        #expect(!ReadinessCheckInPresenter.validate(muscleSoreness: 0,
                                                          fatigueEnergy: 5,
                                                          sleepQuality: 3,
                                                          stressMood: 4))
    }
}
