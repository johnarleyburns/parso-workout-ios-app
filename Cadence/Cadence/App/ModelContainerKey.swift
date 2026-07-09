import SwiftUI
import SwiftData

/// Custom environment key so ExportView can create a background ModelContext
/// for off-main-thread export without freezing the UI.
struct ModelContainerKey: EnvironmentKey {
    static let defaultValue: ModelContainer? = nil
}

extension EnvironmentValues {
    var cadenceModelContainer: ModelContainer? {
        get { self[ModelContainerKey.self] }
        set { self[ModelContainerKey.self] = newValue }
    }
}
