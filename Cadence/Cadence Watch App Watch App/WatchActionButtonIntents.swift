import AppIntents
import Foundation
import Observation

/// Watch redesign D-W5 — the Ultra Action Button: **Start** outside a workout, **Talk** inside one.
/// `StartCladironWorkoutIntent` is the workout-app Action Button intent; its result hands the
/// button to `WatchQuickTalkActionIntent` for the rest of that workout. The Smart Stack card's
/// Start (`cladiron://start`) takes the same path, so there is one way in.
enum CladironWorkoutStyle: String, AppEnum {
    case todaysPlan
    case quickLift

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Workout")
    static let caseDisplayRepresentations: [CladironWorkoutStyle: DisplayRepresentation] = [
        .todaysPlan: DisplayRepresentation(title: "Today's Plan", image: .init(systemName: "calendar")),
        .quickLift: DisplayRepresentation(title: "Quick Lift", image: .init(systemName: "dumbbell.fill"))
    ]
}

struct StartCladironWorkoutIntent: StartWorkoutIntent {
    static let title: LocalizedStringResource = "Start Workout"
    static let description = IntentDescription("Starts today's planned workout, or a quick lift.")

    @Parameter(title: "Workout") var workoutStyle: CladironWorkoutStyle

    static var suggestedWorkouts: [StartCladironWorkoutIntent] {
        [StartCladironWorkoutIntent(style: .todaysPlan), StartCladironWorkoutIntent(style: .quickLift)]
    }

    var displayRepresentation: DisplayRepresentation {
        CladironWorkoutStyle.caseDisplayRepresentations[workoutStyle]
            ?? DisplayRepresentation(title: "Start Workout")
    }

    init() { workoutStyle = .todaysPlan }

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchLaunchRequests.shared.requestStart(workoutStyle)
        return .result(actionButtonIntent: WatchQuickTalkActionIntent())
    }
}

/// During a workout the Action Button starts Quick Talk (the same as holding Log set).
struct WatchQuickTalkActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Log a Set"
    static let description = IntentDescription("Listens for a set while a Cladiron workout is running.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchLaunchRequests.shared.requestTalk()
        return .result()
    }
}

/// What the Action Button or the Smart Stack card asked for, consumed by the visible screen:
/// Today starts the workout; the running workout starts Quick Talk.
@MainActor
@Observable
final class WatchLaunchRequests {
    static let shared = WatchLaunchRequests()
    private(set) var pendingStart: CladironWorkoutStyle?
    private(set) var talkRequest = 0

    func requestStart(_ style: CladironWorkoutStyle) { pendingStart = style }
    func requestTalk() { talkRequest += 1 }
    func consumeStart() -> CladironWorkoutStyle? {
        defer { pendingStart = nil }
        return pendingStart
    }

    /// `cladiron://start` (Smart Stack) → today's plan; `cladiron://start?style=quickLift` → quick lift.
    func handle(_ url: URL) {
        guard url.scheme == "cladiron", url.host() == "start" else { return }
        let style = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "style" }?.value
        requestStart(style.flatMap(CladironWorkoutStyle.init(rawValue:)) ?? .todaysPlan)
    }
}
