import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchRootView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(AppSettings.self) private var watchAppSettings

    @State private var cardioLocation: WorkoutConfigurationSpec.Location = .outdoor
    @State private var cardioLapLength: Double = 25
    @State private var activeCardioKind: WorkoutConfigurationSpec.CardioKind?
    @State private var activeIntervalSession: ActiveIntervalSession?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let intervalSession: ActiveIntervalSession?
        if arguments.contains("-uiTestBoxingInterval") {
            let model = IntervalSetupModel(kind: "Boxing")
            intervalSession = ActiveIntervalSession(plan: model.intervalPlan(), kind: "Boxing")
        } else {
            intervalSession = nil
        }
        _activeIntervalSession = State(initialValue: intervalSession)
    }

    var body: some View {
        Group {
            if let activeIntervalSession {
                WatchIntervalView(plan: activeIntervalSession.plan, kind: activeIntervalSession.kind) {
                    self.activeIntervalSession = nil
                }
            } else if let activeCardioKind {
                WatchCardioSessionView(kind: activeCardioKind) {
                    self.activeCardioKind = nil
                }
            } else {
                launcher
            }
        }
    }

    private var launcher: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { WatchStrengthView() }
                        label: {
                            HStack {
                                Image(systemName: "dumbbell.fill").foregroundStyle(.blue)
                                VStack(alignment: .leading) {
                                    Text("Strength").fontWeight(.semibold)
                                    Text("Weight training").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }

                    ForEach(cardioTypes, id: \.self) { ct in
                        NavigationLink {
                            cardioSetupView(for: ct)
                        } label: {
                            Label(ct.displayName, systemImage: ct.symbol)
                        }
                    }

                    NavigationLink { LiveHRView() }
                        label: { Label("Live HR", systemImage: "heart.fill") }
                }

                if !watchManager.workoutShareAuthorized && !watchManager.isActive {
                    Section {
                        Button {
                            Task { _ = await watchManager.requestWorkoutAuthorization() }
                        } label: {
                            Label("Health access needed. Tap to enable.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                        .accessibilityIdentifier("healthWarningRow")
                    }
                }

                Section {
                    NavigationLink { HRSettingsView() }
                        label: { Label("Heart-rate source", systemImage: "heart.fill") }

                    NavigationLink { WatchUnitsView(appSettings: watchAppSettings) }
                        label: { Label("Units", systemImage: "scalemass") }
                }

                Section("Phone Sync") {
                    HStack {
                        Label("Status", systemImage: "iphone.and.arrow.forward")
                        Spacer()
                        if watchManager.phoneSyncState.isInProgress {
                            ProgressView()
                                .controlSize(.mini)
                        }
                        Text(watchManager.phoneSyncState.settingsText(lastSyncAt: watchManager.lastPhoneSyncAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    HStack {
                        Label("Last sync", systemImage: "clock.arrow.2.circlepath")
                        Spacer()
                        Text(WatchSync.Status.lastSyncText(watchManager.lastPhoneSyncAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Button {
                        watchManager.requestSettingsSync()
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(watchManager.phoneSyncState.isInProgress)
                }
            }
            .navigationTitle("Cladiron")
        }
    }

    var cardioTypes: [CardioType] { [.run, .walk, .cycle, .swim, .hiit, .boxing, .rowing, .other] }

    @ViewBuilder
    private func cardioSetupView(for ct: CardioType) -> some View {
        let kind = ct.toCardioKind()
        if ct == .hiit || ct == .boxing {
            WatchIntervalSetupView(kind: ct.displayName, model: intervalSetupModel(kind: ct.displayName)) { plan in
                activeIntervalSession = ActiveIntervalSession(plan: plan, kind: ct.displayName)
            }
        } else {
            WatchCardioSetupView(kind: kind, location: $cardioLocation, lapLength: $cardioLapLength, unit: watchAppSettings.unit) { spec in
                watchManager.startWorkout(type: ct.rawValue, spec: spec)
                activeCardioKind = kind
            }
        }
    }

    private func intervalSetupModel(kind: String) -> IntervalSetupModel {
        let syncedWarmup = watchManager.lastPhoneSyncAt == nil ? nil : watchAppSettings.warmupMinutes * 60
        let syncedCooldown = watchManager.lastPhoneSyncAt == nil ? nil : watchAppSettings.cooldownMinutes * 60
        return IntervalSetupModel(kind: kind, warmupSeconds: syncedWarmup, cooldownSeconds: syncedCooldown)
    }
}

private struct ActiveIntervalSession {
    let plan: IntervalPlan
    let kind: String
}

// MARK: - Live HR + Settings views

private struct LiveHRView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 8) {
                    if watchManager.isMonitoring {
                        Text(zoneLabel).font(.caption.bold()).foregroundStyle(zoneColor)
                        Text(bpmText).font(.system(size: 56, weight: .bold, design: .monospaced)).foregroundStyle(zoneColor)
                        HStack(spacing: 3) { ForEach(1...5, id: \.self) { z in RoundedRectangle(cornerRadius: 2).fill(z <= zone ? zoneColor : .gray.opacity(0.25)).frame(width: 28, height: 6) } }
                        Button("Stop") { watchManager.stopMonitoringSession() }.buttonStyle(.bordered).padding(.top, 10)
                    } else if watchManager.isActive {
                        Text(zoneLabel).font(.caption.bold()).foregroundStyle(zoneColor)
                        Text(bpmText).font(.system(size: 56, weight: .bold, design: .monospaced)).foregroundStyle(zoneColor)
                        HStack(spacing: 3) { ForEach(1...5, id: \.self) { z in RoundedRectangle(cornerRadius: 2).fill(z <= zone ? zoneColor : .gray.opacity(0.25)).frame(width: 28, height: 6) } }
                    } else {
                        Text("Not monitoring").font(.caption.bold()).foregroundStyle(.secondary)
                        Text("--").font(.system(size: 56, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                        HStack(spacing: 3) { ForEach(1...5, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(.gray.opacity(0.25)).frame(width: 28, height: 6) } }
                        Button("Start monitoring") { watchManager.startMonitoringSession() }.buttonStyle(.borderedProminent).tint(.blue).padding(.top, 8)
                        Text("Runs a sensor-only session.\nNothing is saved to Health.").font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 8).padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
        }
        .navigationTitle("Live HR")
    }
    private var bpmText: String { guard let bpm = watchManager.currentBPM else { return "--" }; return String(format: "%.0f", bpm) }
    private var zone: Int { guard let bpm = watchManager.currentBPM else { return 0 }; let pct = bpm / (220.0 - 30); switch pct { case ..<0.60: return 1; case ..<0.70: return 2; case ..<0.80: return 3; case ..<0.90: return 4; default: return 5 } }
    private var zoneLabel: String { switch zone { case 1: "Recovery"; case 2: "Endurance"; case 3: "Tempo"; case 4: "Threshold"; case 5: "Max"; default: "--" } }
    private var zoneColor: Color { switch zone { case 1: .cyan; case 2: .green; case 3: .yellow; case 4: .orange; case 5: .red; default: .secondary } }
}

private struct HRSettingsView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    var body: some View {
        List {
            Section("Heart Rate Source") {
                ForEach(HRSource.allCases, id: \.self) { source in
                    Button { watchManager.hrSource = source; watchManager.switchToSource(source) } label: {
                        HStack { Label(source.displayName, systemImage: source.symbol); Spacer(); if watchManager.hrSource == source { Image(systemName: "checkmark").foregroundStyle(.green) } }
                    }.buttonStyle(.plain)
                }
            }
            if watchManager.hrSource == .bluetooth {
                Section("Chest Strap Status") {
                    HStack {
                        Circle().fill(bleColor).frame(width: 8, height: 8)
                        Text(bleText).font(.caption)
                    }
                    if let b = watchManager.bleBattery { Label("Battery: \(b)%", systemImage: b < 20 ? "battery.0percent" : b < 45 ? "battery.25percent" : b < 70 ? "battery.50percent" : b < 90 ? "battery.75percent" : "battery.100percent").font(.caption) }
                }
            }
            Section { Button("Request HealthKit Access") { Task { _ = await watchManager.requestWorkoutAuthorization() } } }
        }.navigationTitle("Settings")
    }
    private var bleColor: Color { guard let s = watchManager.bleState else { return .secondary }; switch s { case .scanning: return .blue; case .connected: return .green; case .disconnected: return .orange } }
    private var bleText: String { guard let s = watchManager.bleState else { return "Not active" }; switch s { case .scanning: return "Scanning..."; case .connected: return "Connected"; case .disconnected: return "Disconnected" } }
}

extension CardioType {
    func toCardioKind() -> WorkoutConfigurationSpec.CardioKind {
        switch self {
        case .run: return .run
        case .walk: return .walk
        case .cycle: return .cycle
        case .swim: return .swim
        case .hiit: return .hiit
        case .boxing: return .boxing
        case .rowing: return .rowing
        case .other: return .other
        }
    }
}
