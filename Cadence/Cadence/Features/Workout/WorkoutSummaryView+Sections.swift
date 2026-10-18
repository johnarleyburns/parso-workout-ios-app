import SwiftUI
import Charts
import MapKit
import CadenceCore
import CadenceFeatures

/// Warm-up/cool-down, interval, heart-rate and route sections of `WorkoutSummaryView`.
extension WorkoutSummaryView {
    // MARK: Strength warm-up / cool-down (feedback batch 6)

    /// Actual warm-up / cool-down time consumed for a strength session — e.g.
    /// skipping a 10:00 cool-down at 3:00 shows 3:00.
    var warmCoolSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Warm-up & Cool-down").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                if data.warmupSec > 0 {
                    intervalRow(String(localized: "Warm-up"), Format.duration(data.warmupSec), id: "summary.strength.warmup")
                }
                if data.cooldownSec > 0 {
                    intervalRow(String(localized: "Cool-down"), Format.duration(data.cooldownSec), id: "summary.strength.cooldown")
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
    func intervalSection(_ s: IntervalSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Intervals").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                intervalRow(String(localized: "Protocol"), s.protocolName, id: "summary.interval.protocol")
                intervalRow(String(localized: "Rounds"),
                            "completed \(s.completedRounds)/\(s.rounds)",
                            id: "summary.interval.rounds")
                intervalRow(String(localized: "Work / Rest"),
                            "\(Format.duration(s.workSeconds)) / \(Format.duration(s.restSeconds))",
                            id: "summary.interval.workRest")
                if s.warmupSeconds > 0 {
                    intervalRow(String(localized: "Warm-up"), Format.duration(s.warmupSeconds),
                                id: "summary.interval.warmup")
                }
                if s.cooldownSeconds > 0 {
                    intervalRow(String(localized: "Cool-down"), Format.duration(s.cooldownSeconds),
                                id: "summary.interval.cooldown")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    func intervalRow(_ title: String, _ value: String, id: String) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier(id)
        }
    }

    // MARK: Cardio HR chart + route

    var hrChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Heart Rate").font(.headline)
            HRZoneChart(samples: data.hr.map { ($0.t, $0.bpm) },
                        maxHR: CardioIntensityProfile.resolved(
                            userEnteredMaximumHR: settings.cardioMaximumHROverride,
                            age: settings.userAge).maximumHR ?? CardioMath.defaultMaxHR(age: settings.userAge))
            .frame(height: 180)
            .accessibilityIdentifier("summary.hrChart")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heart rate over time")
            .accessibilityValue(hrChartAXSummary(data.hr.map(\.bpm)))
        }
    }

    /// Spoken summary of an HR series for VoiceOver (the chart itself is opaque).
    func hrChartAXSummary(_ bpms: [Double]) -> String {
        WorkoutSummaryPresenter.hrChartAXSummary(bpms)
    }

    var routeMap: some View {
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

    var routeRegion: MKCoordinateRegion {
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
