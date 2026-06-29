import Foundation

public struct WorkoutSettings: Codable, Equatable, Sendable {
    public var restSeconds: Int
    public var autoStartRest: Bool
    public var preWorkoutCountdown: Int
    public var autoEndOnIdle: Bool
    public var idleTimeoutMinutes: Int
    public var plateRounding: Bool
    public var gpsHighAccuracy: Bool
    public var autoPause: Bool
    public var intervalColorBlind: Bool
    public var spokenCues: Bool
    public var weeklyCardioMinutesGoal: Int
    public var warmupMinutes: Int
    public var cooldownMinutes: Int
    public var useHRMonitoring: Bool

    public init(restSeconds: Int = 90,
                autoStartRest: Bool = true,
                preWorkoutCountdown: Int = 10,
                autoEndOnIdle: Bool = true,
                idleTimeoutMinutes: Int = 10,
                plateRounding: Bool = false,
                gpsHighAccuracy: Bool = false,
                autoPause: Bool = false,
                intervalColorBlind: Bool = false,
                spokenCues: Bool = false,
                weeklyCardioMinutesGoal: Int = 250,
                warmupMinutes: Int = 5,
                cooldownMinutes: Int = 5,
                useHRMonitoring: Bool = false) {
        self.restSeconds = restSeconds
        self.autoStartRest = autoStartRest
        self.preWorkoutCountdown = preWorkoutCountdown
        self.autoEndOnIdle = autoEndOnIdle
        self.idleTimeoutMinutes = idleTimeoutMinutes
        self.plateRounding = plateRounding
        self.gpsHighAccuracy = gpsHighAccuracy
        self.autoPause = autoPause
        self.intervalColorBlind = intervalColorBlind
        self.spokenCues = spokenCues
        self.weeklyCardioMinutesGoal = weeklyCardioMinutesGoal
        self.warmupMinutes = warmupMinutes
        self.cooldownMinutes = cooldownMinutes
        self.useHRMonitoring = useHRMonitoring
    }

    public static let `default` = WorkoutSettings()
}
