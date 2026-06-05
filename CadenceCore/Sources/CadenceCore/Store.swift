import Foundation
import SwiftData

/// Builds the shared SwiftData store. Both the iOS and watchOS apps use this,
/// so logging on the watch mirrors to the phone through the user's private
/// CloudKit database automatically (FR-9).
public enum CadenceStore {

    /// Must match the iCloud container enabled on BOTH targets in Xcode.
    public static let cloudKitContainerID = "iCloud.guru.parso.ios-workout-app"

    public static let schema = Schema([
        WorkoutSession.self,
        Exercise.self,
        SetEntry.self
    ])

    /// - Parameter inMemory: pass `true` for previews/tests (no CloudKit).
    public static func makeModelContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        } else {
            // If the compiler ever rejects `.private(_:)` on your toolchain,
            // fall back to `.automatic` — it picks up the container from the
            // app's iCloud entitlement instead.
            configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
        }

        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
