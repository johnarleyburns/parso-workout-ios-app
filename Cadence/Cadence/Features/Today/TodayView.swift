import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// Home dashboard (FR-3): steps front and center with a goal ring, a 7-day
/// trend, and activity tiles. Reads from HealthKit (fake in UI-test mode).
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var today: DayActivity?
    @State private var trend: [DayActivity] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                StepRing(steps: today?.steps ?? 0, goal: settings.stepGoal)
                    .padding(.top, 8)

                activityTiles

                trendChart

                recentWorkouts
            }
            .padding()
        }
        .navigationTitle("Today")
        .task { await load() }
        .refreshable { await load() }
    }

    private var activityTiles: some View {
        HStack(spacing: 12) {
            tile("Flights", "\(today?.flightsClimbed ?? 0)", "figure.stairs", id: "today.flights")
            tile("Distance", Format.distance(today?.distanceMeters ?? 0), "figure.walk", id: "today.distance")
            tile("Energy", "\(Int(today?.activeEnergyKcal ?? 0)) kcal", "flame.fill", id: "today.energy")
        }
    }

    private func tile(_ title: String, _ value: String, _ symbol: String, id: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(value).font(.headline).monospacedDigit()
                .accessibilityIdentifier(id)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 7 Days").font(.headline)
            Chart(trend) { day in
                BarMark(
                    x: .value("Day", day.date, unit: .day),
                    y: .value("Steps", day.steps))
                .foregroundStyle(.green.gradient)
                RuleMark(y: .value("Goal", settings.stepGoal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(.secondary)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 160)
            .accessibilityIdentifier("today.trendChart")
            .accessibilityLabel("Seven day step trend")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var recentWorkouts: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Workouts").font(.headline)
                ForEach(sessions.prefix(3)) { s in
                    HStack {
                        Image(systemName: "dumbbell.fill").foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(s.title.isEmpty ? "Workout" : s.title)
                            Text(s.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(s.orderedSets.count) sets").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("today.recentWorkouts")
        }
    }

    private func load() async {
        today = await model.health.todayActivity()
        trend = await model.health.activityTrend(days: 7)
    }
}
