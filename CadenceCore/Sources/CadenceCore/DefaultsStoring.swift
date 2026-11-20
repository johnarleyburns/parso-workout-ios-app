import Foundation

/// Generic `UserDefaults`-shaped storage seam.
///
/// Production types accept this instead of a concrete `UserDefaults` so tests
/// can pass `InMemoryDefaultsStore` and avoid the preferences daemon, plist
/// files, and their synchronous IPC. `UserDefaults` itself conforms, so no
/// production call site needs to change.
public protocol DefaultsStoring: AnyObject {
    func object(forKey defaultName: String) -> Any?
    func bool(forKey defaultName: String) -> Bool
    func data(forKey defaultName: String) -> Data?
    func integer(forKey defaultName: String) -> Int
    func string(forKey defaultName: String) -> String?
    func stringArray(forKey defaultName: String) -> [String]?
    func set(_ value: Any?, forKey defaultName: String)
    func removeObject(forKey defaultName: String)
}

/// A `DefaultsStoring` implementation that is safe to carry inside a
/// `Sendable` value. `UserDefaults` itself is not `Sendable`, so production
/// types that need both (for example the Watch inactivity store) keep the
/// suite name for the real backend and accept this seam only in tests.
public protocol SendableDefaultsStoring: DefaultsStoring, Sendable {}

extension UserDefaults: DefaultsStoring {}

/// Process-local replacement for `UserDefaults` in tests. Every accessor is a
/// plain dictionary read/write: no preferences daemon, no file IO, and no
/// blocking work while Swift Testing runs suites concurrently.
public final class InMemoryDefaultsStore: SendableDefaultsStoring, @unchecked Sendable {
    private var values: [String: Any] = [:]

    public init() {}

    public func object(forKey defaultName: String) -> Any? { values[defaultName] }
    public func bool(forKey defaultName: String) -> Bool {
        if let value = values[defaultName] as? Bool { return value }
        if let value = values[defaultName] as? Int { return value != 0 }
        return false
    }
    public func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    public func integer(forKey defaultName: String) -> Int {
        if let value = values[defaultName] as? Int { return value }
        if let value = values[defaultName] as? Bool { return value ? 1 : 0 }
        if let value = values[defaultName] as? String { return Int(value) ?? 0 }
        return 0
    }
    public func string(forKey defaultName: String) -> String? { values[defaultName] as? String }
    public func stringArray(forKey defaultName: String) -> [String]? { values[defaultName] as? [String] }
    public func set(_ value: Any?, forKey defaultName: String) {
        if let value { values[defaultName] = value } else { values.removeValue(forKey: defaultName) }
    }
    public func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
}
