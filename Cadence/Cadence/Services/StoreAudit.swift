import Foundation
import SwiftData
import CadenceCore

/// Recovery-build diagnostics. Lists every file that could hold workout history
/// on this iPhone and reports what each store actually contains.
///
/// Read-only for the listing: stores are copied to a temporary directory before
/// opening. The one write is `mergeLatestSnapshot(into:)`, which only merges the
/// app's own migration snapshot into the live store on explicit request.
enum StoreAudit {
    private struct Entry {
        let path: String
        let isDirectory: Bool
        let bytes: Int64
        let modified: Date?
    }

    static func report(liveSessionIDs: Set<UUID>, liveCardioIDs: Set<UUID>) -> String {
        let fileManager = FileManager.default
        let support = CadenceStore.applicationSupportDirectory()
        var lines: [String] = []
        lines.append("Application Support: \(support.path)")

        let entries = listing(in: support, fileManager: fileManager)
        lines.append("")
        lines.append("FILES (name · size · modified)")
        lines.append(contentsOf: entries.isEmpty
                     ? ["(empty)"]
                     : entries.map { entry in
            let size = entry.isDirectory ? "dir" : ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)
            let modified = entry.modified.map { format($0) } ?? "—"
            return "\(entry.path) · \(size) · \(modified)"
        })

        // The Watch delivery inbox can hold payloads the phone never processed.
        let inbox = support.appendingPathComponent("com.apple.watchconnectivity")
        if fileManager.fileExists(atPath: inbox.path) {
            lines.append("")
            lines.append("WATCH INBOX")
            let inboxEntries = listing(in: inbox, fileManager: fileManager, depth: 3)
            lines.append(contentsOf: inboxEntries.isEmpty
                         ? ["(empty)"]
                         : inboxEntries.map { "\($0.path) · \(ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file)) · \($0.modified.map { format($0) } ?? "—")" })
        }

        lines.append("")
        lines.append("STORE CONTENTS")
        let stores = storeCandidates(in: support, fileManager: fileManager)
        if stores.isEmpty { lines.append("No .store files found.") }
        for store in stores {
            lines.append(contentsOf: inspect(store, fileManager: fileManager))
        }

        lines.append("")
        lines.append("HEALTH OUTBOX")
        lines.append(contentsOf: outboxSummary(support: support,
                                               liveSessionIDs: liveSessionIDs,
                                               liveCardioIDs: liveCardioIDs))

