import Foundation

public enum WatchSwimMode: String, CaseIterable, Identifiable, Sendable {
    case lapPool, openWater
    public var id: Self { self }
}

public enum WatchSwimSetup {
    public static func configuration(mode: WatchSwimMode, poolLength: Double) -> WorkoutConfigurationSpec {
        WorkoutConfigurationSpec(kind: .swim, location: mode == .openWater
            ? .openWater : .pool(lapLength: poolLength == 50 ? 50 : 25))
    }

    public static func shouldWaterLock(pending: Bool, running: Bool,
                                       foreground: Bool, supported: Bool) -> Bool {
        pending && running && foreground && supported
    }
}

/// HealthKit's cumulative pool-swimming measurement is the single source of
/// truth. Never add lap/segment events to it: those can describe the same turn.
public struct WatchSwimProgress: Equatable, Sendable {
    public let poolLengthMeters: Double?
    public private(set) var distanceMeters: Double = 0
    public var lapCount: Int? {
        guard let poolLengthMeters else { return nil }
        return Int(floor(distanceMeters / poolLengthMeters))
    }

    public init(poolLengthMeters: Double?) {
        self.poolLengthMeters = poolLengthMeters.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    public mutating func update(distanceMeters: Double) {
        guard distanceMeters.isFinite, distanceMeters >= 0 else { return }
        if let poolLengthMeters, distanceMeters / poolLengthMeters >= Double(Int.max) { return }
        self.distanceMeters = max(self.distanceMeters, distanceMeters)
    }
}
