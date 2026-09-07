import SwiftUI
import CadenceCore
import CadenceFeatures

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settingsObject
    @Environment(ContributionCoordinator.self) private var contributions
    @Environment(StoreService.self) private var store
    @Environment(\.cadenceModelContainer) private var container

    @State private var healthStatus: HealthAuthorizationStatus = .notDetermined
    @State private var primingPresented = false
    @State private var storageUsage = StorageUsageSnapshot()

    var body: some View {
        @Bindable var settings = settingsObject
        Form {
            Section("Units & Records") {
                Picker("Weight unit", selection: $settings.unit) {
                    ForEach(MeasurementUnitPreference.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.unit")
                Picker("Distance unit", selection: $settings.distanceUnit) {
                    ForEach(DistanceUnitPreference.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.distanceUnit")
                Picker("PR rule", selection: $settings.prRule) {
                    ForEach(PRRule.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.prRule")
                Picker("1RM formula", selection: $settings.formula) {
                    ForEach(OneRepMaxFormula.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.formula")
            }

            Section {
                Button {
                    primingPresented = true
                } label: {
                    HStack {
                        Label("Apple Health", systemImage: "heart.text.square")
                        Spacer()
                        Text(statusText).foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.health.status")
                    }
                }
                .accessibilityIdentifier("settings.health.connect")

                Toggle("Auto-save to Apple Health", isOn: $settings.autoSaveHealth)
                    .accessibilityIdentifier("settings.autoSaveHealth")

                if let lastSync = model.lastHealthSync {
                    HStack {
                        Label("Last sync", systemImage: "clock.arrow.2.circlepath")
                        Spacer()
                        Text(lastSync.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                NavigationLink {
                    HRMSettingsView()
                } label: {
                    Label("Heart-Rate Monitor", systemImage: "antenna.radiowaves.left.and.right")
                }
                .accessibilityIdentifier("settings.hrm")
            } header: {
                Text("Health & Sensors")
            } footer: {
                Text("Your health data stays on your device. Detailed sets stay local; only workout summaries are written to Apple Health.")
            }

            Section {
                HStack {
                    Label("Status", systemImage: "applewatch")
                    Spacer()
                    if model.watchSyncState.isInProgress {
                        ProgressView()
                    }
                    Text(model.watchSyncState.settingsText(lastSyncAt: model.lastWatchSyncAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("settings.watchSync.status")
                }

                HStack {
                    Label("Last synced", systemImage: "clock.arrow.2.circlepath")
                    Spacer()
                    Text(WatchSync.Status.lastSyncText(model.lastWatchSyncAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.watchSync.lastSynced")
                }

                if let error = model.lastWatchSyncError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("settings.watchSync.error")
                }

                Button {
                    model.pushSettingsContext(force: true)
                } label: {
                    if model.watchSyncState.isInProgress {
                        HStack { ProgressView(); Text("Syncing to Watch...") }
                    } else {
                        Label("Sync to Watch Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(model.watchSyncState.isInProgress)
                .accessibilityIdentifier("settings.watchSync.force")
            } header: {
                Text("Apple Watch")
            } footer: {
                Text("Sends units, interval defaults, workout sounds, and recent partners to the Watch app.")
            }

            Section {
                NavigationLink {
                    CoachResearchUpdatesView()
                } label: {
                    HStack {
                        Label("Coach Research Updates", systemImage: "book.closed")
                        Spacer()
                        if CoachKBBadge.hasUnseenUpdate(lastSeen: settings.lastSeenCoachKBVersion) {
                            Text("New")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.green, in: Capsule())
                                .foregroundStyle(.white)
                                .accessibilityIdentifier("settings.coachUpdates.badge")
                        }
                    }
                }
                .accessibilityIdentifier("settings.coachUpdates")

                if store.isPro {
                    HStack {
                        Label("Cladiron Pro", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Text(proStatusText).font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("settings.proStatus")
                } else {
                    Button {
                        Task { await store.restore() }
                    } label: {
                        Label("Restore Purchases", systemImage: "arrow.clockwise")
                    }
                    .accessibilityIdentifier("settings.restore")
                }

                NavigationLink {
                    CoachMethodologyView()
                } label: {
                    Label("Coach Methodology", systemImage: "text.book.closed")
                }
                .accessibilityIdentifier("settings.coach.methodology")

                NavigationLink {
                    CoachSchedulePreferencesView()
                } label: {
                    Label("Coach & Plan", systemImage: "gearshape")
                }
                .accessibilityIdentifier("settings.coach.plan")
            } header: {
                Text("Coach")
            } footer: {
                Text("The coaching engine updates quarterly with new research. Everything else in Cladiron is free forever.")
            }

            Section("Exercises") {
                NavigationLink {
                    CustomExerciseListView()
                } label: {
                    Label("Custom Exercises", systemImage: "figure.strengthtraining.traditional")
                }
                .accessibilityIdentifier("settings.customExercises")
            }

            Section("Data") {
                NavigationLink {
                    ImportView()
                } label: { Label("Import Workout Log", systemImage: "square.and.arrow.down") }
                    .accessibilityIdentifier("settings.import")
                NavigationLink {
                    ExportView()
                } label: { Label("Backup & Restore", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("settings.export")
            }

            Section {
                Toggle("Workout sounds", isOn: $settings.workoutSounds)
                    .accessibilityIdentifier("settings.workoutSounds")
            } header: {
                Text("Sounds")
            } footer: {
                Text("Plays a bell at each transition — workout start, warm-up, work, cool-down and end — so you can start and stop without watching your phone. Boxing keeps its own round bell.")
            }

            Section {
                HStack {
                    Label("iCloud Sync", systemImage: "arrow.triangle.2.circlepath.icloud")
                    Spacer()
                    Text(model.cloudKitAccountAvailability.displayName)
                        .font(.caption)
                        .foregroundStyle(model.cloudKitAccountAvailability.canSync ? Color.secondary : Color.orange)
                        .accessibilityIdentifier("settings.sync.status")
                }

                HStack {
                    Label("Cloud database", systemImage: "lock.icloud")
                    Spacer()
                    Text("Private iCloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.sync.database")
                }

                HStack {
                    Label("Workout records on iPhone", systemImage: "list.number")
                    Spacer()
                    Text("\(storageUsage.workoutRecordCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.storage.recordCount")
                }

                HStack {
                    Label("Cladiron data on iPhone", systemImage: "internaldrive")
                    Spacer()
                    Text(storageUsage.appDataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.storage.appData")
                }

                HStack {
                    Label("Workout database", systemImage: "externaldrive")
                    Spacer()
                    Text(storageUsage.workoutStoreText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.storage.workoutStore")
                }

                HStack {
                    Label("Free iPhone storage", systemImage: "iphone")
                    Spacer()
                    Text(storageUsage.deviceFreeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.storage.deviceFree")
                }

                HStack {
                    Label("iCloud storage used", systemImage: "externaldrive.icloud")
                    Spacer()
                    Text("Not exposed by Apple")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.storage.cloudUsage")
                }

                NavigationLink {
                    CloudKitSyncDiagnosticsView()
                } label: {
                    Label("Sync Diagnostics & Recovery", systemImage: "stethoscope")
                }
                .accessibilityIdentifier("settings.sync.diagnostics")
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text("Your full training log syncs automatically across your iPhone and Apple Watch through your own private iCloud — not a Cladiron server, and never seen by us. Sign in to iCloud in Settings to sync; on a new device your history appears once sync completes. Apple does not provide apps with the exact byte usage of a private CloudKit database, so the iCloud usage row cannot show a precise number.")
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .accessibilityIdentifier("settings.about")
            }

            Section {
                NavigationLink {
                    ContributionSupportView(store: contributions.store)
                } label: {
                    Label(contributions.store.isSupporter ? "Supporter — Thank You" : "Support Cladiron",
                          systemImage: contributions.store.isSupporter ? "heart.fill" : "heart")
                        .foregroundStyle(contributions.store.isSupporter ? Color.pink : Color.accentColor)
                }
                .accessibilityIdentifier("settings.support")
            } footer: {
                Text("Cladiron is open source and ad-free. A one-time tip is an optional way to support development — never required.")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $primingPresented) {
            HealthPrimingView { status in healthStatus = status }
        }
        .task {
            // Directory enumeration and the record-count fetch can be expensive
            // on a device with a long workout history. Keep both off the main
            // actor so entering Settings remains responsive.
            let measurementContainer = container
            let measured = await Task.detached(priority: .utility) {
                StorageUsageSnapshot.measure(container: measurementContainer)
            }.value
            guard !Task.isCancelled else { return }
            storageUsage = measured
        }
    }

    private var proStatusText: String {
        switch store.entitlement.source {
        case .lifetime: return "Lifetime"
        case .subscription: return "Subscribed"
        case .trial: return store.trialDaysRemaining.map { "Trial — \($0)d left" } ?? "Trial"
        case .none: return ""
        }
    }

    private var statusText: String {
        switch healthStatus {
        case .authorized: return "Connected"
        case .denied: return "Denied"
        case .unavailable: return "Unavailable"
        case .notDetermined: return "Not connected"
        }
    }
}
