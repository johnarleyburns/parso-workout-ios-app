import SwiftUI
import CadenceCore
import CadenceFeatures

struct ProgressQuestionSummaryView<DetailContent: View>: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case strength, tests, workouts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .strength: return "Strength"
            case .tests: return "Tests"
            case .workouts: return "Workouts"
            }
        }
    }

    @Binding var selection: ProgressQuestionSelection
    let sessions: [WorkoutSession]
    @ViewBuilder let detailContent: (ProgressQuestion) -> DetailContent
    @State private var mode: Mode = .strength

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Progress", selection: $mode) {
                ForEach(Mode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            .accessibilityIdentifier("progress.question")
            focusedQuestion
        }
        .onAppear { mode = mode(for: selection.selected) }
        .onChange(of: mode) { _, next in
            withAnimation(.easeInOut(duration: 0.15)) {
                selection.select(question(for: next))
            }
        }
    }

    private func mode(for question: ProgressQuestion) -> Mode {
        switch question {
        case .tests: return .tests
        case .workoutHistory: return .workouts
        default: return .strength
        }
    }

    private func question(for mode: Mode) -> ProgressQuestion {
        switch mode {
        case .strength: return .strengthOverTime
        case .tests: return .tests
        case .workouts: return .workoutHistory
        }
    }

    @ViewBuilder
    private var focusedQuestion: some View {
        switch selection.selected {
        case .consistency:
            ConsistencyHeatmapView(sessions: sessions)
        case .strengthOverTime, .tests, .personalRecords, .intensity, .effort:
            detailContent(selection.selected)
        case .workoutHistory:
            EmptyView()
        }
    }
}
