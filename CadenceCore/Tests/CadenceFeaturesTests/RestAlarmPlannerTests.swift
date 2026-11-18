import Foundation
import Testing
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

struct RestAlarmPlannerTests {
    @Test func startExtendAndCancel() {
        var planner = RestAlarmPlanner()
        let start = Date(timeIntervalSince1970: 100)
        #expect(planner.start(endsAt: start) == .schedule(start))
        let extended = start.addingTimeInterval(30)
        #expect(planner.extend(to: extended) == .schedule(extended))
        #expect(planner.skip() == .cancel)
        #expect(planner.endsAt == nil)
    }

    @Test func watchOwnedRestNeverSchedulesPhoneAlarm() {
        var planner = RestAlarmPlanner()
        #expect(planner.start(endsAt: Date(), watchOwnsCue: true) == .cancel)
        #expect(planner.extend(to: Date().addingTimeInterval(30)) == .cancel)
    }

    @Test func endWorkoutAlwaysCancels() {
        var planner = RestAlarmPlanner()
        _ = planner.start(endsAt: Date())
        #expect(planner.endWorkout() == .cancel)
        #expect(planner.endsAt == nil)
    }
}
