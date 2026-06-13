import SwiftUI
import Charts
import MapKit
import CadenceCore

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
                if data.kind == .strength, !data.partners.isEmpty { partnersSection }
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
            Image(systemName: data.kind == .strength ? "dumbbell.fill" : "figure.run")
                .font(.largeTitle)
                .foregroundStyle(.tint)
            Text(data.title)
                .font(.title.weight(.bold))
                .accessibilityIdentifier("summary.title")
            Text(data.date.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
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

    private var strengthSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exercises").font(.headline)
            ForEach(data.exercises, id: \.name) { ex in exerciseRow(ex, idPrefix: "summary.exercise") }
        }
    }

    /// Each training partner's roll-up (feedback batch 3) — partnered history
    /// shows what the partner did, kept separate from the owner's PRs/volume.
    private var partnersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Partners").font(.headline)
            ForEach(data.partners) { partner in
                VStack(alignment: .leading, spacing: 8) {
                    Text(partner.name).font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("summary.partner.\(partner.name)")
                    ForEach(partner.exercises, id: \.name) { ex in
                        exerciseRow(ex, idPrefix: "summary.partner.\(partner.name).exercise")
                    }
                }
            }
        }
    }

    private func exerciseRow(_ ex: WorkoutSummaryData.ExerciseLine, idPrefix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(ex.name).font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("\(idPrefix).\(ex.name)")
                Spacer()
                if let top = ex.topSetWeightKg {
                    Text(topLabel(top, bodyweight: ex.usesBodyweight))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Text("\(ex.setCount) set\(ex.setCount == 1 ? "" : "s") · reps \(ex.reps.map(String.init).joined(separator: ", "))")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    /// "top 100 kg", or for bodyweight: "BW" / "BW + 10 kg".
    private func topLabel(_ topKg: Double, bodyweight: Bool) -> String {
        if bodyweight {
            return topKg > 0 ? "BW + \(Format.weight(topKg, unit: settings.unit, decimals: 0))" : "BW"
        }
        return "top \(Format.weight(topKg, unit: settings.unit, decimals: 0))"
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
        }
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
