import HealthKit

/// The workout configuration the phone hands the Watch when it opens Cladiron
/// there with `HKHealthStore.startWatchApp(with:completion:)`.
///
/// The Watch starts its workout from this configuration as soon as it
/// launches, before the phone's `start_workout` command arrives to name it, so
/// the activity mirrors `WatchWorkoutManager.activityType(for:)` for the same
/// command type: the workout is the same whichever message wins.
enum WatchWorkoutLaunch {
    static func configuration(forRawType rawType: String) -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activityType(forRawType: rawType)
        if configuration.activityType == .swimming {
            // A swimming configuration needs a location; this matches the
            // Watch's default pool setup for a phone-started swim.
            configuration.swimmingLocationType = .pool
            configuration.lapLength = HKQuantity(unit: .meter(), doubleValue: 25)
        }
        return configuration
    }

    static func activityType(forRawType rawType: String) -> HKWorkoutActivityType {
        switch rawType {
        case "boxing": return .boxing
        case "hiit": return .highIntensityIntervalTraining
        case "run": return .running
        case "cycle": return .cycling
        case "swim": return .swimming
        case "walk": return .walking
        case "rowing": return .rowing
        case "other": return .other
        default: return .functionalStrengthTraining
        }
    }
}
