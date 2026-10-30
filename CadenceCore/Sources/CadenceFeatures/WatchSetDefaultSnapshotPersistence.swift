import Foundation

/// Durable, validated storage for the phone's set-default snapshot. The Watch's
/// `WatchSetDefaultSnapshotStore` wraps this; it lives here so it is headlessly testable.
public struct WatchSetDefaultSnapshotPersistence {
    public enum Result: Equatable, Sendable {
        case replaced
        /// Equal/older snapshot; the stored one is still the newest valid data.
        case keptExisting
        /// The write could not be confirmed; the previous snapshot is untouched.
        case failed
    }

    public static let defaultsKey = "watch.setDefaultSnapshot.v1"

    private struct Record: Codable {
        var version: Int
        var generatedAt: Date
        var snapshot: Data
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = defaultsKey) {
        self.defaults = defaults
        self.key = key
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    /// Corrupt or unsupported stored data is discarded and treated as absent.
    public func load() -> WatchSetDefaultSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let record = try? Self.decoder().decode(Record.self, from: data),
              record.version == WatchSetDefaultSnapshot.currentVersion,
              let raw = try? Self.decoder().decode(WatchSetDefaultSnapshot.self, from: record.snapshot),
              raw.version == record.version, raw.generatedAt == record.generatedAt else {
            defaults.removeObject(forKey: key)
            return nil
        }
        return WatchSetDefaultSnapshot(version: raw.version, generatedAt: raw.generatedAt,
                                       performers: raw.performers)
    }

    public func replaceIfNewer(_ snapshot: WatchSetDefaultSnapshot) -> Result {
        guard snapshot.version == WatchSetDefaultSnapshot.currentVersion else { return .keptExisting }
        if let existing = load(), snapshot.generatedAt <= existing.generatedAt { return .keptExisting }
        guard let body = try? Self.encoder().encode(snapshot),
              let data = try? Self.encoder().encode(
                Record(version: snapshot.version, generatedAt: snapshot.generatedAt, snapshot: body))
        else { return .failed }
        defaults.set(data, forKey: key)
        // Confirm the write is readable before the caller may acknowledge the envelope.
        return load()?.generatedAt == snapshot.generatedAt ? .replaced : .failed
    }
}
