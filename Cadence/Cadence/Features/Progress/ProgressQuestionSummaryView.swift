import SwiftUI
import Charts
import SwiftData
import CadenceCore
import CadenceFeatures

struct ProgressQuestionSummaryView<DetailContent: View>: View {
    @Binding var selection: ProgressQuestionSelection
    let facts: TrainingFacts
    let sessions: [WorkoutSession]
    let cardioTotals: [ProgressCardioWeekTotal]
    @ViewBuilder let detailContent: (ProgressQuestion) -> DetailContent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            questionPicker
            focusedQuestion
        }
    }

    private var questionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ProgressQuestion.alphabetical) { question in
                    let isSelected = selection.selected == question
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selection.select(question)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(question.displayName)
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.small)
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                                    in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("progress.question.\(question.rawValue)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("progress.question")
    }

    @ViewBuilder
    private var focusedQuestion: some View {
        switch selection.selected {
        case .consistency:
            consistencyCard
        case .exerciseProgression:
            detailContent(.exerciseProgression)
        case .muscleVolume:
            muscleVolumeCard
        case .cardioChange:
            cardioChangeCard
        case .strengthOverTime, .tests, .trends, .intensity, .effort, .frequency:
            detailContent(selection.selected)
        }
    }

    private var consistencyCard: some View {
        summaryCard(title: "Consistency", subtitle: "Your recent training rhythm", tint: .blue) {
            ConsistencyHeatmapView(sessions: sessions)
        }
        .accessibilityIdentifier("progress.focus.consistency")
    }

    private var muscleVolumeCard: some View {
        let groups = facts.weeklySetsByGroup
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key.displayName.localizedStandardCompare(rhs.key.displayName) == .orderedAscending
                }
                return lhs.value > rhs.value
            }
            .prefix(5)
        return VStack(alignment: .leading, spacing: 8) {
            summaryCard(title: "Muscle-volume balance", subtitle: "Top trained muscle groups this week", tint: .green) {
                if groups.isEmpty {
                    emptyNote("Log strength sets and weekly muscle balance will appear here.")
                } else {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Text(item.key.displayName).font(.caption)
                            Spacer()
                            Text("\(WeeklySetProgress.formattedSets(item.value)) sets")
                                .font(.caption.weight(.semibold)).monospacedDigit()
                        }
                        ProgressView(value: min(item.value / 12, 1)).tint(.green)
                    }
                }
            }
            CoachSourcesLink(citationIds: CitationRegistry.strengthVolumePool.citationIds,
                             identifier: "progress.focus.volume.sources")
        }
        .accessibilityIdentifier("progress.focus.muscleVolume")
    }

    private var cardioChangeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryCard(title: "Cardio change", subtitle: "Logged minutes by week · last 4 weeks",
                        citation: CitationRegistry.piercy2018PhysicalActivityGuidelines, tint: .teal) {
                if cardioTotals.allSatisfy({ $0.minutes == 0 }) {
                    emptyNote("Complete or log a cardio workout to see your weekly trend.")
                } else {
                    Chart {
                        ForEach(Array(cardioTotals.enumerated()), id: \.offset) { _, item in
                            BarMark(x: .value("Week", item.start),
                                    y: .value("Minutes", item.minutes))
                        }
                    }
                    .frame(height: 140)
                    HStack {
                        Text("This week: \(Int((cardioTotals.last?.minutes ?? 0).rounded())) min")
                        Spacer()
                        Text("Previous: \(Int((cardioTotals.dropLast().last?.minutes ?? 0).rounded())) min")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("progress.focus.cardioChange")
    }

    @ViewBuilder
    private func summaryCard<Content: View>(title: String, subtitle: String? = nil,
                                            citation: Citation? = nil, tint: Color? = nil,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.secondary).padding(.bottom, 10)
            } else {
                Color.clear.frame(height: 10)
            }
            content()
            if let citation {
                Divider().padding(.top, 12).padding(.bottom, 8)
                CitationLink(citation: citation, compact: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: tint)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text).font(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
