// Re-exported deliberately: `PlanningConstraintPolicy` is now a typealias of the
// extracted `CadencePlanning.PlanningPolicy`, and every existing client of Core
// (CadenceFeatures, the iOS app target, tests) must keep resolving `.safe` /
// `.meetDeficits` without linking a new product. Remove once clients adopt it.
@_exported import CadencePlanning
import Foundation

/// Boundary adapters from app preference types to the Foundation-only planning domain.
extension RestPreference {
    public var planningRule: PlanningRestRule {
        switch self {
        case .fixed(let days): return .fixed(weekdays: Set(days.map(\.rawValue)))
        case .rolling(let n): return .rolling(everyNDays: n)
        }
    }
}

extension CoachSchedulePreferences {
    public func planningInput(policy: PlanningPolicy = .safe) throws -> PlanningInput {
        try PlanningInput(strengthDaysPerWeek: strengthDaysPerWeek,
                          cardioDaysPerWeek: cardioDaysPerWeek,
                          restRule: restPreference.planningRule,
                          policy: policy)
    }
}
