import SwiftUI
import CadenceCore
import CadenceFeatures

/// Watch redesign §4 — Settings (⚙︎ on Today): everything that used to crowd the launcher.
/// HR source, units, spoken cues, Quick Talk (with the Heard log), phone sync status/retry, About.
struct WatchSettingsView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(AppSettings.self) private var watchAppSettings

    var body: some View {
        List {
            Section {
                NavigationLink { HRSettingsView() } label: { Label("Heart-rate source", systemImage: "heart.fill") }
                NavigationLink { WatchUnitsView(appSettings: watchAppSettings) } label: {
                    Label("Units", systemImage: "scalemass")
                }
                Toggle("Spoken workout cues", isOn: Binding(
                    get: { watchAppSettings.spokenCues },
                    set: { watchAppSettings.spokenCues = $0 }))
                    .accessibilityIdentifier("watch.settings.spokenCues")
            }

            Section("Quick Talk") {
                Text("Hold Log set and speak a set. Your iPhone turns it into text; the recording is deleted.")
                    .font(.caption2).foregroundStyle(.secondary)
                NavigationLink { WatchHeardLogView() } label: { Label("Heard", systemImage: "text.bubble") }
                    .accessibilityIdentifier("watch.settings.heard")
            }

            Section("Phone Sync") {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: "iphone.and.arrow.forward")
                        Text("Status").fontWeight(.bold)
                        Spacer()
                        if watchManager.phoneSyncState.isInProgress { ProgressView().controlSize(.mini) }
                    }
                    Text(watchManager.phoneSyncState.settingsText(lastSyncAt: watchManager.lastPhoneSyncAt))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Label("Last sync", systemImage: "clock.arrow.2.circlepath").fontWeight(.bold)
                    Text(WatchSync.Status.lastSyncText(watchManager.lastPhoneSyncAt))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button {
                    watchManager.requestSettingsSync()
                } label: {
                    Label(watchManager.phoneSyncState.isFailure ? "Retry sync" : "Sync now",
                          systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(watchManager.phoneSyncState.isInProgress)
                .accessibilityIdentifier("watch.phoneSync.retry")
            }

            Section {
                NavigationLink { WatchAboutView() } label: { Label("About", systemImage: "info.circle") }
                    .accessibilityIdentifier("watch.about")
            }
        }
        .navigationTitle("Settings")
    }
}

/// What Quick Talk heard (text and confidence only — never audio), newest first, with Clear.
struct WatchHeardLogView: View {
    @State private var log = WatchHeardLogStore.load()

    var body: some View {
        List {
            if log.entries.isEmpty {
                Text("Nothing heard yet.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(log.entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "“\(entry.transcript)”").font(.footnote)
                    Text(entry.appliedAutomatically ? "Saved automatically" : "Reviewed or not used")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(entry.heardAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if !log.entries.isEmpty {
                Button("Clear", role: .destructive) {
                    WatchHeardLogStore.clear()
                    log = WatchHeardLogStore.load()
                }
            }
        }
        .navigationTitle("Heard")
    }
}

/// §5 T4 — Cardio: the four most-started kinds as tiles (learned order), the rest under More.
struct WatchCardioPickerView: View {
    let types: [CardioType]
    let destination: (CardioType) -> AnyView
    private static let countsKey = "watch.cardio.startCounts"
    @State private var selected: CardioType?

    var body: some View {
        let order = WatchCardioTileOrder.ordered(types.map(\.rawValue), counts: Self.counts())
        let tiles = order.tiles.compactMap(CardioType.init(rawValue:))
        let more = order.more.compactMap(CardioType.init(rawValue:))
        List {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                // Buttons, not NavigationLinks: several links in one List row activate together.
                ForEach(tiles, id: \.self) { type in
                    Button { selected = type } label: {
                        VStack(spacing: 3) {
                            Image(systemName: type.symbol).font(.title3)
                            Text(type.displayName).font(.caption2.weight(.semibold)).lineLimit(1)
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(RoundedRectangle(cornerRadius: 14).fill(WatchTone.surface))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("watch.cardio.\(type.rawValue)")
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            if !more.isEmpty {
                Section("More") {
                    ForEach(more, id: \.self) { type in
                        NavigationLink { destination(type).onAppear { Self.record(type) } } label: {
                            Label(type.displayName, systemImage: type.symbol)
                        }
                        .accessibilityIdentifier("watch.cardio.\(type.rawValue)")
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Cardio")
        .navigationDestination(item: $selected) { type in destination(type).onAppear { Self.record(type) } }
    }

    private static func counts() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: countsKey) as? [String: Int] ?? [:]
    }

    private static func record(_ type: CardioType) {
        var counts = counts()
        counts[type.rawValue, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: countsKey)
    }
}
