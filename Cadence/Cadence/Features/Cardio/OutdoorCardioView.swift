import SwiftUI
import MapKit
import CadenceCore
import CadenceFeatures

/// Purpose-built outdoor GPS screen for Run / Walk / Cycle (field-testing §05).
/// Live map with a growing route polyline, big distance + pace, HR/zone, and
/// wall-clock elapsed that survives backgrounding (a call / the phone in a
/// pocket). Reuses `CardioRecorder` + the shared `LocationTracker`.
///
/// Shows a pre-workout HR gate before starting, letting the user connect a
/// Bluetooth chest strap for live HR.
struct OutdoorCardioView: View {
    let type: CardioType
    /// Free-text label for an "Other Cardio" workout (feedback batch 6), else nil.
    var customTitle: String? = nil
    /// Optional distance goal in meters (feedback batch 8): shows live progress and
    /// is saved on the workout. nil ⇒ no goal.
    var goalMeters: Double? = nil
    var captureHR = false
    /// Notifies the presenter (Home) the instant a workout is persisted, so its
    /// history-derived surfaces refresh without waiting for app re-entry.
    var onSaved: (CardioWorkout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    @State private var recorder: CardioRecorder?
    @State private var clock = WorkoutClock()
    @State private var now = Date()
    @State private var finishedSummary: WorkoutSummaryData?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsed: TimeInterval { clock.elapsed(now: now) }
    private var coordinates: [CLLocationCoordinate2D] {
        model.location.fixes.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }
    /// Pace from GPS distance over wall-clock elapsed (correct after background).
    private var paceSecPerKm: Double? {
        guard let r = recorder else { return nil }
        return CardioMath.paceSecPerKm(distanceMeters: r.distanceMeters, seconds: elapsed)
    }

    var body: some View {
        if let finishedSummary {
            WorkoutSummaryView(data: finishedSummary, onDone: { dismiss() })
        } else {
            liveView
                .keepAwake()
                .onAppear { startIfNeeded() }
                // Safety net: background GPS must never outlive this screen. The
                // End/Cancel paths already stop the tracker; this guards any other
                // dismissal so location is only ever active during a live workout.
                .onDisappear { if recorder?.isRecording == true { model.location.stop() } }
        }
    }

    private var liveView: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack { WallClockLabel(); Spacer() }
                liveMap
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("outdoor.map")
                    .accessibilityLabel("Route map, \(Format.distance(recorder?.distanceMeters ?? 0))")

                Text(Format.duration(elapsed))
                    .scaledSystemFont(52, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .accessibilityIdentifier("outdoor.elapsed")

                HStack(spacing: 14) {
                    bigMetric(Format.distance(recorder?.distanceMeters ?? 0), "Distance", id: "outdoor.distance")
                    bigMetric(CardioMath.formatPace(secPerKm: paceSecPerKm), "Pace", id: "outdoor.pace")
                }
                if let goalMeters,
                   let p = CardioMath.goalProgress(distanceMeters: recorder?.distanceMeters ?? 0, goalMeters: goalMeters) {
                    VStack(spacing: 4) {
                        HStack {
                            Text("Goal \(Format.distance(goalMeters))").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(p.fraction >= 1 ? "Goal met ✓" : "\(Format.distance(p.remainingMeters)) to go")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(p.fraction >= 1 ? .green : .secondary)
                        }
                        ProgressView(value: p.fraction).tint(.green)
                    }
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("outdoor.goal")
                }
                LiveHRBigView(bpm: recorder?.currentBPM, zone: recorder?.zone ?? 0,
                              avgHR: recorder?.avgHR, idPrefix: "outdoor")

                Spacer()

                WorkoutControlBar(
                    isPaused: clock.isPaused,
                    onPauseToggle: togglePause,
                    onEnd: { Task { await end() } },
                    idPrefix: "outdoor"
                )
            }
            .padding()
            .navigationTitle(type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.stopWatchWorkout(); _ = recorder?.end(); dismiss() }
                        .accessibilityIdentifier("outdoor.cancel")
                }
            }
        }
        .interactiveDismissDisabled(true)
        .onReceive(tick) { _ in
            now = Date()
            recorder?.tick()
        }
    }

    @ViewBuilder
    private var liveMap: some View {
        Map(position: .constant(.userLocation(fallback: .automatic))) {
            UserAnnotation()
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates).stroke(.blue, lineWidth: 5)
            }
        }
    }

    private func bigMetric(_ value: String, _ title: String, id: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier(id)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func startIfNeeded() {
        guard recorder == nil else { return }
        model.location.setHighAccuracy(settings.gpsHighAccuracy)
        model.location.requestAuthorization()
        let r = CardioRecorder(location: model.location, hrm: model.hrm)
        r.start(type: type)
        recorder = r
        clock = WorkoutClock(startedAt: Date())
        WorkoutCues.startBeepSequence(enabled: settings.workoutSounds)
    }

    private func togglePause() {
        guard let r = recorder else { return }
        if clock.isPaused { clock.resume(); r.resume() } else { clock.pause(); r.pause() }
    }

    private func end() async {
        guard let r = recorder else { dismiss(); return }
        // A watch session started at the HR gate outlives the recorder unless we
        // tear it down here (field-test batch 2026-08-20 issue 5).
        model.stopWatchWorkout()
        WorkoutCues.endBeepSequence(enabled: settings.workoutSounds)
        clock.end()
        var summary = r.end()
        summary.customTitle = customTitle
        summary.targetDistanceMeters = goalMeters
        let hkID = await model.health.saveCardioWorkout(summary)
        let saved = try? WorkoutRepository.saveRecordedCardio(summary, source: .iphone,
                                                               healthKitWorkoutUUID: hkID, in: context)
        if let saved {
            onSaved(saved)
            finishedSummary = WorkoutSummaryData.from(cardio: saved)
        } else {
            dismiss()
        }
    }
}
