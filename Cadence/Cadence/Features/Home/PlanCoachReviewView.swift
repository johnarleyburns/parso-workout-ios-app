import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Compact self-coach review for an authored unified plan. Every surfaced
/// finding and proposal retains its evidence IDs; applying a change is always
/// an explicit user action.
struct PlanCoachReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Assessment.date, order: .reverse) private var assessments: [Assessment]

    @State private var plan: Plan
    let onApply: (Plan) -> Void
    @State private var critique: [UnifiedPlanCoachCritique] = []
    @State private var progression: [UnifiedPlanProgressionProposal] = []
    @State private var autoregulation: [UnifiedPlanAutoregulationProposal] = []
    @State private var insights: [UnifiedPlanCoachInsight] = []
    @State private var substitutions: [UnifiedPlanSubstitution] = []
    @State private var selectedItemID: UUID?
    @State private var errorMessage: String?

    init(plan: Plan, onApply: @escaping (Plan) -> Void) {
        self._plan = State(initialValue: plan)
        self.onApply = onApply
    }

    private var facts: TrainingFacts {
        TrainingFacts.make(
            sessions: sessions,
            assessments: assessments,
            goal: settings.trainingGoal,
            experience: settings.experienceLevel,
            formula: settings.formula)
    }

    private var strengthItems: [CoachItemChoice] {
        plan.weeks.flatMap { week in
            week.days.flatMap { day in
                day.sessions.flatMap { session in
                    session.orderedItems.compactMap { item in
                        guard case let .strength(value) = item else { return nil }
                        return CoachItemChoice(id: value.id,
                                              title: value.exerciseKey.raw.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let rationale = plan.rationale {
                    Section("Why this plan") {
                        Text(rationale.summary)
                        if let version = rationale.knowledgeBaseVersion {
                            Text("Knowledge base \(version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(rationale.decisions) { decision in
                            rationaleRow(decision)
                        }
                    }
                } else {
                    Section("Why this plan") {
                        Text("This plan is self-authored. The coach can review it, but will not silently change it.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Critique") {
                    if critique.isEmpty {
                        Text("No current critique findings.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(critique) { finding in
                            findingRow(finding)
                        }
                    }
                }

                Section("Insights") {
                    if insights.isEmpty {
                        Text("No plan-level insights for the current data.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(insights) { insight in
                            insightRow(insight)
                        }
                    }
                }

                Section("Progress and autoregulation") {
                    if progression.isEmpty && autoregulation.isEmpty {
                        Text("No progress or autoregulation proposal is active. Log completed working sets and readiness to make these surfaces actionable.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(progression) { proposal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Progress: \(proposal.exerciseKey.raw.replacingOccurrences(of: "_", with: " ").capitalized)")
                                .font(.headline)
                            Text(proposal.reason)
                            Text(citationSummary(proposal.citationIDs))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(autoregulation) { proposal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Autoregulation: \(proposal.direction.rawValue.capitalized)")
                                .font(.headline)
                            Text(proposal.detail)
                            Text(citationSummary(proposal.citationIDs))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Substitute") {
                    if strengthItems.isEmpty {
                        Text("Add a strength item to review substitutions.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Exercise", selection: Binding(
                            get: { selectedItemID ?? strengthItems[0].id },
                            set: {
                                selectedItemID = $0
                                loadSubstitutions()
                            })) {
                            ForEach(strengthItems) { item in
                                Text(item.title).tag(item.id)
                            }
                        }
                        if substitutions.isEmpty {
                            Text("No ranked substitute is available for this item.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(substitutions) { substitution in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(substitution.candidateName)
                                            .font(.headline)
                                        Spacer()
                                        Button("Apply") { apply(substitution) }
                                            .buttonStyle(.bordered)
                                    }
                                    Text(substitution.preserves)
                                    if let tradeoff = substitution.tradeoff {
                                        Text(tradeoff)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(citationSummary(substitution.citationIDs))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Coach review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                selectedItemID = selectedItemID ?? strengthItems.first?.id
                refresh()
            }
        }
    }

    private func refresh() {
        do {
            critique = try UnifiedPlanCoachEngine.critique(for: plan, trainingFacts: facts)
            progression = try UnifiedPlanCoachEngine.progress(for: plan, trainingFacts: facts)
            autoregulation = UnifiedPlanCoachEngine.autoregulate(for: plan, trainingFacts: facts)
            insights = UnifiedPlanCoachEngine.insights(for: plan, trainingFacts: facts)
            loadSubstitutions()
            errorMessage = nil
        } catch {
            errorMessage = "Coach review unavailable: \(error.localizedDescription)"
        }
    }

    private func loadSubstitutions() {
        guard let selectedItemID else { substitutions = []; return }
        do {
            substitutions = try UnifiedPlanCoachEngine.substitute(for: plan, itemID: selectedItemID)
            errorMessage = nil
        } catch {
            substitutions = []
            errorMessage = "Substitutions unavailable: \(error.localizedDescription)"
        }
    }

    private func apply(_ substitution: UnifiedPlanSubstitution) {
        do {
            plan = try UnifiedPlanCoachEngine.apply(substitution, to: plan)
            onApply(plan)
            refresh()
        } catch {
            errorMessage = "Could not apply substitution: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func rationaleRow(_ decision: RationaleDecision) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(decision.claim).font(.headline)
            Text(decision.basis)
            Text(citationSummary(decision.citationIDs))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func findingRow(_ finding: UnifiedPlanCoachCritique) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(finding.title).font(.headline)
            Text(finding.detail)
            if let fix = finding.suggestedFix {
                Text("Suggested fix: \(fix)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(citationSummary(finding.citationIDs))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func insightRow(_ insight: UnifiedPlanCoachInsight) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(insight.title).font(.headline)
            Text(insight.message)
            Text(insight.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(citationSummary(insight.citationIDs))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func citationSummary(_ ids: [String]) -> String {
        let titles = ids.compactMap { CitationRegistry.citation(forId: $0)?.shortText }
        return titles.isEmpty ? "No citation available" : "Science: " + titles.joined(separator: " · ")
    }
}

private struct CoachItemChoice: Identifiable {
    let id: UUID
    let title: String
}
