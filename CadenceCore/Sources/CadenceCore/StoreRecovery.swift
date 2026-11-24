#if canImport(SwiftData)
import Foundation
import SwiftData

/// One-time recovery for users whose single store was quarantined or replaced
/// after a CloudKit-era build. The old store is never modified: candidates are
/// copied to a temporary directory, opened there, and merged into the live
/// store by stable IDs and `updatedAt` (the same idempotent archive merge used
/// by the legacy store migrator).
public enum StoreRecovery {
    public static let autoMarkerFileName = "store-recovery.complete.json"

    public struct Candidate: Sendable, Equatable, Identifiable {
        public enum Kind: String, Sendable { case single, split }
        public let id: String
        public let path: String
        public let kind: Kind
        public let modifiedAt: Date
        public let sessionCount: Int
        public let newestSession: Date?
        public var label: String {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return "\(name) · \(sessionCount) workouts"
        }
    }

    public struct Report: Sendable, Equatable {
        public let candidates: [Candidate]
        public let changedRecords: Int
        public let currentSessionsBefore: Int
        public let currentSessionsAfter: Int
        public let errors: [String]
        public var recoveredAny: Bool { currentSessionsAfter > currentSessionsBefore || changedRecords > 0 }
    }

    private enum Source {
        case single(URL)
        case split(local: URL, sync: URL)

        var primaryPath: String {
            switch self {
            case .single(let url): return url.path
            case .split(let local, _): return local.deletingLastPathComponent().path
            }
        }
        var identifier: String { primaryPath }
        var kindName: Candidate.Kind {
            switch self {
            case .single: return .single
            case .split: return .split
            }
        }
        var modifiedAt: Date {
            let path: String
            switch self {
            case .single(let url): path = url.path
            case .split(let local, _): path = local.path
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            return (attributes?[.modificationDate] as? Date) ?? .distantPast
        }
    }

    /// Runs once on launch, only when the live store has no workouts. Existing
    /// users with a populated store are untouched; they can use the explicit
    /// Recover Previous Data action instead.
    public static func autoRecoverIfNeeded(container: ModelContainer,
                                           directory: URL = CadenceStore.applicationSupportDirectory(),
                                           fileManager: FileManager = .default) -> Report? {
        guard container.configurations.contains(where: { !$0.isStoredInMemoryOnly }) else { return nil }
        let marker = directory.appendingPathComponent(autoMarkerFileName)
        guard !fileManager.fileExists(atPath: marker.path) else { return nil }
        let current = ModelContext(container)
        let before = (try? current.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        guard before == 0 else { return nil }
        let report = recover(into: container, directory: directory, fileManager: fileManager)
        if report.recoveredAny {
            try? Data("recovered\n".utf8).write(to: marker, options: .atomic)
            DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("cadence.workoutHistoryChanged"), object: nil) }
        }
        return report
    }

