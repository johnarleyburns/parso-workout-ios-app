import SwiftUI
import Charts
import MapKit
import CadenceCore
import CadenceFeatures

/// The always-on post-workout summary (field-testing Round 4 A3). Renders a pure
/// `WorkoutSummaryData` — strength rolls up exercises + total volume; cardio shows
/// distance/pace/calories/HR plus an HR chart and route map when present. Every
/// in-workout screen shows this after a confirmed End. Formatting lives here
/// (`Format.*`, `CardioMath.formatPace`); the value type stays formatting-free.
struct WorkoutSummaryView: View {
    let data: WorkoutSummaryData
    @Environment(AppSettings.self) private var settings
    /// Strength only: persist a summary `HKWorkout`. `nil` ⇒ no button (a recorded
    /// cardio workout is already saved to Health when it ends).
    var onSaveHealth: (() async -> Void)? = nil
    /// Strength history only: open the set editor. `nil` ⇒ no Edit button.
    var onEdit: (() -> Void)? = nil
    /// Modal (post-workout) presentation: shows a Done button and wraps itself in
    /// a `NavigationStack`. `nil` ⇒ the view is *pushed* (history), so it relies on
    /// the ambient stack's Back button instead.
    var onDone: (() -> Void)? = nil

    @State private var healthSaved = false
    /// Which exercises are showing their read-only set detail. Per-exercise, so
    /// several can be open at once (field test 2026-08-18 #1).
    @State private var expandedExerciseIDs: Set<String> = []

