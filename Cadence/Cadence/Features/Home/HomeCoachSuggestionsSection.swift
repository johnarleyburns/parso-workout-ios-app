import SwiftUI
import CadenceCore
import CadenceFeatures

/// Home's Coach's Suggestions card plus the full-width action beneath it.
///
/// Field test 2026-08-18 #8/#9/#11: the coach artwork floats over the card's
/// top-right corner instead of taking layout space, the suggested workout moved
/// to the bottom of the card, and `Do Coach's Workout` is a sibling of the card
/// rather than a child so it matches Home's `Start Workout` exactly.
/// The render order itself lives in `HomeCoachSectionPresenter`.
struct HomeCoachSuggestionsSection: View {
    let suggestions: [HomeSuggestion]
    let recommendation: CoachSession?
    let illustration: HomeCoachIllustration
    @Binding var expanded: Bool
    let onStartRecommendation: () -> Void

    /// The heading reserves the artwork's width so it cannot slide under the
    /// floating illustration at large Dynamic Type.
    private static let illustrationSize = HomeCoachIllustrationView.compactSize
    private static let illustrationInset: CGFloat = 12

    var body: some View {
        VStack(spacing: LayoutMetrics.actionButtonSpacing) {
            card
            if HomeCoachSectionPresenter.showsPrimaryAction(recommendation: recommendation) {
                CadenceActionButton(title: "Do Coach's Workout",
                                    systemImage: "play.fill",
                                    action: onStartRecommendation)
                    .accessibilityIdentifier("home.coachRecommendation.start")
            }
        }
        // `children: .contain` must precede the identifier or the container
        // swallows the inner ids the smoke test resolves.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardHeadingSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .padding(LayoutMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .purple)
        .overlay(alignment: .topTrailing) {
            HomeCoachIllustrationView(illustration: illustration, compact: true)
                .padding(Self.illustrationInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.coachSuggestions.card")
    }

    private var blocks: [HomeCoachSectionPresenter.Block] {
        HomeCoachSectionPresenter.blocks(suggestions: suggestions,
                                         recommendation: recommendation,
                                         expanded: expanded)
    }

    @ViewBuilder
    private func blockView(_ block: HomeCoachSectionPresenter.Block) -> some View {
        switch block {
        case .heading:
            VStack(alignment: .leading, spacing: 6) {
                Text("Coach’s Suggestions")
                    .font(.headline)
                    .padding(.trailing, Self.illustrationSize + Self.illustrationInset)
                if suggestions.isEmpty {
                    Text("No new suggestions right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        case let .suggestion(suggestion):
            suggestionRow(suggestion)
        case let .showMore(expandedNow):
            showMoreButton(expandedNow)
        case .divider:
            Divider()
        case let .suggestedWorkout(title, why, exercises):
            HomeCoachRecommendationCard(
                title: title,
                why: why,
                exercises: exercises,
                additionalCount: recommendation.map(HomeCoachSectionPresenter.additionalExerciseCount) ?? 0,
                citationIds: recommendation?.citationIds ?? [],
                durationMinutes: recommendation?.durationMinutes)
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
                    .accessibilityIdentifier("home.suggestion.\(suggestion.id).science")
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func showMoreButton(_ expandedNow: Bool) -> some View {
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
        .accessibilityIdentifier(expandedNow ? "home.suggestions.showLess" : "home.suggestions.showMore")
    }

    private func tint(_ suggestion: HomeSuggestion) -> Color {
        switch HomeCoachSectionPresenter.toneRole(suggestion.tone) {
        case .positive: return .green
        case .warning: return .yellow
        case .neutral: return .white
        }
    }
}
