import Foundation
import AppIntents
import CadenceCore
import CadenceFeatures

extension Notification.Name {
    static let readinessCheckInChanged = Notification.Name("cadence.readinessCheckInChanged")
    static let cadenceStartTodaysWorkout = Notification.Name("cadence.startTodaysWorkout")
    static let cadenceShowTodaysPlan = Notification.Name("cadence.showTodaysPlan")
    static let cadenceShowThisWeek = Notification.Name("cadence.showThisWeek")
    static let cadenceLogSetRequested = Notification.Name("cadence.logSetRequested")
}

enum CadenceHandoff {
    static let planActivityType = "guru.parso.ios-workout-app.plan"

    static func activity(title: String, planID: UUID? = nil) -> NSUserActivity {
        let activity = NSUserActivity(activityType: planActivityType)
        activity.title = title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.isEligibleForPublicIndexing = false
        // `webpageURL` must be a real HTTP(S) webpage/universal link. The app's
        // custom `cladiron://` route is handled by RootTabView's `onOpenURL` and
        // assigning it here causes NSUserActivity to abort on device.
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
        CadencePlatformRequestStore.requestStartWorkout()
        NotificationCenter.default.post(name: .cadenceStartTodaysWorkout, object: nil)
        return .result()
    }
}

struct ExerciseEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Exercise")
    static let defaultQuery = ExerciseEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct ExerciseEntityQuery: EntityQuery {
    func entities(for identifiers: [ExerciseEntity.ID]) async throws -> [ExerciseEntity] {
        identifiers.compactMap { id in
            ExerciseLibrary.template(matching: id).map { ExerciseEntity(id: $0.name, name: $0.name) }
        }
    }

    func suggestedEntities() async throws -> [ExerciseEntity] {
        ExerciseLibrary.starter.map { ExerciseEntity(id: $0.name, name: $0.name) }
    }
}

struct LogSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Set"
    static let description = IntentDescription("Log a set in the active Cladiron workout.")
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Exercise") var exercise: ExerciseEntity
    @Parameter(title: "Weight") var weight: Measurement<UnitMass>
    @Parameter(title: "Reps") var reps: Int

    init() {
        exercise = ExerciseEntity(id: "Bench Press", name: "Bench Press")
        weight = Measurement(value: 0, unit: UnitMass.kilograms)
        reps = 0
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard weight.value >= 0, reps > 0 else {
            return .result(dialog: "Enter a valid weight and at least one rep.")
        }
        let request = CadencePlatformRequestStore.LogSetRequest(
            exerciseName: exercise.name,
            weightKg: weight.converted(to: .kilograms).value,
            reps: reps)
        CadencePlatformRequestStore.requestLogSet(request)
        NotificationCenter.default.post(name: .cadenceLogSetRequested, object: request)
        return .result(dialog: "Open Cladiron to log this set in your active workout.")
    }
}

struct ShowTodaysPlanIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Today's Plan"
    static let description = IntentDescription("Open Cladiron to today's planned workouts.")
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
            AppShortcut(intent: LogSetIntent(), phrases: [
                "Log a set in \(.applicationName)",
                "Record a set in \(.applicationName)"
            ], shortTitle: "Log set", systemImageName: "checkmark.circle")
    }
}
