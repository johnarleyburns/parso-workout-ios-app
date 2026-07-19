import Foundation
import CadenceCore

public enum HomePlanPresenter {
    public enum Route: Equatable {
        case yourPlan
    }

    public static func weekStripTapRoute() -> Route {
        .yourPlan
    }

    public static func yourPlanDestinationPlan(cachedPlan: WeeklyPlan) -> WeeklyPlan {
        cachedPlan
    }
}
