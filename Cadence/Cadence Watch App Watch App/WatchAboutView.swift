import SwiftUI
import WatchConnectivity

enum WatchAppVersion {
    static let shortVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
        ?? String(localized: "Unknown")
    static let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
        ?? String(localized: "Unknown")
    static let bundleID = Bundle.main.bundleIdentifier ?? String(localized: "Unknown")
    static let display = "\(shortVersion) (\(build))"
}

struct WatchAboutView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager

    var body: some View {
        List {
            Section("Installed Watch App") {
                aboutRow("Version", value: WatchAppVersion.shortVersion)
                aboutRow(String(localized: "Build"), value: WatchAppVersion.build)
                aboutRow(String(localized: "Bundle ID"), value: WatchAppVersion.bundleID)
            }

            Section("Phone Connection") {
                aboutRow("WatchConnectivity", value: connectivityState)
                aboutRow(String(localized: "Phone reachability"), value: reachabilityState)
                aboutRow(String(localized: "Sync status"), value: watchManager.phoneSyncState.settingsText(
                    lastSyncAt: watchManager.lastPhoneSyncAt))
                aboutRow(String(localized: "Last successful sync"), value: syncDateText)

                if let error = watchManager.lastPhoneSyncError, !error.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Last sync error")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section {
                Text("The version and build above identify the Watch binary currently installed. Phone reachability must say Reachable before Sync now can send a live request.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("watch.about.screen")
    }

    private var connectivityState: String {
        guard let session = watchManager.wcSession else { return String(localized: "Unsupported") }
        switch session.activationState {
        case .activated: return String(localized: "Activated")
        case .inactive: return String(localized: "Inactive")
        case .notActivated: return String(localized: "Not activated")
        @unknown default: return String(localized: "Unknown")
        }
    }

    private var reachabilityState: String {
        guard let session = watchManager.wcSession,
              session.activationState == .activated else { return String(localized: "Unavailable") }
        return session.isReachable ? String(localized: "Reachable") : String(localized: "Not reachable")
    }

    private var syncDateText: String {
        guard let date = watchManager.lastPhoneSyncAt else { return String(localized: "Never") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func aboutRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}
