import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Progress → Observations. Builds its feed from a freshly computed Coach
/// snapshot (same `HomeCoachModel` pipeline and `HomeDashboardPresenter`
/// ordering Home used), so it never reads Home's view state. It owns no
/// workout-history list or all-history query.
struct ProgressObservationsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.cadenceModelContainer) private var container
    @AppStorage("home.dismissedObservationKeys.v1") private var dismissedRaw = ""
    @State private var snapshot: CoachSnapshot?
    @State private var expanded = false

    private var feed: ProgressObservationFeed {
        guard let snapshot else { return .empty }
        return ProgressObservationFeed.make(
            snapshot: snapshot, schedule: settings.coachSchedulePreferences,
            goal: settings.trainingGoal, experience: settings.experienceLevel,
            userAge: settings.userAge,
            dismissedKeys: ProgressObservationFeed.dismissedKeys(raw: dismissedRaw))
    }

    var body: some View {
        ScrollView {
            ObservationsSection(
                suggestions: feed.suggestions, expanded: $expanded,
                onClearAll: {
                    var dismissed = ProgressObservationFeed.dismissedKeys(raw: dismissedRaw)
                    dismissed.formUnion(feed.suggestions.map(\.sourceClaimKey))
                    dismissedRaw = dismissed.sorted().joined(separator: "|")
                    expanded = false
                })
            .padding(.horizontal)
            .padding(.bottom, CadenceTabBarClearance.scrollContentBottom)
        }
        .task { await load() }
    }

    private func load() async {
        guard let container else { return }
        let passive = await model.health.passiveReadinessSamples(days: 60)
        guard !Task.isCancelled else { return }
        let policy: PlanningConstraintPolicy = settings.isPlanOverrideActive() ? .meetDeficits : .safe
        snapshot = await HomeCoachModel.snapshotAsync(
            container: container, goal: settings.trainingGoal, experience: settings.experienceLevel,
            formula: settings.formula, schedule: settings.coachSchedulePreferences,
            profile: settings.coachPreferenceProfile, passiveSamples: passive,
            userAge: settings.userAge, cardioMaximumHROverride: settings.cardioMaximumHROverride,
            constraintPolicy: policy)
    }
}

/// Surface-neutral cited Observations card rendered from `ObservationsPresenter`.
struct ObservationsSection: View {
    let suggestions: [HomeSuggestion]
    @Binding var expanded: Bool
    let onClearAll: () -> Void

    private static let illustrationSize = MuscleFocusThumbnail.size
    private static let illustrationInset: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardHeadingSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .padding(LayoutMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .purple)
        .overlay(alignment: .topTrailing) {
            MuscleFocusThumbnail(count: suggestions.count)
                .padding(Self.illustrationInset)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("progress.observations.card")
    }

    private var blocks: [ObservationsPresenter.Block] {
        ObservationsPresenter.blocks(suggestions: suggestions, expanded: expanded)
    }

    @ViewBuilder
    private func blockView(_ block: ObservationsPresenter.Block) -> some View {
        switch block {
        case .heading:
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Observations").font(.headline)
                    Spacer(minLength: 8)
                    if !suggestions.isEmpty {
                        Button("Clear all", action: onClearAll)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CadenceTheme.link)
                            .accessibilityIdentifier("progress.observations.clearAll")
                    }
                }
                .padding(.trailing, Self.illustrationSize + Self.illustrationInset)
                if ObservationsPresenter.isEmpty(suggestions: suggestions) {
                    Text("No new suggestions right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case let .suggestion(suggestion):
            suggestionRow(suggestion)
        case let .showMore(expandedNow):
            Button {
                withAnimation { expanded.toggle() }
            } label: {
                HStack {
                    Text(expandedNow ? "Show less" : "Show more...")
                    Spacer()
                    Image(systemName: expandedNow ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
    }

    private func suggestionRow(_ suggestion: HomeSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(tint(suggestion)).frame(width: 8, height: 8)
                Text(suggestion.title).font(.headline)
            }
            Text(suggestion.message).font(.subheadline)
            if let citationID = suggestion.citationID,
               let citation = CitationRegistry.citation(forId: citationID) {
                CitationLink(citation: citation, compact: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func tint(_ suggestion: HomeSuggestion) -> Color {
        switch ObservationsPresenter.toneRole(suggestion.tone) {
        case .positive: return .green
        case .warning: return .yellow
        case .neutral: return .white
        }
    }
}
