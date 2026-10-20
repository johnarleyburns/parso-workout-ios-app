import CadencePlanning
import Foundation
import Testing
@testable import CadenceCore

struct PlanningAdapterParityTests {
    @Test func preferencesAdaptToPlanningInput() throws {
        let prefs = CoachSchedulePreferences(strengthDaysPerWeek: 4, cardioDaysPerWeek: 2,
                                             restPreference: .fixed(days: [.sunday, .wednesday]))
        let input = try prefs.planningInput()
        #expect(input.strengthDaysPerWeek == 4)
        #expect(input.cardioDaysPerWeek == 2)
        #expect(input.restRule == .fixed(weekdays: [1, 4]))
        #expect(input.policy == PlanningConstraintPolicy.safe)
    }

    @Test func rollingRestRuleMatchesLegacyFormula() {
        for n in 1...6 {
            let rule = RestPreference.rolling(everyNDays: n).planningRule
            for d in 0..<14 {
                let legacy = d > 0 && d % (n + 1) == n
                #expect(PlanningRestRule.isRestDay(weekday: 1, daysSinceWeekStart: d, rule: rule) == legacy)
            }
        }
    }

    @Test func fixedRestRuleMatchesWeekday() {
        let rule = RestPreference.fixed(days: [.monday]).planningRule
        for wd in Weekday.allCases {
            #expect(PlanningRestRule.isRestDay(weekday: wd.rawValue, daysSinceWeekStart: 0, rule: rule) == (wd == .monday))
        }
    }
}
