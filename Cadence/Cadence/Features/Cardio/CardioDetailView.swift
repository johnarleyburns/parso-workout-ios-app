import SwiftUI
import Charts
import MapKit
import CadenceCore
import SwiftData

/// Cardio workout detail (FR-5.3): summary, HR overlay, and route map.
struct CardioDetailView: View {
    @Bindable var workout: CardioWorkout
    @Environment(\.modelContext) private var context
    @State private var datePickerPresented = false
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
                LabeledContent("Source", value: workout.sourceValue.rawValue.capitalized)
            }

            let hr = workout.orderedHRSamples
            if !hr.isEmpty {
                Section("Heart Rate") {
                    Chart(hr) { sample in
                        LineMark(x: .value("Time", sample.t / 60),
                                 y: .value("BPM", sample.bpm))
                            .foregroundStyle(.red)
                    }
                    .chartXAxisLabel("min")
                    .frame(height: 180)
                    .accessibilityIdentifier("cardioDetail.hrChart")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Heart rate over time")
                    .accessibilityValue(hrChartAXSummary(hr.map(\.bpm)))
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
                Button { datePickerPresented = true } label: {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Edit workout date")
                .accessibilityIdentifier("cardioDetail.editDate")
            }
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
        guard !valid.isEmpty else { return "No heart rate samples" }
        let lo = Int(valid.min() ?? 0)
        let hi = Int(valid.max() ?? 0)
        let avg = Int(valid.reduce(0, +) / Double(valid.count))
        return "Average \(avg), range \(lo) to \(hi) beats per minute, \(valid.count) samples"
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
