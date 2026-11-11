import Foundation
import OSLog

/// File-system seam so the store is testable without a real container.
public protocol WatchOutboxFileSystem {
    func read(_ name: String) -> Data?
    /// Atomically replaces `name`; a failure must leave the previous file intact.
    func writeAtomically(_ data: Data, to name: String) throws
    func move(_ name: String, to newName: String) throws
}

/// Read-only access to the retired UserDefaults journals.
public protocol WatchOutboxLegacyReader {
    func data(forKey key: String) -> Data?
}

/// Real file system rooted at one directory (Application Support on the Watch).
public struct WatchOutboxDirectoryFileSystem: WatchOutboxFileSystem {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    /// Application Support, created idempotently.
    public static func applicationSupport() -> WatchOutboxDirectoryFileSystem? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        return WatchOutboxDirectoryFileSystem(directory: base)
    }

    public func read(_ name: String) -> Data? {
        try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    public func writeAtomically(_ data: Data, to name: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        let temporary = directory.appendingPathComponent(name + ".tmp")
        #if canImport(Darwin)
        try data.write(to: temporary, options: [.completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: temporary)
        #endif
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fm.moveItem(at: temporary, to: destination)
        }
    }

    public func move(_ name: String, to newName: String) throws {
        let fm = FileManager.default
        let target = directory.appendingPathComponent(newName)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: directory.appendingPathComponent(name), to: target)
    }
}

public enum WatchOutboxStoreIssue: Equatable, Sendable {
    /// File bytes could not be decoded; preserved under the quarantine name.
    case unreadableFileQuarantined
    case quarantineFailed
    /// Legacy journal decoded but could not be committed to its file yet.
    case legacyMigrationWriteFailed
    case clearFailed
}

private struct WatchOutboxFileEnvelope: Codable, Equatable {
    let version: Int
    let state: WatchHeartRateOutboxState?
}

/// Crash-safe, file-backed outbox journal. A committed envelope (even an empty
/// tombstone) is the migration-complete marker; legacy defaults are never written.
public final class FileWatchHeartRateOutboxStore: WatchHeartRateOutboxStore {
    public static let currentVersion = 1
    public static let heartRateFileName = "watch.hr-outbox.v1.json"
    public static let strengthCompletionFileName = "watch.strength-completion-outbox.v1.json"
    public static let heartRateLegacyKey = "watch.hrOutbox.v1"
    public static let strengthCompletionLegacyKey = "watch.strengthCompletionOutbox.v1"

    private static let log = Logger(subsystem: "guru.parso.cadence", category: "WatchOutboxFile")

    private let fileSystem: WatchOutboxFileSystem
    private let legacy: WatchOutboxLegacyReader
    private let fileName: String
    private let legacyKey: String
    /// Most recent recoverable problem, for diagnostics.
    public private(set) var lastIssue: WatchOutboxStoreIssue?

    public var quarantineFileName: String { fileName + ".unreadable" }

    public init(fileSystem: WatchOutboxFileSystem, legacy: WatchOutboxLegacyReader,
                fileName: String, legacyKey: String) {
        self.fileSystem = fileSystem; self.legacy = legacy
        self.fileName = fileName; self.legacyKey = legacyKey
    }

    public func load() -> WatchHeartRateOutboxState? {
        if let bytes = fileSystem.read(fileName) {
            if let envelope = try? JSONDecoder().decode(WatchOutboxFileEnvelope.self, from: bytes) {
                return envelope.state
            }
            do {
                try fileSystem.move(fileName, to: quarantineFileName)
                lastIssue = .unreadableFileQuarantined
            } catch {
                lastIssue = .quarantineFailed
            }
            Self.log.error("outbox file unreadable; bytes preserved")
            return nil
        }
        guard let legacyBytes = legacy.data(forKey: legacyKey),
              let state = try? JSONDecoder().decode(WatchHeartRateOutboxState.self, from: legacyBytes) else { return nil }
        do {
            try commit(state)
            Self.log.info("legacy outbox migrated to file")
        } catch {
            lastIssue = .legacyMigrationWriteFailed
            Self.log.error("legacy outbox migration write failed; will retry")
        }
        return state
    }

    public func save(_ state: WatchHeartRateOutboxState) throws {
        try commit(state)
    }

    public func clear() {
        do { try commit(nil) } catch {
            lastIssue = .clearFailed
            Self.log.error("outbox clear tombstone failed")
        }
    }

    private func commit(_ state: WatchHeartRateOutboxState?) throws {
        let data = try JSONEncoder().encode(WatchOutboxFileEnvelope(version: Self.currentVersion, state: state))
        try fileSystem.writeAtomically(data, to: fileName)
    }
}
