import SwiftUI
import SwiftData
import WatchConnectivity
import CadenceCore
import CadenceFeatures

struct WatchRootView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    @Environment(AppSettings.self) private var watchAppSettings
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var cardioLocation: WorkoutConfigurationSpec.Location = .outdoor
    @State private var cardioLapLength: Double = 25
    @State private var activeCardioKind: WorkoutConfigurationSpec.CardioKind?
    @State private var activeCardioSpec: WorkoutConfigurationSpec?
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
            } else if let activeCardioKind, let activeCardioSpec {
                WatchCardioSessionView(kind: activeCardioKind, spec: activeCardioSpec) {
                    self.activeCardioKind = nil
                    self.activeCardioSpec = nil
                }
            } else {
                launcher
            }
        }
        .onChange(of: watchManager.customExercisesUpdatedAt) { _, _ in
            watchManager.applyCustomExercises(watchManager.customExerciseRows, in: context)
        }
        .accessibilityIdentifier("watch.root")
    }

    private var launcher: some View {
        NavigationStack {
            List {
                if let resume = resumableStrengthSession {
                    Section {
                        NavigationLink { WatchStrengthView(resuming: resume) }
                            label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise.circle.fill").foregroundStyle(.green)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Resume \(resume.title.isEmpty ? "Workout" : resume.title)")
                                            .fontWeight(.semibold)
                                        Text("\(resume.orderedSets.count) sets logged")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .accessibilityIdentifier("watch.resumeStrength")
                            // Abandoned sessions were previously deletable only by
                            // opening them, which starts a workout session just to
                            // throw one away.
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    discardResumable(resume)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .accessibilityIdentifier("watch.resumeStrength.delete")
                            }
                    }
                }

                Section("Your Plan") {
                    yourPlanRows
                }

                Section("Strength Workout") {
                    NavigationLink { WatchStrengthStartView() }
                        label: { Label("Strength Workout", systemImage: "dumbbell.fill") }
                        .accessibilityIdentifier("watch.startStrength")
                }

                Section {
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
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "iphone.and.arrow.forward")
                            Text("Status").fontWeight(.bold)
                            Spacer()
                            if watchManager.phoneSyncState.isInProgress {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                        }
                        Text(watchManager.phoneSyncState.settingsText(lastSyncAt: watchManager.lastPhoneSyncAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Image(systemName: "clock.arrow.2.circlepath")
                            Text("Last sync").fontWeight(.bold)
                        }
                        Text(WatchSync.Status.lastSyncText(watchManager.lastPhoneSyncAt))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        watchManager.requestSettingsSync()
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(watchManager.phoneSyncState.isInProgress)
                }

                Section {
                    NavigationLink {
                        WatchAboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                    .accessibilityIdentifier("watch.about")
                }
            }
            .navigationTitle("Cladiron")
        }
    }

    private var resumableStrengthSession: WorkoutSession? {
        sessions.filter(\.isResumable).first
    }

    /// Deletes an abandoned watch-only session in place and tells the phone to
    /// drop its copy, without opening the workout.
    private func discardResumable(_ session: WorkoutSession) {
        WatchHaptics.tap()
        guard let payload = WatchResumableSession.discard(session, in: context) else { return }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload)
    }

    @ViewBuilder
    private var yourPlanRows: some View {
        if let plan = watchManager.todayPlan {
            if plan.sessions.isEmpty || plan.isRestDay {
                Label("Rest", systemImage: "bed.double.fill")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(plan.sessions) { session in
                    switch session.kind {
                    case .strength:
                        NavigationLink {
                            WatchStrengthView(
                                title: session.label.isEmpty ? "Strength" : session.label,
                                plannedExerciseNames: session.exerciseNames,
                                repLadder: session.repLadder,
                                planPayload: session.planPayload
                            )
                        } label: {
                            plannedStrengthLabel(session)
                        }
                    case .cardio:
                        Button {
                            startPlannedCardio(session)
                        } label: {
                            plannedCardioLabel(session)
                        }
                    case .rest:
                        Label(session.label.isEmpty ? "Rest" : session.label, systemImage: "bed.double.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            Text("Open Cladiron on iPhone to sync today.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func plannedStrengthLabel(_ session: WatchSync.TodayPlan.Session) -> some View {
        HStack {
            Image(systemName: "checklist.checked").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.label.isEmpty ? "Strength" : session.label)
                    .fontWeight(.semibold)
                if !session.exerciseNames.isEmpty {
                    Text(session.exerciseNames.prefix(3).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func plannedCardioLabel(_ session: WatchSync.TodayPlan.Session) -> some View {
        HStack {
            Image(systemName: cardioType(from: session.cardioType).symbol).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.label.isEmpty ? "Cardio" : session.label)
                    .fontWeight(.semibold)
                let detail = plannedCardioDetail(session)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func plannedCardioDetail(_ session: WatchSync.TodayPlan.Session) -> String {
        var parts: [String] = []
        if let minutes = session.durationMinutes { parts.append("\(minutes) min") }
        if let zone = session.zone { parts.append("Z\(zone)") }
        return parts.joined(separator: " · ")
    }

    private func startPlannedCardio(_ session: WatchSync.TodayPlan.Session) {
        let ct = cardioType(from: session.cardioType)
        if ct == .hiit || ct == .boxing {
            let richCardio = session.planPayload?.cardio.first
            if let data = richCardio?.intervalPlanData,
               let plan = try? JSONDecoder().decode(IntervalPlan.self, from: data) {
                activeIntervalSession = ActiveIntervalSession(plan: plan, kind: ct.displayName)
            } else {
                let model = intervalSetupModel(kind: ct.displayName)
                activeIntervalSession = ActiveIntervalSession(plan: model.intervalPlan(), kind: ct.displayName)
            }
        } else {
            let kind = ct.toCardioKind()
            let richCardio = session.planPayload?.cardio.first
            let duration = richCardio?.durationSeconds ?? session.durationMinutes.map { $0 * 60 }
            let zone = richCardio?.targetZone ?? session.zone
            let spec = WorkoutConfigurationSpec(
                for: ct.rawValue,
                plannedDurationSeconds: duration,
                targetZone: zone)
            watchManager.startWorkout(type: ct.rawValue, spec: spec)
            activeCardioKind = kind
            activeCardioSpec = spec
        }
    }

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
                activeCardioSpec = spec
            }
        }
    }

    private func intervalSetupModel(kind: String) -> IntervalSetupModel {
        let isHIITOrBoxing = kind.lowercased() == "hiit" || kind.lowercased() == "boxing"
        let syncedWarmup = isHIITOrBoxing ? nil : (watchManager.lastPhoneSyncAt == nil ? nil : watchAppSettings.warmupMinutes * 60)
        let syncedCooldown = isHIITOrBoxing ? nil : (watchManager.lastPhoneSyncAt == nil ? nil : watchAppSettings.cooldownMinutes * 60)
        return IntervalSetupModel(kind: kind, warmupSeconds: syncedWarmup, cooldownSeconds: syncedCooldown)
    }
}

// MARK: - Live HR + Settings views

private struct LiveHRView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if watchManager.isMonitoring || watchManager.isActive {
                Text(bpmText)
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(zoneColor)
                    .padding(.top, 0)
                Text(zoneLabel).font(.caption.bold()).foregroundStyle(zoneColor)
                HStack(spacing: 3) { ForEach(1...5, id: \.self) { z in RoundedRectangle(cornerRadius: 2).fill(z <= zone ? zoneColor : .gray.opacity(0.25)).frame(width: 28, height: 6) } }
                Button("Stop") { watchManager.stopWorkout(save: false) }.buttonStyle(.bordered).padding(.top, 10)
            } else {
                Text("--")
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 0)
                HStack(spacing: 3) { ForEach(1...5, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(.gray.opacity(0.25)).frame(width: 28, height: 6) } }
                Button("Start monitoring") { watchManager.startMonitoringSession() }.buttonStyle(.borderedProminent).tint(.blue).padding(.top, 8)
            }
            Spacer(minLength: 0).frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .background(zoneBackgroundColor)
        .navigationTitle("Live HR")
    }
    private var bpmText: String { guard let bpm = watchManager.currentBPM else { return "--" }; return String(format: "%.0f", bpm) }
    private var zone: Int { guard let bpm = watchManager.currentBPM else { return 0 }; let pct = bpm / (220.0 - 30); switch pct { case ..<0.60: return 1; case ..<0.70: return 2; case ..<0.80: return 3; case ..<0.90: return 4; default: return 5 } }
    private var zoneLabel: String { switch zone { case 1: "Z1 / Recovery"; case 2: "Z2 / Endurance"; case 3: "Z3 / Tempo"; case 4: "Z4 / Threshold"; case 5: "Z5 / Max"; default: "--" } }
    private var zoneColor: Color { switch zone { case 1: .cyan; case 2: .green; case 3: .yellow; case 4: .orange; case 5: .red; default: .secondary } }
    private var zoneBackgroundColor: Color {
        guard watchManager.isMonitoring || watchManager.isActive else { return Color.clear }
        return zoneColor.opacity(0.15)
    }
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
