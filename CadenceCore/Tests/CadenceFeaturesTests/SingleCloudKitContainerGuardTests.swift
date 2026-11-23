import Foundation
import Testing

/// Structural guards for the single-store architecture. The app must never
/// select the retired pre-split store or its CloudKit container at runtime.
struct SingleCloudKitContainerGuardTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test func everyEntitlementFileListsOnlyTheSyncContainer() throws {
        for path in ["Cadence/Cadence/Cadence.entitlements",
                     "Cadence/Cadence/Cadence.Release.entitlements",
                     "Cadence/Cadence/Cadence.Debug.entitlements"] {
            let text = try source(path)
            #expect(text.contains("<string>iCloud.guru.parso.cladiron.sync</string>"),
                    "\(path) must include the current CloudKit container")
            #expect(!text.contains("<string>iCloud.guru.parso.ios-workout-app</string>"),
                    "\(path) must not include the retired CloudKit container")
        }
    }

    @Test func storeAndSchemaToolingUseOnlyTheSyncContainer() throws {
        let store = try source("CadenceCore/Sources/CadenceCore/Store.swift")
        #expect(store.contains("splitCloudKitContainerID = \"iCloud.guru.parso.cladiron.sync\""))
        #expect(!store.contains("cloudKitContainerID = \"iCloud.guru.parso.ios-workout-app\""))
        #expect(store.contains("applicationStoreFileName = \"Cladiron.store\""))
        #expect(store.contains("migrateToSingleStore"))
        #expect(store.contains("makeSingleModelContainer"))

        let script = try source("scripts/check-cloudkit-schema.sh")
        #expect(script.contains("CONTAINER_ID=\"iCloud.guru.parso.cladiron.sync\""))

        let docs = try source("CLAUDE.md")
        #expect(docs.contains("iCloud.guru.parso.cladiron.sync"))
        #expect(!docs.contains("`iCloud.guru.parso.ios-workout-app`"))
    }

    @Test func appHasNoInteractiveLegacyStoreFallback() throws {
        let model = try source("Cadence/Cadence/App/AppModel.swift")
        #expect(!model.contains("legacyStoreNeedsMigration"))
        #expect(!model.contains("migrateLegacyStore()"))
        #expect(!model.contains("StoreMigrationStatus"))
        #expect(model.contains("CadenceStore.splitCloudKitContainerID"))

        let backup = try source("Cadence/Cadence/Features/Settings/BackupRestoreCenterView.swift")
        #expect(!backup.contains("Upgrade private store"))
        #expect(!backup.contains("backupCenter.migrateStore"))

        let diagnostics = try source("Cadence/Cadence/Features/Settings/CloudKitSyncDiagnosticsView.swift")
        #expect(diagnostics.contains("CadenceStore.splitCloudKitContainerID"))
        #expect(!diagnostics.contains("activeCloudKitContainerID"))
        #expect(!diagnostics.contains("CloudKitRecoveryService"))

        let app = try source("Cadence/Cadence/CadenceApp.swift")
        #expect(app.contains("makeApplicationModelContainer()"))
    }
}
