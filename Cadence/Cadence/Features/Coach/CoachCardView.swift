import SwiftUI
import CadenceCore

/// The Coach card — Home's hero (strength-pivot P3). Surfaces the top read-only
/// `Insight` from the engine with an always-available "Why / the science" expander
/// and its citation (decision D3). When more than one insight is available it offers
/// a "See all insights" link. Read-only in P3 (no prescribed "Do this" action yet).
struct CoachCardView: View {
    let insights: [Insight]
    var onSeeAll: () -> Void

    private var top: Insight? { insights.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "figure.mind.and.body")
                Text("COACH").font(.caption.bold()).tracking(1.2)
                Spacer()
                Text("This week").font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)

            if let top {
                InsightContentView(insight: top, headline: true)

                if insights.count > 1 {
                    Button { Haptics.selection(); onSeeAll() } label: {
                        HStack(spacing: 4) {
                            Text("See all insights (\(insights.count))").font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .accessibilityIdentifier("coach.card.seeAll")
                }
            }

            Text("Coaching, not medical advice.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.tint.opacity(0.25), lineWidth: 1))
        // Keep inner controls (coach.card.why / .citation) individually addressable;
        // the background+overlay would otherwise collapse the card into one element.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card")
    }
}

/// One insight's body: title, message, and an expandable why + citation. Reused by
/// the Coach card (headline styling) and the full insights list.
struct InsightContentView: View {
    let insight: Insight
    var headline: Bool = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: insight.kind.symbol)
                    .foregroundStyle(insight.severity.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.title)
                        .font(headline ? .title3.bold() : .headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(insight.message)
                        .font(headline ? .subheadline : .footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Explicit toggle (not a DisclosureGroup) for predictable a11y/testing.
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "book.closed")
                    Text("Why / the science")
                    Spacer(minLength: 4)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach.card.why")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(expanded ? "Hide the science" : "Why — show the science")

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(insight.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CitationLink(citation: insight.citation)
                }
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
    }
}

/// A tappable reference to the study behind an insight.
struct CitationLink: View {
    let citation: Citation

    var body: some View {
        Group {
            if let url = URL(string: citation.url) {
                Link(destination: url) { label }
            } else {
                label
            }
        }
        .accessibilityIdentifier("coach.card.citation")
        .accessibilityLabel("Source: \(citation.shortText)")
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "quote.opening").font(.caption2)
            Text(citation.shortText)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "arrow.up.right").font(.caption2)
        }
        .foregroundStyle(.tint)
    }
}

extension InsightKind {
    var symbol: String {
        switch self {
        case .volume:    return "chart.bar.fill"
        case .trend:     return "chart.line.uptrend.xyaxis"
        case .frequency: return "calendar"
        case .intensity: return "scalemass"
        case .coldStart: return "sparkles"
        }
    }
}

extension InsightSeverity {
    var tint: Color {
        switch self {
        case .attention: return .orange
        case .info:      return .accentColor
        }
    }
}
