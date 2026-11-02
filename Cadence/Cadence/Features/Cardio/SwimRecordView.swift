import SwiftUI
import Combine
import SwiftData
import CadenceCore
import CadenceFeatures

/// Pool swim recorder (round4b feedback #3): time + lap count only — no GPS,
/// distance, or calorie estimate. Set a lap goal, start the clock, tap to count
/// laps, then End to save. Deliberately minimal, per "just time and number of
/// target laps, nothing complex."
struct SwimRecordView: View {
    var onSchedule: ((Date) async throws -> Void)? = nil
    /// Notifies the presenter (Home) the instant a workout is persisted, so its
    /// history-derived surfaces refresh without waiting for app re-entry.
    var onSaved: (CardioWorkout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var started = false
    @State private var startDate = Date()
    @State private var now = Date()
    @State private var targetLaps = 20
    @State private var laps = 0
    @State private var finishedSummary: WorkoutSummaryData?
    @State private var schedulePresented = false
    /// Swim has no recorder: pause freezes the wall-clock elapsed.
    @State private var pausedAt: Date?
    @State private var pausedTotal: TimeInterval = 0
    @State private var cancelled = false
    /// Coordinator session id; inactivity is owned by `AppModel.phoneCardio`, not this view.
    @State private var phoneSessionID: UUID?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let finishedSummary {
                // The swim is already saved; show its summary (laps + duration).
                WorkoutSummaryView(data: finishedSummary, onDone: { dismiss() })
            } else {
                NavigationStack {
                    Group {
                        if started { liveScreen } else { setupScreen }
                    }
                    .navigationTitle(started ? "Swimming" : "Swim")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { cancelled = true; if let id = phoneSessionID { model.endPhoneCardio(id) }; dismiss() }.accessibilityIdentifier("swim.cancel")
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(started && !CardioPresentation.live(isPaused: pausedAt != nil).allowsInteractiveMinimize)
        .onChange(of: pausedAt != nil) { _, paused in announceCardioPaused(paused) }
        .onAppear { model.phoneCardioHasLiveView = true; adoptParked() }
        .onDisappear { model.phoneCardioHasLiveView = false; parkIfMinimized() }
        .onChange(of: laps) { _, new in
            // Lap taps are explicit user actions (the only safe swim evidence).
            if let id = phoneSessionID { model.phoneCardioContexts[id]?.laps = new }
            model.phoneCardioUserAction()
        }
        .keepAwake(started && finishedSummary == nil)
        .onReceive(tick) { now = $0; phoneTick() }
        .sheet(isPresented: $schedulePresented) {
            if let onSchedule {
                ScheduleWorkoutSheet(title: "Swim", onSave: onSchedule)
            }
        }
    }

    private var elapsed: TimeInterval {
        let ref = pausedAt ?? now
        return max(0, ref.timeIntervalSince(startDate) - pausedTotal)
    }

    private func adoptParked() {
        guard !started, let parked = model.parkedCardio.session, parked.route == .swim else { return }
        _ = model.parkedCardio.take()
        startDate = parked.startDate
        laps = parked.laps
        targetLaps = parked.targetLaps
        pausedTotal = parked.clock.pausedAccumulated
        pausedAt = parked.clock.pausedSince
        now = Date()
        started = true
        phoneSessionID = model.phoneCardio.session?.id
    }

    private func parkIfMinimized() {
        guard started, !cancelled, finishedSummary == nil, let pausedAt else { return }
        model.parkedCardio.park(ParkedCardioSession(
            route: .swim, type: .swim,
            clock: WorkoutClock(startedAt: startDate, pausedAccumulated: pausedTotal, pausedSince: pausedAt),
            laps: laps, targetLaps: targetLaps, startDate: startDate))
    }

    private func togglePause() {
        if let p = pausedAt {
            guard model.phoneCardioMayResume(phoneSessionID) else { phoneTick(); return }
            pausedTotal += Date().timeIntervalSince(p); pausedAt = nil
        } else {
            if let id = phoneSessionID { model.phoneCardioManualPause(id) }
            pausedAt = Date()
        }
    }

    /// Swim has no sensors the recorder can trust, so it uses the timer fallback: lap taps
    /// and controls are the only evidence, and the automatic pause is visible.
    private func phoneTick() {
        guard let id = phoneSessionID else { return }
        Task {
            await model.reconcilePhoneCardio()
            if let w = model.claimAutoEnded(id) {
                onSaved(w); finishedSummary = WorkoutSummaryData.from(cardio: w); return
            }
            if let p = model.phoneCardioAutoPausedAt(id), pausedAt == nil { pausedAt = p }
        }
    }

    private var setupScreen: some View {
        VStack(spacing: 24) {
            Image(systemName: "figure.pool.swim").scaledSystemFont(64, relativeTo: .largeTitle).foregroundStyle(.tint)
            Stepper(value: $targetLaps, in: 1...200) {
                HStack { Text("Target laps"); Spacer(); Text("\(targetLaps)").monospacedDigit() }
            }
            .accessibilityIdentifier("swim.targetLaps")

            HStack {
                @Bindable var settings = settings
                Toggle("Use HR monitoring", isOn: $settings.useHRMonitoring)
                    .accessibilityIdentifier("swim.hrToggle")
            }

            Button {
                startDate = Date(); now = Date(); started = true
                let ctx = PhoneCardioContext(recorder: nil)
                ctx.targetLaps = targetLaps
                phoneSessionID = model.beginPhoneCardio(
                    type: .swim, route: "swim", start: startDate, profile: .timerOnly,
                    autoPauseEnabled: settings.lastCardioSettings.autoPause, context: ctx)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
            }
            .cadenceGlassButton(prominent: true, tint: .blue)
            .accessibilityIdentifier("swim.start")
            if onSchedule != nil {
                Button {
                    schedulePresented = true
                } label: {
                    Label("Schedule Swim", systemImage: "calendar.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("swim.schedule")
            }
            Spacer()
        }
        .padding()
    }

    private var liveScreen: some View {
        VStack(spacing: 28) {
            HStack { WallClockLabel(); Spacer() }
            Text(Format.duration(elapsed))
                .scaledSystemFont(56, relativeTo: .largeTitle, weight: .bold, design: .rounded).monospacedDigit()
                .accessibilityIdentifier("swim.elapsed")

            VStack(spacing: 4) {
                Text("\(laps)/\(targetLaps)")
                    .scaledSystemFont(48, relativeTo: .largeTitle, weight: .bold, design: .rounded).monospacedDigit()
                    .accessibilityIdentifier("swim.laps")
                Text("laps").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 32) {
                Button { if laps > 0 { laps -= 1 } } label: {
                    Image(systemName: "minus.circle.fill").scaledSystemFont(48, relativeTo: .largeTitle)
                }
                .accessibilityIdentifier("swim.lapMinus")
                .accessibilityLabel("Remove a lap")
                Button { laps += 1 } label: {
                    Image(systemName: "plus.circle.fill").scaledSystemFont(48, relativeTo: .largeTitle)
                }
                .accessibilityIdentifier("swim.lapPlus")
                .accessibilityLabel("Add a lap")
            }
            .tint(.blue)

            Spacer()

            WorkoutControlBar(isPaused: pausedAt != nil, onPauseToggle: togglePause,
                              onEnd: endSwim, idPrefix: "swim")
            if pausedAt != nil && model.phoneCardioAutoPaused { AutoPausedBanner(idPrefix: "swim") }
            if pausedAt != nil {
                ReturnToTodayButton(idPrefix: "swim") { dismiss() }
            }
        }
        .padding()
    }

    private func endSwim() {
        // A watch session started at the HR gate outlives the recorder unless we
        // tear it down here (field-test batch 2026-08-20 issue 5).
        if let id = phoneSessionID { model.endPhoneCardio(id) }
        model.stopWatchWorkout()
        if let p = pausedAt { pausedTotal += Date().timeIntervalSince(p); pausedAt = nil }
        // Paused time is excluded from the saved span.
        let end = Date().addingTimeInterval(-pausedTotal)
        Task {
            let profile = await cardioIntensityProfile(model: model, settings: settings)
            let duration = end.timeIntervalSince(startDate)
            let intensity = CardioMinuteAccumulator.summarize(duration: duration, samples: [], profile: profile)
            let summary = CardioWorkoutSummary(id: UUID(), type: .swim, start: startDate, end: end,
                                               hrSamples: [], route: [], intensityProfile: profile,
                                               intensitySummary: intensity,
                                               metEstimate: METEstimator.cardio(type: .swim, duration: duration))
            if let saved = try? WorkoutRepository.saveSwim(
                id: summary.id,
                start: startDate, end: end,
                laps: laps, targetLaps: targetLaps,
                healthKitWorkoutUUID: nil,
                intensityProfile: summary.intensityProfile,
                intensitySummary: summary.intensitySummary,
                metEstimate: summary.metEstimate,
                in: context) {
                let report = await model.healthBackup.enqueueAndDrain(cardio: saved)
                if let hkID = report.savedObjectIDs[saved.id] {
                    saved.healthKitWorkoutUUID = hkID
                    try? context.save()
                }
                onSaved(saved)
                finishedSummary = WorkoutSummaryData.from(cardio: saved)
            } else {
                dismiss()
            }
        }
    }
}
