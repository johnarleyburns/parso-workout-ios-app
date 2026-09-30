import SwiftUI
import CadenceCore
import CadenceFeatures

struct HomeTodayHeroCard: View {
    let title: String
    let tag: String
    let estimatedMinutes: Int?
    let exercises: [(name: String, detail: String)]
    let reason: String?
    let rationale: SuggestedWorkoutRationale?
    let citationIDs: [String]
    let summary: DaySummary?
    let unit: MeasurementUnitPreference
    let onStart: () -> Void
    let onEdit: () -> Void
    let onChooseAnother: () -> Void
    let onViewSummary: () -> Void
    let onAddSomething: () -> Void
    @State private var rationalePresented = false
    @State private var durationInfoPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(tag, systemImage: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CadenceTheme.accent)
                Spacer()
                if let estimatedMinutes {
                    Button {
                        durationInfoPresented = true
                    } label: {
                        Text("≈ \(estimatedMinutes) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Estimated duration, \(estimatedMinutes) minutes")
                    .sheet(isPresented: $durationInfoPresented) {
                        Text("Duration estimate")
                            .font(.headline)
                            .padding(.top)
                        Text("Based on the planned sets and your recent pace. Actual time varies with rest and transitions.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .presentationDetents([.height(180)])
                    }
                }
            }

            if let summary, tag == "Done for today" {
                doneSummary(summary)
            } else {
                Text(title)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)

                if !exercises.isEmpty {
                    exerciseRows
                }

                if let reason {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !citationIDs.isEmpty {
                            CoachSourcesLink(
                                citationIds: citationIDs,
                                contexts: Dictionary(uniqueKeysWithValues: citationIDs.map {
                                    ($0, "Why this workout")
                                }),
                                identifier: "home.hero.science")
                        }
                    }
                }

                if let rationale {
                    Button {
                        rationalePresented = true
                    } label: {
                        Label("Why this workout", systemImage: "questionmark.circle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(CadenceTheme.link)
                    .accessibilityIdentifier("home.hero.whyWorkout")
                    .sheet(isPresented: $rationalePresented) {
                        RecommendationRationaleSheet(rationale: rationale)
                    }
                }

                if tag == "Recovery day" {
                    Button("Easy options", action: onChooseAnother)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button("Train anyway", action: onStart)
                        .buttonStyle(.plain)
                        .foregroundStyle(CadenceTheme.link)
                        .frame(maxWidth: .infinity)
                } else {
                    Button(action: onStart) {
                        Label(tag == "In progress" ? "Resume" : "Start Workout",
                              systemImage: tag == "In progress" ? "play.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CadenceTheme.accent)
                    .controlSize(.large)
                    .accessibilityIdentifier("home.hero.start")

                    HStack(spacing: 18) {
                        Button("Edit plan", action: onEdit)
                        Button("Choose another", action: onChooseAnother)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.plain)
                    .foregroundStyle(CadenceTheme.link)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceCard(.hero)
        .accessibilityIdentifier("home.hero")
    }

    private var exerciseRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(exercises.prefix(5).enumerated()), id: \.offset) { _, exercise in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(exercise.name)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(exercise.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) { Divider().opacity(0.35) }
            }
        }
    }

    private func doneSummary(_ summary: DaySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(summary.title)
                .font(.title3.weight(.bold))
            HStack(spacing: 12) {
                fact("\(summary.setCount)", "sets")
                fact(WorkoutMath.tonnageLabel(volumeKg: summary.volumeKg, unit: unit), "volume")
                if let duration = summary.durationMinutes {
                    fact("\(duration) min", "duration")
                }
            }
            if let bestPR = summary.bestPR {
                Label(bestPR, systemImage: "trophy.fill")
                    .foregroundStyle(CadenceTheme.achievement)
                    .font(.subheadline.weight(.semibold))
            }
            HStack(spacing: 18) {
                Button("View summary", action: onViewSummary)
                    .buttonStyle(.bordered)
                Button("Add something", action: onAddSomething)
                    .buttonStyle(.plain)
                    .foregroundStyle(CadenceTheme.link)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Done for today. \(summary.setCount) sets, \(WorkoutMath.tonnageLabel(volumeKg: summary.volumeKg, unit: unit)).")
        .accessibilityIdentifier("home.hero.done")
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
