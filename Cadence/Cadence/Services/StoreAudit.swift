import Foundation
import SwiftData
import CadenceCore

/// Recovery-build diagnostics. Lists every file that could hold workout history
/// on this iPhone and reports the row counts each store actually contains.
///
/// Read-only: stores are copied to a temporary directory before opening, so no
/// source file is ever opened in place or modified.
enum StoreAudit {
    private struct Entry {
        let path: String
        let isDirectory: Bool
        let bytes: Int64
        let modified: Date?
    }

    static func report() -> String {
        let fileManager = FileManager.default
        let support = CadenceStore.applicationSupportDirectory()
        var lines: [String] = []
        lines.append("Application Support: \(support.path)")

        let entries = listing(in: support, fileManager: fileManager)
        if entries.isEmpty {
            lines.append("(empty)")
        } else {
            lines.append("")
            lines.append("FILES (name · size · modified)")
            for entry in entries {
                let size = entry.isDirectory ? "dir" : ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)
                let modified = entry.modified.map { format($0) } ?? "—"
                lines.append("\(entry.path) · \(size) · \(modified)")
            }
        }

        lines.append("")
        lines.append("STORE CONTENTS")
        let stores = storeCandidates(in: support, fileManager: fileManager)
        if stores.isEmpty {
            lines.append("No .store files found.")
        }
        for store in stores {
            lines.append(contentsOf: inspect(store, fileManager: fileManager))
        }
        return lines.joined(separator: "\n")
    }

    private static func listing(in directory: URL, fileManager: FileManager) -> [Entry] {
        var results: [Entry] = []
        func walk(_ url: URL, depth: Int) {
            guard depth >= 0 else { return }
            let children = (try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: [])) ?? []
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                let isDirectory = values?.isDirectory ?? false
                results.append(Entry(path: child.path,
                                     isDirectory: isDirectory,
                                     bytes: Int64(values?.fileSize ?? 0),
                                     modified: values?.contentModificationDate))
                if isDirectory { walk(child, depth: depth - 1) }
            }
        }
        walk(directory, depth: 1)
        return results
    }

    private static func storeCandidates(in support: URL, fileManager: FileManager) -> [URL] {
        var stores: [URL] = []
        let names: Set<String> = [CadenceStore.applicationStoreFileName,
                                  CadenceStore.legacyStoreFileName,
                                  CadenceStore.localStoreFileName,
                                  CadenceStore.syncStoreFileName]
        func walk(_ url: URL, depth: Int) {
            guard depth >= 0 else { return }
            let children = (try? fileManager.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
            for child in children {
                let isDirectory = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                if isDirectory {
                    walk(child, depth: depth - 1)
                } else if names.contains(child.lastPathComponent) {
                    stores.append(child)
                }
            }
        }
        walk(support, depth: 2)
        return stores.sorted { $0.path < $1.path }
    }

    private static func inspect(_ store: URL, fileManager: FileManager) -> [String] {
        let temp = fileManager.temporaryDirectory
            .appendingPathComponent("CladironAudit-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temp) }

        func copyFamily(_ url: URL) -> URL {
            let destination = temp.appendingPathComponent(url.lastPathComponent)
            for suffix in ["", "-wal", "-shm"] {
                let from = URL(fileURLWithPath: url.path + suffix)
                guard fileManager.fileExists(atPath: from.path) else { continue }
                try? fileManager.copyItem(at: from, to: URL(fileURLWithPath: destination.path + suffix))
            }
            return destination
        }

        let siblingLocal = store.deletingLastPathComponent()
            .appendingPathComponent(CadenceStore.localStoreFileName)
        let name = store.lastPathComponent
        do {
            let container: ModelContainer
            if (name == CadenceStore.syncStoreFileName || name == CadenceStore.localStoreFileName),
               fileManager.fileExists(atPath: siblingLocal.path) {
                let splitSync = store.deletingLastPathComponent()
                    .appendingPathComponent(CadenceStore.syncStoreFileName)
                guard fileManager.fileExists(atPath: splitSync.path) else {
                    throw AuditError.missingSplitPartner
                }
                container = try CadenceStore.makeSplitModelContainer(localURL: copyFamily(siblingLocal),
                                                                     syncURL: copyFamily(splitSync))
            } else {
                container = try CadenceStore.makeSingleModelContainer(storeURL: copyFamily(store))
            }
            let context = ModelContext(container)
            let sessions = (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) ?? -1
            let deleted = (try? context.fetchCount(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate<WorkoutSession> { $0.deletedAt != nil }))) ?? -1
            let cardio = (try? context.fetchCount(FetchDescriptor<CardioWorkout>())) ?? -1
            let assessments = (try? context.fetchCount(FetchDescriptor<Assessment>())) ?? -1
            var newest = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])
            newest.fetchLimit = 1
            let newestDate = (try? context.fetch(newest))?.first?.date
            var newestCardio = FetchDescriptor<CardioWorkout>(sortBy: [SortDescriptor(\.start, order: .reverse)])
            newestCardio.fetchLimit = 1
            let newestCardioDate = (try? context.fetch(newestCardio))?.first?.start
            let latest = [newestDate, newestCardioDate].compactMap { $0 }.max()
            return ["\(store.path)",
                    "  open: ok · strength \(sessions) (soft-deleted \(deleted)) · cardio \(cardio) · assessments \(assessments) · newest \(latest.map { format($0) } ?? "—")"]
        } catch {
            return ["\(store.path)", "  open: FAILED · \(error.localizedDescription)"]
        }
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private enum AuditError: Error, LocalizedError {
        case missingSplitPartner

        var errorDescription: String? { "Local.store exists without Sync.store" }
    }
}
