import Foundation
import Testing

/// Structural guardrails for App Store submission. These are deliberately
/// source/plist checks: the shipping build must stay local-only (no health data
/// in iCloud), declare the required-reason APIs it actually uses, and keep its
/// permission copy accurate.
struct AppStoreSubmissionReadinessTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    @Test func phoneStoreIsLocalOnlyAndHasNoICloudEntitlement() throws {
        let app = try source("Cadence/Cadence/CadenceApp.swift")
        #expect(app.contains("makeApplicationModelContainer(cloudKitEnabled: false)"))

        for entitlement in ["Cadence/Cadence/Cadence.entitlements",
                            "Cadence/Cadence/Cadence.Release.entitlements",
                            "Cadence/Cadence/Cadence.Debug.entitlements"] {
            let text = try source(entitlement)
            #expect(!text.contains("com.apple.developer.icloud"), "\(entitlement) still grants iCloud")
            #expect(text.contains("com.apple.developer.healthkit"), "\(entitlement) lost HealthKit")
        }

        let settings = try source("Cadence/Cadence/Features/Settings/SettingsView.swift")
        #expect(!settings.contains("CloudKitSyncDiagnosticsView()"))
        #expect(!settings.contains("iCloud Sync"))
        let transparency = try source("Cadence/Cadence/Features/Settings/TransparencyCenterView.swift")
        #expect(!transparency.contains("CloudKitSyncDiagnosticsView()"))
        let backup = try source("Cadence/Cadence/Features/Settings/BackupRestoreCenterView.swift")
        #expect(!backup.contains("CloudKitSyncDiagnosticsView()"))
    }

    @Test func privacyManifestsDeclareEveryRequiredReasonAPI() throws {
        let phone = try source("Cadence/Cadence/PrivacyInfo.xcprivacy")
        #expect(phone.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(phone.contains("NSPrivacyAccessedAPICategoryFileTimestamp"))
        #expect(phone.contains("C617.1"))
        #expect(phone.contains("NSPrivacyAccessedAPICategoryDiskSpace"))
        #expect(phone.contains("E174.1"))

        let watch = try source("Cadence/Cadence Watch App Watch App/PrivacyInfo.xcprivacy")
        #expect(watch.contains("NSPrivacyAccessedAPICategoryUserDefaults"))
        #expect(watch.contains("NSPrivacyAccessedAPICategorySystemBootTime"))
        #expect(watch.contains("35F9.1"))
    }

    @Test func outdoorWorkoutLocationHasABackgroundPurposeString() throws {
        let plist = try source("Cadence/Cadence/Info.plist")
        #expect(plist.contains("NSLocationAlwaysAndWhenInUseUsageDescription"))
        #expect(!plist.contains("remote-notification"))

        let tracker = try source("Cadence/Cadence/Services/LocationTracker.swift")
        #expect(tracker.contains("requestAlwaysAuthorization()"))
        #expect(tracker.contains("allowsBackgroundLocationUpdates = true"))
    }

    @Test func storeCopyNoLongerAdvertisesICloudOrMotion() throws {
        let metadata = try source("docs/app-store/metadata.md")
        #expect(!metadata.contains("private iCloud"))
        #expect(!metadata.contains("iCloud backup"))
        #expect(!metadata.contains("Motion data"))
        let readme = try source("README.md")
        #expect(!readme.contains("syncs live across your iPhone and Apple Watch"))
    }
}
