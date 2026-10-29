import SwiftUI
import Charts
import MapKit
import CadenceCore
import CadenceFeatures
import SwiftData

/// Cardio workout detail (FR-5.3): summary, HR overlay, and route map.
struct CardioDetailView: View {
    @Bindable var workout: CardioWorkout
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var datePickerPresented = false
    @State private var deletePresented = false
    @State private var titleEditorPresented = false
    @State private var editedTitle = ""

    var body: some View {
        List {
            Section {
                LabeledContent("Date", value: workout.start.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: Format.duration(workout.duration))
                if let laps = workout.laps {
                    LabeledContent("Laps", value: workout.targetLaps.map { "\(laps)/\($0)" } ?? "\(laps)")
                } else if let d = workout.distance {
                    LabeledContent("Distance", value: Format.distance(d))
                    LabeledContent("Pace", value: CardioMath.formatPace(
                        secPerKm: CardioMath.paceSecPerKm(distanceMeters: d, seconds: workout.duration)))
                }
                if let hr = workout.avgHeartRate { LabeledContent("Avg HR", value: Format.heartRate(hr)) }
                if let hr = workout.maxHeartRate { LabeledContent("Max HR", value: Format.heartRate(hr)) }
                if workout.originValue == .healthKitImported {
                    let origin = HealthKitWorkoutOriginPresenter.label(for: workout.healthKitProvenance)
                    LabeledContent("Source", value: origin.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(origin.accessibilityLabel)
                    if let detail = origin.detail {
                        LabeledContent("Recorded by", value: detail)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    LabeledContent("Source", value: workout.sourceValue.rawValue.capitalized)
                }
            }

            let hr = workout.orderedHRSamples
            if !hr.isEmpty {
                Section("Heart Rate") {
                    HRZoneChart(samples: hr.map { ($0.t, $0.bpm) },
                                maxHR: CardioIntensityProfile.resolved(
                                    userEnteredMaximumHR: settings.cardioMaximumHROverride,
                                    age: settings.userAge).maximumHR ?? CardioMath.defaultMaxHR(age: settings.userAge))
                    .frame(height: 180)
                    .accessibilityIdentifier("cardioDetail.hrChart")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Heart rate over time")
                    .accessibilityValue(hrChartAXSummary(hr.map(\.bpm)))
                }
            }

            if let summary = workout.intensitySummary {
                Section("Intensity") {
                    detailRow(String(localized: "Actual exercise"), "\(minutes(summary.actualDuration)) min")
                    detailRow(String(localized: "Below moderate"), "\(minutes(summary.belowModerateDuration)) min · 0 credited")
                    detailRow(String(localized: "Moderate"), "\(minutes(summary.moderateDuration)) min · \(minutes(summary.moderateDuration)) credited")
                    detailRow(String(localized: "Vigorous"), "\(minutes(summary.vigorousDuration)) min · \(minutes(summary.vigorousDuration * 2)) credited")
                    if summary.unclassifiedDuration > 0 {
                        detailRow(String(localized: "Unclassified"), "\(minutes(summary.unclassifiedDuration)) min")
                    }
                    detailRow(String(localized: "Guideline credit"), "\(minutes(summary.moderateEquivalentMinutes * 60)) min")
                    detailRow(String(localized: "Method"), summary.method.displayName)
                    detailRow(String(localized: "Confidence"), summary.confidence.displayName)
                    CoachSourcesLink(citationIds: CardioIntensityPolicy.citationIDs,
                                     contexts: CardioIntensitySourceContexts.contexts,
                                     identifier: "cardioDetail.intensity.science")
                }
                .accessibilityIdentifier("cardioDetail.intensity")
                if !summary.zoneDurations.isEmpty {
                    Section("Training Zones") {
                        ForEach(summary.zoneDurations.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { zone in
                            detailRow(zone.displayName, String(localized: "\(minutes(summary.zoneDurations[zone] ?? 0)) min"))
                        }
                    }
                    .accessibilityIdentifier("cardioDetail.trainingZones")
                }
            } else if workout.duration > 0 {
                Section("Intensity") {
                    Text("This workout predates intensity provenance. It remains in actual history, but its intensity credit is unclassified.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("cardioDetail.intensityLegacy")
            }

            if let met = workout.standardMETMinutes {
                Section("Activity Dose") {
                    detailRow(String(localized: "Standard MET"), workout.standardMETValue.map { String(format: "%.1f", $0) } ?? "—")
                    detailRow("MET-minutes", "\(Int(met.rounded()))")
                    Text("A separate standardized activity estimate; it is not guideline credit.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let citation = CitationRegistry.citation(forId: "compendium2024AdultPhysicalActivities") {
                        CitationLink(citation: citation, context: String(localized: "Adult Compendium of Physical Activities"), compact: true)
                    }
                }
                .accessibilityIdentifier("cardioDetail.activityDose")
            }

            if let interval = workout.intervalSummary {
                Section("Intervals") {
                    intervalRow(interval)
                }
            }

            let route = workout.orderedRouteSamples
            if route.count > 1 {
                Section("Route") {
                    RouteMap(samples: route)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("cardioDetail.map")
                }
                let splits = kmSplits(route)
                if !splits.isEmpty {
                    Section("Pace Splits") {
                        ForEach(Array(splits.enumerated()), id: \.offset) { i, secPerKm in
                            HStack {
                                Text("km \(i + 1)")
                                Spacer()
                                Text(CardioMath.formatPace(secPerKm: secPerKm)).monospacedDigit()
                            }
                        }
                    }
                    .accessibilityIdentifier("cardioDetail.splits")
                }
            }
        }
        .navigationTitle(workout.typeValue.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 14) {
                    Button { datePickerPresented = true } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Edit workout date")
                    .accessibilityIdentifier("cardioDetail.editDate")

                    Button(role: .destructive) { deletePresented = true } label: {
                        Image(systemName: "trash")
                    }
                    .foregroundStyle(.red)
                    .accessibilityLabel("Delete workout")
                    .accessibilityIdentifier("cardioDetail.delete")
                }
            }
        }
        .confirmationDialog("Delete this cardio workout?", isPresented: $deletePresented,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                try? WorkoutRepository.softDeleteCardio(workout, in: context)
                NotificationCenter.default.post(name: .workoutHistoryChanged, object: nil)
                dismiss()
            }
            .accessibilityIdentifier("cardioDetail.deleteConfirm")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the cardio workout. You can restore it from History → View Deleted.")
        }
        .sheet(isPresented: $datePickerPresented) {
            NavigationStack {
                DatePicker("Workout date", selection: Binding(
                    get: { workout.start },
                    set: { workout.start = $0; try? context.save() }
                ))
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Edit Date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { datePickerPresented = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    /// Seconds-per-km for each completed kilometer, from the route samples.
    private func kmSplits(_ route: [RouteSample]) -> [Double] {
        guard route.count > 1 else { return [] }
        var splits: [Double] = []
        var accumDist = 0.0
        var splitStartTime = route.first!.t
        for i in 1..<route.count {
            let a = route[i - 1], b = route[i]
            accumDist += GeoMath.distance(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon)
            if accumDist >= 1000 {
                splits.append(b.t - splitStartTime)
                splitStartTime = b.t
                accumDist -= 1000
            }
        }
        return splits
    }

    /// Spoken summary of an HR series for VoiceOver (the chart itself is opaque).
    private func hrChartAXSummary(_ bpms: [Double]) -> String {
        let valid = bpms.filter { $0 > 0 }
        guard !valid.isEmpty else { return String(localized: "No heart rate samples") }
        let lo = Int(valid.min() ?? 0)
        let hi = Int(valid.max() ?? 0)
        let avg = Int(valid.reduce(0, +) / Double(valid.count))
        return String(localized: "Average \(avg), range \(lo) to \(hi) beats per minute, \(valid.count) samples")
    }

    @ViewBuilder
    private func intervalRow(_ s: IntervalSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailRow(String(localized: "Protocol"), s.protocolName)
            detailRow(String(localized: "Rounds"), "completed \(s.completedRounds)/\(s.rounds)")
            detailRow(String(localized: "Work / Rest"),
                      "\(Format.duration(s.workSeconds)) / \(Format.duration(s.restSeconds))")
            if s.warmupSeconds > 0 {
                detailRow(String(localized: "Warm-up"), Format.duration(s.warmupSeconds))
            }
            if s.cooldownSeconds > 0 {
                detailRow(String(localized: "Cool-down"), Format.duration(s.cooldownSeconds))
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private func minutes(_ seconds: TimeInterval) -> String {
        String(Int((seconds / 60).rounded()))
    }
}

private struct RouteMap: View {
    let samples: [RouteSample]

    var body: some View {
        Map(initialPosition: .region(region)) {
            MapPolyline(coordinates: samples.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            })
            .stroke(.blue, lineWidth: 4)
        }
    }

    private var region: MKCoordinateRegion {
        let lats = samples.map(\.lat), lons = samples.map(\.lon)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.005, (maxLat - minLat) * 1.4),
                                    longitudeDelta: max(0.005, (maxLon - minLon) * 1.4))
        return MKCoordinateRegion(center: center, span: span)
    }
}


/// Shared "How this applies" copy for the single aggregated cardio-intensity science link.
enum CardioIntensitySourceContexts {
    static let contexts: [String: String] = [
        "swainLeutholtz1997HRR": String(localized: "Heart-rate reserve (%HRR) estimates relative effort, which sets the moderate and vigorous bands. Guideline credit is separate from actual minutes and does not credit below-moderate work."),
        "piercy2018PhysicalActivityGuidelines": String(localized: "Guidelines: 150 moderate or 75 vigorous minutes per week; one vigorous minute counts as two moderate minutes."),
        "acsmGarber2011AerobicGuidelines": String(localized: "ACSM intensity classification by percent of heart-rate reserve or maximum heart rate."),
        "mezzani2013AerobicIntensity": String(localized: "Consensus on expressing aerobic exercise intensity relative to heart-rate reserve and peak capacity."),
        "tanakaMaxHR2001": String(localized: "Age-based estimate of maximum heart rate used when no measured maximum is available."),
    ]
}
