import Foundation

/// Content-free lifecycle events for the Home launch and This Week paths.
/// Production keeps using `OSSignposter`; tests receive the same names through
/// a `HomePerformanceEventSink`. Events never carry workout data, identifiers,
/// cache keys, or user information.
public enum HomePerformanceEvent: String, Sendable, CaseIterable {
    case firstTodayFrame, heroRestored, suggestionRestored
    case historyReadStarted, coachIdentityEvaluated, fullSnapshotStarted
    case weeklyProjectionStarted, weeklyProjectionPublished
    case thisWeekInteractive
}

public protocol HomePerformanceEventSink: Sendable {
    func record(_ event: HomePerformanceEvent)
}

/// Thread-safe recording sink with monotonic timestamps (UI-test/debug use).
public final class RecordingHomePerformanceEventSink: HomePerformanceEventSink, @unchecked Sendable {
    public struct Entry: Sendable, Equatable {
        public let event: HomePerformanceEvent
        public let uptimeNanoseconds: UInt64
    }
    private let lock = NSLock()
    private var storage: [Entry] = []
    private let clock: @Sendable () -> UInt64

    public init(clock: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.clock = clock
    }

    public func record(_ event: HomePerformanceEvent) {
        let now = clock()
        lock.lock(); defer { lock.unlock() }
        storage.append(Entry(event: event, uptimeNanoseconds: now))
    }

    public var entries: [Entry] { lock.lock(); defer { lock.unlock() }; return storage }
    public var events: [HomePerformanceEvent] { entries.map(\.event) }
}

/// Event-ordering contract (the hard CI gate; wall-clock budgets are separate).
public enum HomePerformanceContract {
    /// Events that mean history/identity/full-snapshot work has begun.
    public static let heavyEvents: Set<HomePerformanceEvent> =
        [.historyReadStarted, .coachIdentityEvaluated, .fullSnapshotStarted]

    /// Returns human-readable violations (empty when the trace is valid).
    public static func violations(in events: [HomePerformanceEvent]) -> [String] {
        var out: [String] = []
        func first(_ e: HomePerformanceEvent) -> Int? { events.firstIndex(of: e) }
        let firstHeavy = heavyEvents.compactMap(first).min()
        for restored in [HomePerformanceEvent.heroRestored, .suggestionRestored] {
            guard let r = first(restored) else { out.append("missing \(restored.rawValue)"); continue }
            if let h = firstHeavy, h < r { out.append("\(restored.rawValue) after heavy work") }
        }
        if let f = first(.firstTodayFrame), let h = firstHeavy, h < f {
            out.append("heavy work before firstTodayFrame")
        }
        if let s = first(.weeklyProjectionStarted), let p = first(.weeklyProjectionPublished), p < s {
            out.append("projection published before start")
        }
        if let i = first(.thisWeekInteractive), let p = first(.weeklyProjectionPublished), p < i {
            out.append("thisWeekInteractive after projection published (not interactive during projection)")
        }
        if first(.thisWeekInteractive) == nil { out.append("missing thisWeekInteractive") }
        return out
    }
}
