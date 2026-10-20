import CadencePlanning
import Foundation
import Testing
@testable import CadenceCore

struct PlanningAdapterParityTests {
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
