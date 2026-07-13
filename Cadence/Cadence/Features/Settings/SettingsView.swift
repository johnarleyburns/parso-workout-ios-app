import SwiftUI
import CadenceCore
import CadenceFeatures

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settingsObject
    @Environment(ContributionCoordinator.self) private var contributions
    @Environment(StoreService.self) private var store
    @Environment(CloudBackupService.self) private var backup

    @State private var healthStatus: HealthAuthorizationStatus = .notDetermined
    @State private var primingPresented = false
    @State private var restoreResult: String?

    var body: some View {
        @Bindable var settings = settingsObject
        Form {
            Section("Units & Records") {
                Picker("Weight unit", selection: $settings.unit) {
                    ForEach(MeasurementUnitPreference.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.unit")
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
                    Toggle("Hide Coach offers", isOn: $settings.coachHidden)
                        .accessibilityIdentifier("settings.coach.hideOffers")
                        .onChange(of: settings.coachHidden) { _, hidden in
                            if !hidden { settings.coachIntroImpressions = 0 }
                        }

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
                Toggle("iCloud Backup", isOn: $settings.iCloudBackupEnabled)
                    .accessibilityIdentifier("settings.iCloudBackup")
                if settings.iCloudBackupEnabled {
                    HStack {
                        Label("Last backed up", systemImage: "clock.arrow.2.circlepath")
                        Spacer()
                        Text(lastBackupText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.backup.lastBackedUp")
                    }
                    Button {
                        Task { await backup.backUpIfNeeded(settings: settingsObject, force: true) }
                    } label: {
                        if case .backingUp = backup.status {
                            HStack { ProgressView(); Text("Backing up…") }
                        } else {
                            Label("Back Up Now", systemImage: "icloud.and.arrow.up")
                        }
                    }
                    .disabled(isBackupBusy)
                    .accessibilityIdentifier("settings.backup.now")
                    Button {
                        Task {
                            restoreResult = nil
                            do {
                                let added = try await backup.restore(settings: settingsObject)
                                restoreResult = "Restored \(added) workout\(added == 1 ? "" : "s")."
                            } catch {
                                restoreResult = error.localizedDescription
                            }
                        }
                    } label: {
                        if case .restoring = backup.status {
                            HStack { ProgressView(); Text("Restoring…") }
                        } else {
                            Label("Restore from iCloud", systemImage: "icloud.and.arrow.down")
                        }
                    }
                    .disabled(isBackupBusy)
                    .accessibilityIdentifier("settings.backup.restore")
                    if let restoreResult {
                        Text(restoreResult).font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("settings.backup.result")
                    }
                }
            } header: {
                Text("iCloud Backup")
            } footer: {
                Text("A compressed backup of your training log is kept in your own private iCloud — not on a Cladiron server, and never seen by us. If you lose or replace your phone, your history restores automatically on a fresh install.")
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
                Text("Cladiron is free and open-source. A one-time tip is an optional way to support development — never required.")
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $primingPresented) {
            HealthPrimingView { status in healthStatus = status }
        }
    }

    private var lastBackupText: String {
        guard let date = settingsObject.lastBackupAt else { return "Never" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var isBackupBusy: Bool {
        switch backup.status {
        case .backingUp, .restoring: return true
        default: return false
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
