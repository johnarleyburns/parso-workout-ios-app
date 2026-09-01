import XCTest
@testable import CadenceCore

final class TrainingEngineBridgeTests: XCTestCase {
    func testBundledEndurancePolicyProvidesAppDefaults() throws {
        let defaults = try XCTUnwrap(
            TrainingEngineBridge.goalDefaults(policyId: "general-endurance-v1")
        )

        XCTAssertEqual(defaults.reps, 15...20)
        XCTAssertEqual(defaults.rir, 2)
        XCTAssertEqual(TrainingGoal.endurance.repRange, defaults.reps)
        XCTAssertEqual(TrainingGoal.endurance.targetRIR, defaults.rir)
    }

    func testEnduranceFallbackMatchesPolicyWhenEngineIsUnavailable() {
        let unavailable = TrainingEngineBridge.goalDefaults(
            policyId: "general-endurance-v1",
            useSharedEngine: false
        )

        XCTAssertNil(unavailable)
        XCTAssertEqual(unavailable?.reps ?? 15...20, 15...20)
        XCTAssertEqual(unavailable?.rir ?? 2, 2)
    }

    func testUnknownGoalPolicyDoesNotProduceDefaults() {
        XCTAssertNil(TrainingEngineBridge.goalDefaults(policyId: "unknown-policy"))
    }
}
