import Foundation

/// When the Watch sends heart rate to the phone during a phone-started workout.
///
/// Apple Watch produces a new heart-rate reading every few seconds during a
/// workout (often about every 5 s), not every second, so a fixed one-second
/// send mostly repeated the last number, and a fixed five-second send could
/// hold a fresh reading back for up to five seconds. Instead:
///
/// - Each new reading is sent as soon as it arrives, at most one message per
///   `minimumGap` (a reading inside the gap waits for the gap to end).
/// - When nothing new arrives, the last value is resent every
///   `heartbeatInterval`, so the phone can tell a quiet sensor from a dropped
///   connection. The phone treats heart rate as stale after
///   `WatchHRRelay.staleAfter` (three missed heartbeats).
///
/// With the screen off the Watch app runs as a background workout, where
/// watchOS suspends apps that do too much work. Between readings and
/// heartbeats nothing runs: the caller keeps one one-shot timer, scheduled
/// for whichever of the two comes first.
///
/// Times are monotonic (`ProcessInfo.systemUptime`), so a wall-clock change
/// cannot stall the relay.
public struct WatchHRRelaySchedule: Equatable, Sendable {
    public static let minimumGap: TimeInterval = 1
    public static let heartbeatInterval: TimeInterval = 5

    private var lastSentUptime: TimeInterval?
    private var newestReadingEnd: Date?
    /// When the Watch last received a new reading (HealthKit or strap).
    private var lastNewReadingUptime: TimeInterval?

    public init() {}

    /// Records a reading and returns whether it is new. HealthKit readings
    /// carry the end of their sample interval; a reading no newer than one
    /// already seen (the display poll re-reading the builder's latest
    /// statistic, or a callback for a sample the poll already caught) is not
    /// new. Readings without a timestamp (a Bluetooth strap) are always new.
    public mutating func observeReading(endingAt sampleEnd: Date?, uptime: TimeInterval) -> Bool {
        if let sampleEnd {
            if let newestReadingEnd, sampleEnd <= newestReadingEnd { return false }
            newestReadingEnd = sampleEnd
        }
        lastNewReadingUptime = uptime
        return true
    }

    /// Whether no new reading has arrived for longer than the phone's stale
    /// window: the sensor has stopped, so resending the last value would show
    /// a frozen number as live. Measured from arrival on the Watch, not from
    /// the sample's own time, so a reading HealthKit delivers late is still
    /// sent when it arrives.
    public func isNewestReadingStale(uptime: TimeInterval) -> Bool {
        guard let lastNewReadingUptime, uptime >= lastNewReadingUptime else { return false }
        return uptime - lastNewReadingUptime > WatchHRRelay.staleAfter
    }

    /// Seconds to wait before a message may be sent; zero means now.
    public func delayBeforeSending(uptime: TimeInterval) -> TimeInterval {
        guard let lastSentUptime, uptime >= lastSentUptime else { return 0 }
        return max(0, Self.minimumGap - (uptime - lastSentUptime))
    }

    public mutating func recordSend(uptime: TimeInterval) {
        lastSentUptime = uptime
    }

    public mutating func reset() {
        self = WatchHRRelaySchedule()
    }
}
