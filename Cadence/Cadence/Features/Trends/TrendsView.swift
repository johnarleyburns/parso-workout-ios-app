import SwiftUI
import SwiftData
import Charts
import CadenceCore

/// Analysis hub (FR-5): activity trend, cardio, recent PRs, per-exercise trends,
/// and a consistency heatmap. The phone is the review/progress surface (FR-9.3).
struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var sessions: [WorkoutSession]
    @State private var trend: [DayActivity] = []

    private var trainedExercises: [Exercise] {
        exercises.filter { !($0.sets ?? []).isEmpty }
    }

    private var recentPRs: [WorkoutRepository.RecentPR] {
        (try? WorkoutRepository.recentPRs(context, rule: settings.prRule, formula: settings.formula)) ?? []
    }

    var body: some View {
        List {
            Section {
                Chart(trend) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps))
                        .foregroundStyle(.green.gradient)
                    RuleMark(y: .value("Goal", settings.stepGoal))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.secondary)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .frame(height: 150)
                .accessibilityIdentifier("today.trendChart")
                .accessibilityLabel("Seven day step trend")

                NavigationLink(value: HomeRoute.cardio) {
                    Label("Cardio history", systemImage: "figure.run")
                }
                .accessibilityIdentifier("stats.cardio")
            } header: {
                Text("Activity").textCase(nil)
            }

            if sessions.isEmpty {
                    ContentUnavailableView("No workouts yet",
                                           systemImage: "chart.xyaxis.line",
                                           description: Text("Log some workouts to see trends and PRs."))
                }

                if !recentPRs.isEmpty {
                    Section {
                        ForEach(recentPRs.prefix(8)) { pr in
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading) {
                                    Text(pr.exerciseName)
                                    Text(pr.achievedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Format.weight(pr.value, unit: settings.unit))
                                    .monospacedDigit().fontWeight(.semibold)
                            }
                            .accessibilityIdentifier("recentPR.\(pr.exerciseName)")
                        }
                    } header: {
                        Text("Personal Records").textCase(nil)
                    }
                    .accessibilityIdentifier("trends.recentPRs")
                }

                if !sessions.isEmpty {
                    Section {
                        ConsistencyHeatmap(trainingDays: (try? WorkoutRepository.trainingDays(context)) ?? [])
                            .padding(.vertical, 4)
                    } header: {
                        Text("Consistency").textCase(nil)
                    }
                }

                if !trainedExercises.isEmpty {
                    Section {
                        ForEach(trainedExercises) { ex in
                            NavigationLink {
                                ExerciseTrendView(exercise: ex)
                            } label: {
                                HStack {
                                    Text(ex.name)
                                    Spacer()
                                    Text("\((ex.sets ?? []).count) sets")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityIdentifier("trends.exercise.\(ex.name)")
                        }
                    } header: {
                        Text("Exercises").textCase(nil)
                    }
                }
            }
        .navigationTitle("Trends")
        .task { trend = await model.health.activityTrend(days: 7) }
    }
}
