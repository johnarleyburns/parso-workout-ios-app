import SwiftUI
import SwiftData
import CadenceCore

/// Analysis hub (FR-5): recent PRs, per-exercise trends, and a consistency
/// heatmap. The phone is the review/progress surface (FR-9.3).
struct TrendsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var sessions: [WorkoutSession]

    private var trainedExercises: [Exercise] {
        exercises.filter { !($0.sets ?? []).isEmpty }
    }

    private var recentPRs: [WorkoutRepository.RecentPR] {
        (try? WorkoutRepository.recentPRs(context, rule: settings.prRule, formula: settings.formula)) ?? []
    }

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView("No data yet",
                                           systemImage: "chart.xyaxis.line",
                                           description: Text("Log some workouts to see trends and PRs."))
                }

                if !recentPRs.isEmpty {
                    Section("Personal Records") {
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
                    }
                    .accessibilityIdentifier("trends.recentPRs")
                }

                if !sessions.isEmpty {
                    Section("Consistency") {
                        ConsistencyHeatmap(trainingDays: (try? WorkoutRepository.trainingDays(context)) ?? [])
                            .padding(.vertical, 4)
                    }
                }

                if !trainedExercises.isEmpty {
                    Section("Exercises") {
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
                    }
                }
            }
            .navigationTitle("Trends")
        }
    }
}