        lines.append("")
        lines.append("MIGRATION SNAPSHOTS")
        for name in ["pre-single-store-native-db-v9.json", "pre-split-native-db-v8.json"] {
            let url = support.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url) else {
                lines.append("\(name) · missing")
                continue
            }
            guard let archive = try? JSONDecoder().decode(ExportNativeDatabase.self, from: data) else {
                lines.append("\(name) · unreadable archive")
                continue
            }
            let counts = Dictionary(grouping: archive.records, by: \.entity).mapValues(\.count)
            let summary = ["WorkoutSession", "CardioWorkout", "SetEntry", "Assessment"]
                .map { "\($0) \(counts[$0] ?? 0)" }
                .joined(separator: ", ")
            let latest = archive.records.compactMap(\.updatedAt).max().map { format($0) } ?? "—"
            lines.append("\(name) · \(summary) · newest record \(latest)")
        }
        return lines.joined(separator: "\n")
    }

    /// The Health backup queue is written when a workout is saved, so it can
    /// still describe workouts that are no longer in any store.
    private static func outboxSummary(support: URL, liveSessionIDs: Set<UUID>,
                                      liveCardioIDs: Set<UUID>) -> [String] {
        let url = support.appendingPathComponent("HealthOutbox.json")
        guard let data = try? Data(contentsOf: url),
              let queue = try? JSONDecoder().decode(HealthOutboxQueue.self, from: data) else {
            return ["HealthOutbox.json · missing or unreadable"]
        }
        var byKind: [String: Int] = [:]
        var missingStrength: [Date] = []
        var missingCardio: [Date] = []
        for item in queue.items {
            byKind["\(item.entityKind.rawValue)/\(item.operation.rawValue)", default: 0] += 1
            guard item.operation == .upsert, let job = try? item.decodeJob() else { continue }
            switch job {
            case .strength(let summary):
                if !liveSessionIDs.contains(summary.id) { missingStrength.append(summary.start) }
            case .cardio(let summary):
                if !liveCardioIDs.contains(summary.id) { missingCardio.append(summary.start) }
            default:
                break
            }
        }
        let kinds = byKind.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        var lines = ["HealthOutbox.json · \(queue.items.count) items \(kinds.isEmpty ? "" : "(\(kinds))")"]
        lines.append("  strength jobs not in the live store: \(missingStrength.count)\(missingStrength.isEmpty ? "" : " (\(format(missingStrength.min()!)) → \(format(missingStrength.max()!)))")")
        lines.append("  cardio jobs not in the live store: \(missingCardio.count)\(missingCardio.isEmpty ? "" : " (\(format(missingCardio.min()!)) → \(format(missingCardio.max()!)))")")
        return lines
    }


    /// Rebuilds workouts described by the Health backup queue that are no longer
    /// in any store. Each queued strength job carries the session metadata and
    /// its full set list, so the normal Health restore path can recreate it with
    /// sets. Existing ids are skipped by the planner, and queued deletes are
    /// ignored, so this is idempotent and cannot resurrect deleted workouts.
    static func restoreFromHealthOutbox(into container: ModelContainer) -> String {
        let support = CadenceStore.applicationSupportDirectory()
        let url = support.appendingPathComponent("HealthOutbox.json")
        guard let data = try? Data(contentsOf: url),
              let queue = try? JSONDecoder().decode(HealthOutboxQueue.self, from: data) else {
            return "HealthOutbox.json is missing or unreadable."
        }
        var incoming: [HealthBackupReadObject] = []
        for item in queue.items {
            guard item.operation == .upsert, let job = try? item.decodeJob() else { continue }
            switch job {
            case .strength(let summary):
                let payload = HealthWorkoutReadPayload(
                    healthObjectID: UUID(),
                    kind: .strength,
                    activityType: .traditionalStrength,
                    start: summary.start,
                    end: summary.end,
                    activeEnergyKcal: summary.activeEnergyKcal,
                    heartRate: summary.hrSamples,
                    metadata: summary.metadata,
                    source: .cladiron)
                if let object = try? HealthBackupDecoder.workout(payload) { incoming.append(object) }
            case .cardio(let summary):
                let payload = HealthWorkoutReadPayload(
                    healthObjectID: UUID(),
                    kind: .cardio,
                    activityType: importedKind(for: summary.type),
                    start: summary.start,
                    end: summary.end,
                    activeEnergyKcal: summary.activeEnergyKcal,
                    distanceMeters: summary.distanceMeters,
                    heartRate: summary.hrSamples,
                    metadata: summary.metadata,
                    source: .cladiron)
                if let object = try? HealthBackupDecoder.workout(payload) { incoming.append(object) }
            default:
                break
            }
        }
        guard !incoming.isEmpty else { return "The Health queue holds no recoverable workouts." }
        let context = ModelContext(container)
        let local: [HealthRestoreLocalState] =
            ((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []).map {
                HealthRestoreLocalState(kind: .strengthSession, id: $0.id,
                                        updatedAt: $0.updatedAt,
                                        healthObjectID: $0.healthKitWorkoutUUID,
                                        isDeleted: $0.deletedAt != nil)
            }
            + ((try? context.fetch(FetchDescriptor<CardioWorkout>())) ?? []).map {
                HealthRestoreLocalState(kind: .cardioWorkout, id: $0.id,
                                        updatedAt: $0.updatedAt,
                                        healthObjectID: $0.healthKitWorkoutUUID,
                                        isDeleted: $0.deletedAt != nil)
            }
        let plan = HealthBackupRestorePlanner.plan(incoming: incoming, local: local)
        do {
            let report = try WorkoutRepository.applyHealthRestore(plan, in: context)
            let restoredIDs = Set(plan.operations
                .filter { $0.action == .insert || $0.action == .replace }
                .map { $0.object.entityID })
            // A Health object without Cladiron metadata is restored as a
            // duration-only summary, which duplicates the real session once the
            // queue rebuilds it with sets. Hide those empty placeholders.
            var removedPlaceholders = 0
            if !restoredIDs.isEmpty {
                let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
                let restoredDates = sessions.filter { restoredIDs.contains($0.id) }.map(\.date)
                for session in sessions
                where session.deletedAt == nil && session.orderedSets.isEmpty
                    && session.healthKitWorkoutUUID != nil
                    && restoredDates.contains(where: { abs($0.timeIntervalSince(session.date)) < 180 }) {
                    session.deletedAt = Date()
                    removedPlaceholders += 1
                }
                try? context.save()
            }
            return "Health queue restore: inserted \(report.inserted), replaced \(report.replaced), skipped \(report.skipped), removed \(removedPlaceholders) empty placeholders."
        } catch {
            return "Health queue restore failed: \(error.localizedDescription)"
        }
    }

    /// Merges the app's newest migration snapshot into the live store. The merge
    /// is idempotent and identity-based, so records already present are skipped.
    static func mergeLatestSnapshot(into container: ModelContainer) -> String {
        let support = CadenceStore.applicationSupportDirectory()
        for name in ["pre-single-store-native-db-v9.json", "pre-split-native-db-v8.json"] {
            let url = support.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url),
                  let archive = try? JSONDecoder().decode(ExportNativeDatabase.self, from: data) else { continue }
            let context = ModelContext(container)
            do {
                let changed = try NativeDatabaseExport.merge(archive, in: context)
                try context.save()
                let after = (try? context.fetchCount(FetchDescriptor<WorkoutSession>())) ?? 0
                return "Merged \(name): \(changed) records changed. \(after) strength workouts are now in the live store."
            } catch {
                return "Merging \(name) failed: \(error.localizedDescription)"
            }
        }
        return "No migration snapshot found."
    }

    private static func listing(in directory: URL, fileManager: FileManager, depth: Int = 1) -> [Entry] {
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
        walk(directory, depth: depth)
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
            let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
            let cardio = (try? context.fetch(FetchDescriptor<CardioWorkout>())) ?? []
            let assessments = (try? context.fetchCount(FetchDescriptor<Assessment>())) ?? -1
            let liveSessions = sessions.filter { $0.deletedAt == nil }
            let liveCardio = cardio.filter { $0.deletedAt == nil }
            let withSets = liveSessions.filter { !$0.orderedSets.isEmpty }.count
            let withoutSets = liveSessions.count - withSets
            let oldest = (liveSessions.map(\.date) + liveCardio.map(\.start)).min()
            let newest = (liveSessions.map(\.date) + liveCardio.map(\.start)).max()
            return ["\(store.path)",
                    "  open: ok · strength \(sessions.count) (\(sessions.count - liveSessions.count) deleted; \(withSets) with sets, \(withoutSets) without) · cardio \(cardio.count) (\(cardio.count - liveCardio.count) deleted) · assessments \(assessments)",
                    "  range: \(oldest.map { format($0) } ?? "—") → \(newest.map { format($0) } ?? "—")",
                    "  by month (strength/cardio): \(monthly(sessions: liveSessions, cardio: liveCardio))"]
        } catch {
            return ["\(store.path)", "  open: FAILED · \(error.localizedDescription)"]
        }
    }

    private static func monthly(sessions: [WorkoutSession], cardio: [CardioWorkout]) -> String {
        let key = DateFormatter()
        key.dateFormat = "yyyy-MM"
        var strength: [String: Int] = [:]
        var counts: [String: Int] = [:]
        for session in sessions {
            let bucket = key.string(from: session.date)
            strength[bucket, default: 0] += 1
            counts[bucket, default: 0] += 1
        }
        for workout in cardio {
            counts[key.string(from: workout.start), default: 0] += 1
        }
        guard !counts.isEmpty else { return "none" }
        return counts.keys.sorted().suffix(10).map { bucket in
            "\(bucket) \(strength[bucket] ?? 0)/\(counts[bucket] ?? 0)"
        }.joined(separator: " · ")
    }

    private static func importedKind(for type: CardioType) -> ImportedWorkoutKind {
        switch type {
        case .run: return .running
        case .walk: return .walking
        case .cycle: return .cycling
        case .swim: return .swimming
        case .rowing: return .rowing
        case .hiit: return .hiit
        case .boxing: return .boxing
        case .elliptical, .stairClimber, .other: return .other
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
