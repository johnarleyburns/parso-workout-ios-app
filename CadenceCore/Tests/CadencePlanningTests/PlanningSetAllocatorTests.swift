import Foundation
import Testing
@testable import CadencePlanning

/// Golden contract fixtures; identical on macOS and Linux CI.
struct PlanningSetAllocatorTests {
    @Test func zeroHistoryDefaultsClampToPolicy() {
        func sets(_ requested: Int?, _ policy: PlanningPolicy) -> Int {
            PlanningSetAllocator.plannedSets(requestedSets: requested, desiredSetsPerExercise: 3,
                perSetContribution: [:], deficits: [:], projected: [:], mrv: [:], policy: policy)
        }
        #expect(sets(nil, .safe) == 3)
        #expect(sets(1, .safe) == 2)
        #expect(sets(10, .safe) == 4)
        #expect(sets(10, .meetDeficits) == 8)
    }

    @Test func deficitsDriveSetsAndMRVCaps() {
        let args = (c: ["quads": 1.0], d: ["quads": 6.0])
        let safe = PlanningSetAllocator.plannedSets(requestedSets: 3, desiredSetsPerExercise: 3,
            perSetContribution: args.c, deficits: args.d, projected: ["quads": 18], mrv: ["quads": 20], policy: .safe)
        #expect(safe == 2)
        let free = PlanningSetAllocator.plannedSets(requestedSets: 3, desiredSetsPerExercise: 3,
            perSetContribution: args.c, deficits: args.d, projected: ["quads": 18], mrv: ["quads": 20], policy: .meetDeficits)
        #expect(free == 6)
        let unrelated = PlanningSetAllocator.plannedSets(requestedSets: 3, desiredSetsPerExercise: 3,
            perSetContribution: ["lats": 1], deficits: args.d, projected: [:], mrv: [:], policy: .safe)
        #expect(unrelated == 0)
    }

    @Test func loadRoundingHandlesMalformedInput() {
        #expect(PlanningSetAllocator.roundedLoad(82.74) == 82.5)
        #expect(PlanningSetAllocator.roundedLoad(0) == nil)
        #expect(PlanningSetAllocator.roundedLoad(-5) == nil)
    }

    @Test func deficitTiesAreDeterministic() {
        let order = ["a": 2, "b": 1, "c": 3]
        let result = PlanningSetAllocator.deficitOrdered(["a": 1, "b": 1, "c": 5, "z": 1]) { order[$0] ?? Int.max }
        #expect(result == ["c", "b", "a", "z"])
    }

    @Test func hardStrengthGating() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let later = now.addingTimeInterval(3600)
        #expect(!PlanningSetAllocator.hardStrengthAllowed(isRestDay: true, plannedMiddayTime: now, wholeBodyHardEligibleAt: nil, policy: .safe))
        #expect(PlanningSetAllocator.hardStrengthAllowed(isRestDay: true, plannedMiddayTime: now, wholeBodyHardEligibleAt: nil, policy: .meetDeficits))
        #expect(!PlanningSetAllocator.hardStrengthAllowed(isRestDay: false, plannedMiddayTime: now, wholeBodyHardEligibleAt: later, policy: .safe))
        #expect(PlanningSetAllocator.hardStrengthAllowed(isRestDay: false, plannedMiddayTime: later, wholeBodyHardEligibleAt: later, policy: .safe))
    }

    @Test func rollingRestRuleFixture() {
        #expect(PlanningRestRule.isRestDay(weekday: 1, daysSinceWeekStart: 0, rule: .rolling(everyNDays: 2)) == false)
        #expect(PlanningRestRule.isRestDay(weekday: 4, daysSinceWeekStart: 2, rule: .rolling(everyNDays: 2)))
        #expect(PlanningRestRule.isRestDay(weekday: 1, daysSinceWeekStart: 0, rule: .fixed(weekdays: [1])))
    }
}
