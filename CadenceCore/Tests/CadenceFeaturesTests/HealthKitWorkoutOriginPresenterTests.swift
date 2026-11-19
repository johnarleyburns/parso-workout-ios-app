import Testing
import CadenceCore
import CadencePhoneFeatures
@testable import CadenceFeatures
@testable import CadenceWorkoutFeatures

struct HealthKitWorkoutOriginPresenterTests {
    private func p(source: String = "", device: String? = nil, model: String? = nil,
                   brand: String? = nil, plus: Bool = false,
                   product: String? = nil) -> HealthKitWorkoutProvenance {
        HealthKitWorkoutProvenance(sourceName: source, sourceBundleIdentifier: "com.x",
                                   productType: product, deviceName: device, deviceModel: model,
                                   workoutBrandName: brand, isAppleFitnessPlus: plus)
    }

    @Test func precedence() {
        let l = HealthKitWorkoutOriginPresenter.label
        #expect(l(p(source: "S", brand: "B", plus: true)).primary == "Imported from Apple Fitness+")
        #expect(l(p(source: "S", brand: "Peloton")).primary == "Imported from Peloton")
        #expect(l(p(source: "Strava", device: "Apple Watch")).primary == "Imported from Strava on Apple Watch")
        #expect(l(p(source: "Strava")).primary == "Imported from Strava")
        #expect(l(p(model: "Garmin Edge")).primary == "Imported from Garmin Edge")
        #expect(l(p()).primary == "Imported from HealthKit")
        #expect(l(nil).primary == "Imported from HealthKit")
    }

    @Test func blankBrandAndDuplicateDevice() {
        let a = HealthKitWorkoutOriginPresenter.label(for: p(source: "Strava", brand: "  "))
        #expect(a.primary == "Imported from Strava")
        let b = HealthKitWorkoutOriginPresenter.label(for: p(source: "Wahoo", device: "wahoo"))
        #expect(b.primary == "Imported from Wahoo")
        #expect(b.detail == "Wahoo")
    }

    @Test func watchProductTypeAloneNeverImpliesFitness() {
        let r = HealthKitWorkoutOriginPresenter.label(for: p(product: "Watch7,1"))
        #expect(r.primary == "Imported from HealthKit")
    }

    @Test func accessibilityDetailAndNoBundleID() {
        let r = HealthKitWorkoutOriginPresenter.label(for: p(source: "Strava", device: "Apple Watch"))
        #expect(r.accessibilityLabel == "Imported from Strava on Apple Watch. Recorded by Strava on Apple Watch")
        #expect(!r.accessibilityLabel.contains("com.x"))
    }
}
