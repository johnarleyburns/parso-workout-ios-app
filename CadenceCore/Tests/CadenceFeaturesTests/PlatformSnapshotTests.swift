import XCTest
import CadenceCore
import CadenceWorkoutFeatures

final class PlatformReadinessTests: XCTestCase {
    func testReadinessPresenterKeepsSafetyCopySeparate() {
        let concern = ReadinessEntry(muscleSoreness: 1, fatigueEnergy: 2,
                                     sleepQuality: 2, stressMood: 1,
                                     hasPainOrIllnessConcern: true)
        XCTAssertEqual(ReadinessCheckInPresenter.summary(for: concern), "Pain or illness noted")
        XCTAssertTrue(ReadinessCheckInPresenter.detail(for: concern).contains("/5"))
        XCTAssertTrue(ReadinessCheckInPresenter.validate(muscleSoreness: 1,
                                                         fatigueEnergy: 5,
                                                         sleepQuality: 3,
                                                         stressMood: 4))
        XCTAssertFalse(ReadinessCheckInPresenter.validate(muscleSoreness: 0,
                                                          fatigueEnergy: 5,
                                                          sleepQuality: 3,
                                                          stressMood: 4))
    }
}