    var body: some View {
        if onDone != nil {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                metricsGrid
                if data.kind == .strength, !data.exercises.isEmpty { strengthSection }
                if data.kind == .strength, data.warmupSec > 0 || data.cooldownSec > 0 { warmCoolSection }
                if let interval = data.interval { intervalSection(interval) }
                if !data.hr.isEmpty { hrChart }
                if data.route.count > 1 { routeMap }
            }
            .padding()
        }
        .navigationTitle("Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { onEdit() }.accessibilityIdentifier("summary.edit")
                }
            }
            if let onDone {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }.accessibilityIdentifier("summary.done")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let onSaveHealth {
                Button {
                    Task { await onSaveHealth(); withAnimation { healthSaved = true } }
                } label: {
                    Label(healthSaved ? "Saved to Apple Health" : "Save to Apple Health",
                          systemImage: healthSaved ? "checkmark.circle.fill" : "heart.text.square")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(healthSaved ? .green : .pink)
                .disabled(healthSaved)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityIdentifier("summary.saveHealth")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: data.symbol)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("summary.icon")
                .accessibilityHidden(true)
            Text(data.title)
                .font(.title.weight(.bold))
                .accessibilityIdentifier("summary.title")
            HStack(spacing: 8) {
                Text(data.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if data.isLogged { LoggedTag() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Metrics

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metric("Duration", Format.duration(data.durationSec), id: "summary.duration")
            if data.kind == .strength {
                if let vol = data.totalVolumeKg {
                    metric("Total Volume", Format.weight(vol, unit: settings.unit, decimals: 0),
                           id: "summary.metric.volume")
                }
                metric("Sets", Format.integer(data.setCount), id: "summary.metric.sets")
                // Total reps across all exercises (round4b feedback #8) — useful
                // for volume/work even on bodyweight days.
                metric("Total Reps", Format.integer(data.totalReps), id: "summary.metric.reps")
            } else {
                // Swimming (round4b feedback #3): laps, not distance/pace.
                if let laps = data.laps {
                    let value = data.targetLaps.map { "\(laps)/\($0)" } ?? "\(laps)"
                    metric("Laps", value, id: "summary.metric.laps")
                } else if let d = data.distanceM {
                    metric("Distance", Format.distance(d), id: "summary.metric.distance")
                    metric("Pace", CardioMath.formatPace(secPerKm: data.paceSecPerKm),
                           id: "summary.metric.pace")
                }
                if let avg = data.avgHR {
                    metric("Avg HR", Format.heartRate(avg), id: "summary.metric.avgHR")
                }
                if let mx = data.maxHR {
                    metric("Max HR", Format.heartRate(mx), id: "summary.metric.maxHR")
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String, id: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Strength exercises

    /// Every exercise expands **in place** to a read-only, per-performer set list
    /// (field test 2026-08-18 #1, decisions **D6**/**D7**): the old bottom
    /// `Partners` roll-up is gone because those numbers now live in these rows,
    /// and tapping never pushes the editor — `Edit` in the toolbar does.
    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercises").font(.headline)
            ForEach(data.exercises, id: \.name) { ex in
                let key = ex.sourceExerciseID?.uuidString ?? ex.name
                WorkoutSummaryExerciseRow(
                    line: ex,
                    unit: settings.unit,
                    isExpanded: expandedExerciseIDs.contains(key),
                    idPrefix: "summary.exercise",
                    onToggle: {
                        withAnimation {
                            if expandedExerciseIDs.contains(key) {
                                expandedExerciseIDs.remove(key)
                            } else {
                                expandedExerciseIDs.insert(key)
                            }
                        }
                    })
            }
            Text("Tap an exercise to see every set. Use Edit to change them.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Strength warm-up / cool-down (feedback batch 6)

    /// Actual warm-up / cool-down time consumed for a strength session — e.g.
    /// skipping a 10:00 cool-down at 3:00 shows 3:00.
    private var warmCoolSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Warm-up & Cool-down").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                if data.warmupSec > 0 {
                    intervalRow("Warm-up", Format.duration(data.warmupSec), id: "summary.strength.warmup")
                }
                if data.cooldownSec > 0 {
                    intervalRow("Cool-down", Format.duration(data.cooldownSec), id: "summary.strength.cooldown")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Interval (HIIT/boxing) detail

    /// Protocol structure for an interval workout (feedback batch 4 / roadmap P5):
    /// rounds, work/rest, warm-up/cool-down, and how many rounds were completed.
    private func intervalSection(_ s: IntervalSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intervals").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                intervalRow("Protocol", s.protocolName, id: "summary.interval.protocol")
                intervalRow("Rounds",
                            "completed \(s.completedRounds)/\(s.rounds)",
                            id: "summary.interval.rounds")
                intervalRow("Work / Rest",
                            "\(Format.duration(s.workSeconds)) / \(Format.duration(s.restSeconds))",
                            id: "summary.interval.workRest")
                if s.warmupSeconds > 0 {
                    intervalRow("Warm-up", Format.duration(s.warmupSeconds),
                                id: "summary.interval.warmup")
                }
                if s.cooldownSeconds > 0 {
                    intervalRow("Cool-down", Format.duration(s.cooldownSeconds),
                                id: "summary.interval.cooldown")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func intervalRow(_ title: String, _ value: String, id: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier(id)
        }
    }

    // MARK: Cardio HR chart + route

    private var hrChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate").font(.headline)
            Chart {
                ForEach(Array(data.hr.enumerated()), id: \.offset) { _, sample in
                    LineMark(x: .value("Time", sample.t / 60),
                             y: .value("BPM", sample.bpm))
                        .foregroundStyle(.red)
                }
            }
            .chartXAxisLabel("min")
            .frame(height: 180)
            .accessibilityIdentifier("summary.hrChart")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heart rate over time")
            .accessibilityValue(hrChartAXSummary(data.hr.map(\.bpm)))
        }
    }

    /// Spoken summary of an HR series for VoiceOver (the chart itself is opaque).
    private func hrChartAXSummary(_ bpms: [Double]) -> String {
        WorkoutSummaryPresenter.hrChartAXSummary(bpms)
    }

    private var routeMap: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Route").font(.headline)
            Map(initialPosition: .region(routeRegion)) {
                MapPolyline(coordinates: data.route.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
                })
                .stroke(.blue, lineWidth: 4)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("summary.map")
        }
    }

    private var routeRegion: MKCoordinateRegion {
        let lats = data.route.map(\.lat), lons = data.route.map(\.lon)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.005, (maxLat - minLat) * 1.4),
                                    longitudeDelta: max(0.005, (maxLon - minLon) * 1.4))
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// A small "Logged" chip distinguishing a manually-logged workout from a
/// live-recorded one (feedback batch 6). Live workouts show no tag.
struct LoggedTag: View {
    var body: some View {
        Label("Logged", systemImage: "square.and.pencil")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(.tint)
            .accessibilityIdentifier("workout.loggedTag")
    }
}
