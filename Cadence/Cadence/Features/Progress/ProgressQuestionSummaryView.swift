import SwiftUI
import CadenceCore
import CadenceFeatures

struct ProgressQuestionSummaryView<DetailContent: View>: View {
    @Binding var selection: ProgressQuestionSelection
    let sessions: [WorkoutSession]
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
            // ConsistencyHeatmapView already owns its glass card. Wrapping it
            // in another summary card produced the duplicated section seen in
            // field testing.
            ConsistencyHeatmapView(sessions: sessions)
        case .strengthOverTime, .tests, .personalRecords, .intensity, .effort:
            detailContent(selection.selected)
        case .workoutHistory:
            EmptyView()
        }
    }

}
