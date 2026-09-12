import Foundation
import AppIntents

extension Notification.Name {
    static let readinessCheckInChanged = Notification.Name("cadence.readinessCheckInChanged")
    static let cadenceStartTodaysWorkout = Notification.Name("cadence.startTodaysWorkout")
    static let cadenceShowTodaysPlan = Notification.Name("cadence.showTodaysPlan")
}

enum CadenceHandoff {
    static let planActivityType = "guru.parso.ios-workout-app.plan"

    static func activity(title: String, planID: UUID? = nil) -> NSUserActivity {
        let activity = NSUserActivity(activityType: planActivityType)
        activity.title = title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.isEligibleForPublicIndexing = false
        activity.webpageURL = URL(string: "cladiron://plan")
        if let planID {
            activity.userInfo = ["planID": planID.uuidString]
        }
        return activity
    }
}

struct StartTodaysWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Today's Workout"
    static let description = IntentDescription("Open Cladiron and choose today's workout.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .cadenceStartTodaysWorkout, object: nil)
        return .result()
    }
}

struct ShowTodaysPlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Today's Plan"
    static let description = IntentDescription("Open Cladiron to today's self-authored and coach plan.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .cadenceShowTodaysPlan, object: nil)
        return .result()
    }
}

struct CadenceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
            AppShortcut(intent: StartTodaysWorkoutIntent(), phrases: [
                "Start today's workout in \(.applicationName)",
                "Start my workout in \(.applicationName)"
            ], shortTitle: "Start workout", systemImageName: "play.fill")
            AppShortcut(intent: ShowTodaysPlanIntent(), phrases: [
                "Show today's plan in \(.applicationName)",
                "What's my plan today in \(.applicationName)"
            ], shortTitle: "Today's plan", systemImageName: "calendar")
    }
}
