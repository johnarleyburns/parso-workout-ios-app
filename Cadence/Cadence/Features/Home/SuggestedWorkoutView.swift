import SwiftUI
import CadenceCore
import CadenceFeatures
import os

struct SuggestedWorkoutRequest: Identifiable {
    let id = UUID()
    let input: SuggestedWorkoutInput
    let unit: MeasurementUnitPreference
    let warmupMinutes: Int
    let cooldownMinutes: Int
    let failureMessage: String?

    init(input: SuggestedWorkoutInput, unit: MeasurementUnitPreference, warmupMinutes: Int,
         cooldownMinutes: Int, failureMessage: String? = nil) {
        self.input = input
        self.unit = unit
        self.warmupMinutes = warmupMinutes
        self.cooldownMinutes = cooldownMinutes
        self.failureMessage = failureMessage
    }
}

enum SuggestedWorkoutSignposts {
    private static let log = OSLog(subsystem: "guru.parso.cladiron", category: "SuggestedWorkout")

    static func exerciseFetchAndMap<T>(_ operation: () throws -> T) rethrows -> T {
        let identifier = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "exerciseFetchAndMap", signpostID: identifier)
        defer { os_signpost(.end, log: log, name: "exerciseFetchAndMap", signpostID: identifier) }
        return try operation()
    }

    static func recordGeneration(_ bundle: SuggestedWorkoutBundle) {
        os_signpost(.event, log: log, name: "vectorIndexBuild", "%.3f ms",
                    Double(bundle.diagnostics.vectorIndexBuildDuration.components.attoseconds) / 1e15
                    + Double(bundle.diagnostics.vectorIndexBuildDuration.components.seconds) * 1e3)
        os_signpost(.event, log: log, name: "allStylesGeneration", "%.3f ms",
                    Double(bundle.diagnostics.allStylesGenerationDuration.components.attoseconds) / 1e15
                    + Double(bundle.diagnostics.allStylesGenerationDuration.components.seconds) * 1e3)
    }
}

struct SuggestedWorkoutView: View {
    let request: SuggestedWorkoutRequest
    let onStart: (EditablePlan) -> Void
    let onRetry: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var state: SuggestedWorkoutState = .idle
    @State private var aboutPresented = false

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle, .calculating:
                    ProgressView(SuggestedWorkoutPresenter.calculatingTitle)
                        .accessibilityIdentifier("suggestedWorkout.calculating")
                case .ready(let bundle):
                    choices(bundle)
                case .failed(let message):
                    ContentUnavailableView("Couldn’t calculate suggested workouts",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                    Button("Retry", action: onRetry)
                        .accessibilityIdentifier("suggestedWorkout.retry")
                }
            }
            .navigationTitle(SuggestedWorkoutPresenter.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("suggestedWorkout.close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { aboutPresented = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel(SuggestedWorkoutPresenter.aboutAccessibilityLabel)
                    .accessibilityIdentifier("suggestedWorkout.about")
                }
            }
            .sheet(isPresented: $aboutPresented) {
                NavigationStack { AboutSuggestedWorkoutsView() }
            }
        }
        .task { await calculate() }
    }

    private func calculate() async {
        if let failure = request.failureMessage {
            state = .failed(message: failure)
            return
        }
        state = .calculating
        await Task.yield()
        guard !Task.isCancelled else { return }
        // Generation uses the immutable DB++ catalog and can take several
        // seconds on device. Keep that CPU work off the main actor so the sheet
        // can render its calculating state and remain interactive.
        let generation = Task.detached(priority: .userInitiated) { () -> SuggestedWorkoutBundle? in
            guard !Task.isCancelled else { return nil }
            let result = SuggestedWorkoutGenerator.generate(input: request.input)
            guard !Task.isCancelled else { return nil }
            return result
        }
        let bundle = await generation.value
        guard !Task.isCancelled else { return }
        guard let bundle else {
            state = .failed(message: "The suggestion engine did not return a plan. Retry to try again.")
            return
        }
        guard bundle.options.contains(where: \.isLaunchable) else {
            state = .failed(message: "No usable exercise data is available yet. Retry to refresh the exercise catalog.")
            return
        }
        SuggestedWorkoutSignposts.recordGeneration(bundle)
        state = .ready(bundle)
    }

    private func choices(_ bundle: SuggestedWorkoutBundle) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(SuggestedWorkoutPresenter.chooserIntro)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let notice = SuggestedWorkoutPresenter.historyNotice(for: bundle.historyQuality) {
                    Label(notice, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("suggestedWorkout.historyNotice")
                }
                ForEach(SuggestedWorkoutPresenter.choices(for: bundle)) { choice in
                    choiceButton(choice)
                }
                citations
            }
            .padding()
        }
        .accessibilityIdentifier("suggestedWorkout.ready")
    }

    private func choiceButton(_ choice: SuggestedWorkoutChoice) -> some View {
        let style = choice.option.style
        return NavigationLink {
            WorkoutPlanEditor(
                plan: SuggestedWorkoutPresenter.editablePlan(
                    for: choice.option,
                    unit: request.unit,
                    warmupMinutes: request.warmupMinutes,
                    cooldownMinutes: request.cooldownMinutes),
                startInEditMode: true,
                onExcludeAndRegenerate: { candidateID in
                    await regeneratedPlan(excludingCandidateID: candidateID, style: style)
                },
                onStart: onStart)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(choice.title).font(.headline)
                Text(choice.styleDescription).font(.caption).foregroundStyle(.secondary)
                Text(choice.subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
        }
        .buttonStyle(.plain)
        .disabled(choice.isDisabled)
        .accessibilityIdentifier("suggestedWorkout.style.\(choice.option.style.rawValue)")
        .accessibilityLabel(choice.title)
        .accessibilityValue("\(choice.styleDescription) \(choice.subtitle)")
    }

    /// Reruns the full generator with `candidateID`'s exercise removed from
    /// the pool, for the same style the user was already reviewing, and
    /// materializes a fresh `EditablePlan` from the result — a real
    /// from-scratch regeneration, not a patch of the plan already on
    /// screen. `nil` when the style has nothing left to suggest at all
    /// (e.g. excluding the only remaining candidate for every gap); the
    /// caller still keeps the exclusion (it already saved) and simply
    /// cannot refresh this particular plan.
    private func regeneratedPlan(
        excludingCandidateID candidateID: String, style: SuggestedWorkoutStyle
    ) async -> EditablePlan? {
        let newInput = request.input.excluding(candidateID: candidateID)
        // Same reasoning as the initial calculate(): DB++ generation is real
        // CPU work and must stay off the main actor so this sheet's spinner
        // keeps rendering while it runs.
        let bundle = await Task.detached(priority: .userInitiated) {
            SuggestedWorkoutGenerator.generate(input: newInput)
        }.value
        let option = bundle.option(style)
        guard option.isLaunchable else { return nil }
        return SuggestedWorkoutPresenter.editablePlan(
            for: option, unit: request.unit, warmupMinutes: request.warmupMinutes,
            cooldownMinutes: request.cooldownMinutes)
    }

    @ViewBuilder
    private var citations: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scientific backing").font(.headline)
            ForEach(SuggestedWorkoutPresenter.citationIDs, id: \.self) { id in
                if let citation = CitationRegistry.citation(forId: id) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(citation.title).font(.caption)
                        CitationLink(citation: citation, identifier: "suggestedWorkout.science.\(id)")
                    }
                }
            }
        }
        .accessibilityIdentifier("suggestedWorkout.science")
    }
}
