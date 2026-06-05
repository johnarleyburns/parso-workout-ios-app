import SwiftUI
import CadenceCore

// Placeholder — built out under FR-4 / FR-6.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        NavigationStack {
            Form {
                Text("Settings")
            }
            .navigationTitle("Settings")
        }
    }
}
