import Foundation

public struct ElapsedTimeTracker {
    public private(set) var totalPausedDuration: TimeInterval = 0
    private var pauseStart: Date?

    public var isPaused: Bool { pauseStart != nil }

    public init() {}

    public mutating func startPause(now: Date = Date()) {
        guard pauseStart == nil else { return }
        pauseStart = now
    }

    public mutating func resume(now: Date = Date()) {
        guard let start = pauseStart else { return }
        totalPausedDuration += now.timeIntervalSince(start)
        pauseStart = nil
    }

    public mutating func togglePause(now: Date = Date()) {
        if isPaused { resume(now: now) } else { startPause(now: now) }
    }

    public func elapsed(since sessionStart: Date, now: Date = Date()) -> TimeInterval {
        let wallClock = now.timeIntervalSince(sessionStart)
        let currentPause: TimeInterval = {
            if let start = pauseStart { return now.timeIntervalSince(start) }
            return 0
        }()
        return max(0, wallClock - totalPausedDuration - currentPause)
    }

    public mutating func reset() {
        totalPausedDuration = 0
        pauseStart = nil
    }
}
