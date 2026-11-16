import AppIntents
import Foundation
import Observation

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
        return .result()
    }
}


@MainActor
@Observable
final class WatchLaunchRequests {
    static let shared = WatchLaunchRequests()
    private(set) var pendingStart: CladironWorkoutStyle?

    func requestStart(_ style: CladironWorkoutStyle) { pendingStart = style }
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
