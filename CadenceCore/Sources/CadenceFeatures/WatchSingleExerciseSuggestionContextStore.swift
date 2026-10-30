import Foundation

/// Durable UserDefaults-JSON storage for the phone's suggestion context, so the
/// Watch keeps it after relaunch with the iPhone unreachable. A corrupt or
/// unsupported stored value is discarded; a failed write leaves the prior value.
public struct WatchSingleExerciseSuggestionContextStore {
    public enum Result: Equatable, Sendable {
        case replaced
        /// Equal/older/unsupported incoming; the stored context is still the newest valid data.
        case keptExisting
        /// The write could not be confirmed; the previous context is untouched.
        case failed
    }

    public static let defaultsKey = "watch.singleExerciseSuggestionContext.v1"

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> WatchSingleExerciseSuggestionContext? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let value = WatchSingleExerciseSuggestionContext.decodePayload(data) else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return value
    }

    public func replace(_ context: WatchSingleExerciseSuggestionContext) -> Result {
        guard context.version == WatchSingleExerciseSuggestionContext.currentVersion else { return .keptExisting }
        if let existing = load(), context.generatedAt <= existing.generatedAt { return .keptExisting }
        guard let data = context.propertyListValue,
              WatchSingleExerciseSuggestionContext.decodePayload(data) != nil else { return .failed }
        defaults.set(data, forKey: key)
        // Confirm the write is readable before the caller may acknowledge the envelope.
        return load()?.generatedAt == context.generatedAt ? .replaced : .failed
    }

    /// True when the incoming context replaced the stored one.
    @discardableResult
    public func replaceIfNewer(_ context: WatchSingleExerciseSuggestionContext) -> Bool {
        replace(context) == .replaced
    }
}
