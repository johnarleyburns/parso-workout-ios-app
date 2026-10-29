import XCTest
import CadenceCore
@testable import CadenceFeatures

final class HealthKitWorkoutOriginPresenterTests: XCTestCase {
    private func p(source: String = "", device: String? = nil, model: String? = nil,
                   brand: String? = nil, plus: Bool = false,
                   product: String? = nil) -> HealthKitWorkoutProvenance {
        HealthKitWorkoutProvenance(sourceName: source, sourceBundleIdentifier: "com.x",
                                   productType: product, deviceName: device, deviceModel: model,
                                   workoutBrandName: brand, isAppleFitnessPlus: plus)
    }

    func testPrecedence() {
        let l = HealthKitWorkoutOriginPresenter.label
        XCTAssertEqual(l(p(source: "S", brand: "B", plus: true)).primary, "Imported from Apple Fitness+")
        XCTAssertEqual(l(p(source: "S", brand: "Peloton")).primary, "Imported from Peloton")
        XCTAssertEqual(l(p(source: "Strava", device: "Apple Watch")).primary, "Imported from Strava on Apple Watch")
        XCTAssertEqual(l(p(source: "Strava")).primary, "Imported from Strava")
        XCTAssertEqual(l(p(model: "Garmin Edge")).primary, "Imported from Garmin Edge")
        XCTAssertEqual(l(p()).primary, "Imported from HealthKit")
        XCTAssertEqual(l(nil).primary, "Imported from HealthKit")
    }

    func testBlankBrandAndDuplicateDevice() {
        let a = HealthKitWorkoutOriginPresenter.label(for: p(source: "Strava", brand: "  "))
        XCTAssertEqual(a.primary, "Imported from Strava")
        let b = HealthKitWorkoutOriginPresenter.label(for: p(source: "Wahoo", device: "wahoo"))
        XCTAssertEqual(b.primary, "Imported from Wahoo")
        XCTAssertEqual(b.detail, "Wahoo")
    }

    func testWatchProductTypeAloneNeverImpliesFitness() {
        let r = HealthKitWorkoutOriginPresenter.label(for: p(product: "Watch7,1"))
        XCTAssertEqual(r.primary, "Imported from HealthKit")
    }

    func testAccessibilityDetailAndNoBundleID() {
        let r = HealthKitWorkoutOriginPresenter.label(for: p(source: "Strava", device: "Apple Watch"))
        XCTAssertEqual(r.accessibilityLabel, "Imported from Strava on Apple Watch. Recorded by Strava on Apple Watch")
        XCTAssertFalse(r.accessibilityLabel.contains("com.x"))
    }
}
