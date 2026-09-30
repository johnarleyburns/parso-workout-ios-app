import XCTest
import Foundation
import CadenceFeatures

final class RestAlarmPlannerTests: XCTestCase {
    func testStartExtendAndCancel() {
        var planner = RestAlarmPlanner()
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(planner.start(endsAt: start), .schedule(start))
        let extended = start.addingTimeInterval(30)
        XCTAssertEqual(planner.extend(to: extended), .schedule(extended))
        XCTAssertEqual(planner.skip(), .cancel)
        XCTAssertNil(planner.endsAt)
    }

    func testWatchOwnedRestNeverSchedulesPhoneAlarm() {
        var planner = RestAlarmPlanner()
        XCTAssertEqual(planner.start(endsAt: Date(), watchOwnsCue: true), .cancel)
        XCTAssertEqual(planner.extend(to: Date().addingTimeInterval(30)), .cancel)
    }

    func testEndWorkoutAlwaysCancels() {
        var planner = RestAlarmPlanner()
        _ = planner.start(endsAt: Date())
        XCTAssertEqual(planner.endWorkout(), .cancel)
        XCTAssertNil(planner.endsAt)
    }
}
