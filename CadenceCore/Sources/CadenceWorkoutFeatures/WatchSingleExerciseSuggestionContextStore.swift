import CadenceFeatures
import Foundation
import CadenceCore

/// Storage backend for `WatchSingleExerciseSuggestionContextStore`, so tests can
/// substitute an in-memory double instead of real `UserDefaults`/preferences-daemon
/// IPC (which is slow and, run concurrently across many test instances, has been
/// observed to exhaust Swift Testing's cooperative thread pool and hang).
public protocol WatchSingleExerciseSuggestionContextStoring: AnyObject {
    func loadData() -> Data?
    func saveData(_ data: Data)
    func deleteData()
}

public final class InMemoryWatchSingleExerciseSuggestionContextStore:
    WatchSingleExerciseSuggestionContextStoring, @unchecked Sendable {
    private var data: Data?
    public init() {}
    public func loadData() -> Data? { data }
    public func saveData(_ data: Data) { self.data = data }
    public func deleteData() { data = nil }
}

public final class UserDefaultsWatchSingleExerciseSuggestionContextStore:
    WatchSingleExerciseSuggestionContextStoring, @unchecked Sendable {
    private let defaults: DefaultsStoring
    private let key: String

    public init(defaults: DefaultsStoring = UserDefaults.standard,
               key: String = WatchSingleExerciseSuggestionContextStore.defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public func loadData() -> Data? { defaults.data(forKey: key) }
    public func saveData(_ data: Data) { defaults.set(data, forKey: key) }
    public func deleteData() { defaults.removeObject(forKey: key) }
}

/// Durable JSON storage for the phone's suggestion context, so the Watch keeps it
/// after relaunch with the iPhone unreachable. A corrupt or unsupported stored
/// value is discarded; a failed write leaves the prior value.
public struct WatchSingleExerciseSuggestionContextStore {
    public enum Result: Equatable, Sendable {
        case replaced
        /// Equal/older/unsupported incoming; the stored context is still the newest valid data.
        case keptExisting
        /// The write could not be confirmed; the previous context is untouched.
        case failed
    }

    public static let defaultsKey = "watch.singleExerciseSuggestionContext.v1"

    private let store: WatchSingleExerciseSuggestionContextStoring

    public init(defaults: DefaultsStoring = UserDefaults.standard, key: String = defaultsKey) {
        self.store = UserDefaultsWatchSingleExerciseSuggestionContextStore(defaults: defaults, key: key)
    }

    public init(store: WatchSingleExerciseSuggestionContextStoring) {
        self.store = store
    }

    public func load() -> WatchSingleExerciseSuggestionContext? {
        guard let data = store.loadData() else { return nil }
        guard let value = WatchSingleExerciseSuggestionContext.decodePayload(data) else {
            store.deleteData()
            return nil
        }
        return value
    }

    public func replace(_ context: WatchSingleExerciseSuggestionContext) -> Result {
        guard context.version == WatchSingleExerciseSuggestionContext.currentVersion else { return .keptExisting }
        if let existing = load(), context.generatedAt <= existing.generatedAt { return .keptExisting }
        guard let data = context.propertyListValue,
              WatchSingleExerciseSuggestionContext.decodePayload(data) != nil else { return .failed }
        store.saveData(data)
        // Confirm the write is readable before the caller may acknowledge the envelope.
        return load()?.generatedAt == context.generatedAt ? .replaced : .failed
    }

    /// True when the incoming context replaced the stored one.
    @discardableResult
    public func replaceIfNewer(_ context: WatchSingleExerciseSuggestionContext) -> Bool {
        replace(context) == .replaced
    }
}
