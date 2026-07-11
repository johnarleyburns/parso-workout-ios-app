import SwiftUI
import CadenceCore

/// The coach's "run this fitness test" suggestion (issue 11) — a distinct,
/// lower-priority card surfaced at most once a week. Shows the test name, why
/// now, tappable citations, and three actions: Start test, Pick a different test
/// (cycles to the next-priority kind), and Not right now (snoozes ~1 week).
struct CoachTestRecommendationCard: View {
    let recommendation: TestRecommendation
    let onStart: (AssessmentKind) -> Void
    let onPickDifferent: () -> Void
    let onSnooze: (AssessmentKind) -> Void

    private var citations: [Citation] {
        recommendation.citationIds.compactMap { CitationRegistry.citation(forId: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: recommendation.kind.symbol)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach suggestion")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(recommendation.kind.displayName)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coach.test.title")
                }
            }

            Text(recommendation.whyNow)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(citations, id: \.id) { citation in
                CitationLink(citation: citation, compact: true)
            }

            HStack(spacing: 10) {
                Button {
                    onStart(recommendation.kind)
                } label: {
                    Label("Start test", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .cadenceGlassButton(prominent: true, tint: .blue)
                .accessibilityIdentifier("coach.test.start")
            }

            HStack(spacing: 16) {
                Button("Pick a different test", action: onPickDifferent)
                    .font(.caption.weight(.medium))
                    .accessibilityIdentifier("coach.test.pickDifferent")
                Spacer(minLength: 4)
                Button("Not right now") { onSnooze(recommendation.kind) }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("coach.test.snooze")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 16, style: .continuous), tint: .blue)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.test.card")
    }
}
