import Foundation
import SwiftData
import CadenceCore

/// Read-only storage facts shown in Settings. CloudKit deliberately does not
/// expose per-app private-database byte usage to apps, so the UI distinguishes
/// the exact local footprint from the cloud account/sync state.
struct StorageUsageSnapshot: Equatable {
    var appDataBytes: Int64 = 0
    var workoutStoreBytes: Int64 = 0
    var deviceFreeBytes: Int64?
    var workoutRecordCount: Int = 0

    var appDataText: String { Self.fileSizeText(appDataBytes) }
    var workoutStoreText: String { Self.fileSizeText(workoutStoreBytes) }
    var deviceFreeText: String {
        guard let deviceFreeBytes else { return "Unavailable" }
        return Self.fileSizeText(deviceFreeBytes)
    }

    static func measure(container: ModelContainer?) -> StorageUsageSnapshot {
        let fileManager = FileManager.default
        let roots = [
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        let appDataBytes = roots.reduce(Int64(0)) { $0 + directorySize(at: $1) }

        let storeURL = container?.configurations.first(where: { !$0.isStoredInMemoryOnly })?.url
        let workoutStoreBytes = storeURL.map(storeFamilySize(at:)) ?? 0
        let workoutRecordCount: Int
        if let container {
            let context = ModelContext(container)
            let strength = (try? context.fetch(FetchDescriptor<WorkoutSession>()).count) ?? 0
            let cardio = (try? context.fetch(FetchDescriptor<CardioWorkout>()).count) ?? 0
            workoutRecordCount = strength + cardio
        } else {
            workoutRecordCount = 0
        }

        let deviceURL = roots.first ?? URL(fileURLWithPath: NSHomeDirectory())
        let deviceFreeBytes = try? deviceURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage

        return StorageUsageSnapshot(appDataBytes: appDataBytes,
                                    workoutStoreBytes: workoutStoreBytes,
                                    deviceFreeBytes: deviceFreeBytes,
                                    workoutRecordCount: workoutRecordCount)
    }

    private static func storeFamilySize(at url: URL) -> Int64 {
        let paths = [url.path, url.path + "-shm", url.path + "-wal"]
        return paths.reduce(Int64(0)) { total, path in
            total + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0)
        }
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private static func fileSizeText(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytes)
    }
}
