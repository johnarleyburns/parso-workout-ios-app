import Foundation
import CadenceCore

public enum PlannedDayPreviewPresenter {
    public static let restFooterText = String(localized: "This is a rest day, enjoy it, you earned it!", bundle: .module)
    public static let plannedFooterText = String(localized: "This is a planned day. Start it from the Workout tab when it's today.", bundle: .module)

    public static func footerText(for day: WeeklyPlan.DayOutline) -> String {
        guard !day.sessions.isEmpty,
              day.sessions.allSatisfy(\.isRest)
        else {
            return plannedFooterText
        }
        return restFooterText
    }

    public static func strengthPrescription(goal: TrainingGoal, sets: Int) -> String {
        let setCount = min(4, max(3, sets))
        let ladder = RepLadder.ladder(for: goal, sets: setCount)
        let reps = ladder.map(String.init).joined(separator: "-")
        return String(localized: "\(setCount) sets · \(reps) reps · ~\(goal.targetRIR) RIR", bundle: .module)
    }
}