    /// Explicit recovery. Scans the live Application Support directory,
    /// every `Recovery-*` quarantine folder, and the legacy top-level stores.
    /// The user's current store and all source files are preserved.
    public static func recover(into container: ModelContainer,
                               directory: URL = CadenceStore.applicationSupportDirectory(),
                               fileManager: FileManager = .default) -> Report {
        let currentURL = CadenceStore.applicationStoreURL(in: directory)
        let sources = discoverSources(in: directory, excluding: currentURL, fileManager: fileManager)
        let destination = ModelContext(container)
        let before = (try? destination.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        var changed = 0
        var errors: [String] = []
        var candidates: [Candidate] = []
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("CladironRecovery-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempRoot) }

        for (index, source) in sources.enumerated() {
            let temp = tempRoot.appendingPathComponent("source-\(index)", isDirectory: true)
            do {
                let copied = try copy(source, into: temp, fileManager: fileManager)
                let sourceContainer = try open(copied)
                let context = ModelContext(sourceContainer)
                let sessions = try context.fetchCount(FetchDescriptor<WorkoutSession>())
                let cardio = try context.fetchCount(FetchDescriptor<CardioWorkout>())
                var descriptor = FetchDescriptor<WorkoutSession>(
                    sortBy: [SortDescriptor(\.date, order: .reverse)])
                descriptor.fetchLimit = 1
                let newest = try context.fetch(descriptor).first?.date
                let candidate = Candidate(id: source.identifier,
                                          path: source.primaryPath,
                                          kind: source.kindName,
                                          modifiedAt: source.modifiedAt,
                                          sessionCount: sessions + cardio,
                                          newestSession: newest)
                candidates.append(candidate)
                guard sessions + cardio > 0 else { continue }
                let archive = try NativeDatabaseExport.build(from: context)
                changed += try NativeDatabaseExport.merge(archive, in: destination)
            } catch {
                errors.append("\(source.primaryPath): \(error.localizedDescription)")
            }
        }

        if changed > 0 {
            do {
                try destination.save()
                DispatchQueue.main.async { NotificationCenter.default.post(name: Notification.Name("cadence.workoutHistoryChanged"), object: nil) }
            } catch {
                errors.append("Could not save recovered data: \(error.localizedDescription)")
            }
        }
        let after = (try? destination.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
        return Report(candidates: candidates,
                      changedRecords: changed,
                      currentSessionsBefore: before,
                      currentSessionsAfter: after,
                      errors: errors)
    }

    // MARK: - Source discovery

    private static func discoverSources(in directory: URL,
                                        excluding currentURL: URL,
                                        fileManager: FileManager) -> [Source] {
        var sources: [Source] = []
        func appendSingle(_ url: URL) {
            guard url.standardizedFileURL != currentURL.standardizedFileURL,
                  fileManager.fileExists(atPath: url.path) else { return }
            sources.append(.single(url))
        }
        func appendSplit(_ folder: URL) {
            let local = folder.appendingPathComponent(CadenceStore.localStoreFileName)
            let sync = folder.appendingPathComponent(CadenceStore.syncStoreFileName)
            let hasLocal = fileManager.fileExists(atPath: local.path)
            let hasSync = fileManager.fileExists(atPath: sync.path)
            if hasLocal, hasSync {
                sources.append(.split(local: local, sync: sync))
            } else if hasLocal {
                // A failed split migration can leave Local.store without its
                // Sync.store partner. The local store still holds history.
                appendSingle(local)
            }
        }

        // Top-level legacy stores left by the split/pre-split era.
        appendSingle(directory.appendingPathComponent(CadenceStore.legacyStoreFileName))
        appendSplit(directory)
        appendSingle(directory.appendingPathComponent(CadenceStore.applicationStoreFileName))

        // Every quarantine folder created by the phone bootstrap policy.
        let children = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        for child in children where child.lastPathComponent.hasPrefix("Recovery-") {
            appendSingle(child.appendingPathComponent(CadenceStore.applicationStoreFileName))
            appendSingle(child.appendingPathComponent(CadenceStore.legacyStoreFileName))
            appendSplit(child)
        }
        return sources
    }

    // MARK: - Opening copies

    private static func copy(_ source: Source, into directory: URL,
                             fileManager: FileManager) throws -> Source {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        func copyFamily(_ url: URL) throws -> URL {
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: url.path + suffix)
                guard fileManager.fileExists(atPath: from.path) else { continue }
                try fileManager.copyItem(at: from,
                                         to: URL(fileURLWithPath: destination.path + suffix))
            }
            return destination
        }
        switch source {
        case .single(let url):
            return .single(try copyFamily(url))
        case .split(let local, let sync):
            return .split(local: try copyFamily(local), sync: try copyFamily(sync))
        }
    }

    private static func open(_ source: Source) throws -> ModelContainer {
        switch source {
        case .single(let url):
            return try CadenceStore.makeSingleModelContainer(storeURL: url)
        case .split(let local, let sync):
            return try CadenceStore.makeSplitModelContainer(localURL: local, syncURL: sync)
        }
    }
}
