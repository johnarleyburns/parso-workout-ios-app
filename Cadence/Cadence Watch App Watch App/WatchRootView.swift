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
            if watchManager.needsInitialHealthAuthorization && !watchManager.isActive && !watchManager.isMonitoring {
                WatchHealthAuthorizationView()
            } else if let activeIntervalSession {
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
            // Reconcile the local catalog after the launcher has had a frame to
            // render. Incoming property-list parsing is already off-main; this
            // remaining SwiftData write is deliberately deferred as well.
            Task { @MainActor in
                await Task.yield()
                watchManager.applyCustomExercises(watchManager.customExerciseRows, in: context)
            }
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
                        Label(watchManager.phoneSyncState.isFailure ? "Retry sync" : "Sync now",
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(watchManager.phoneSyncState.isInProgress)
                    .accessibilityIdentifier("watch.phoneSync.retry")
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
