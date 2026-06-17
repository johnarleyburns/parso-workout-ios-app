import SwiftUI
import CadenceCore

/// The Coach card — Home's hero (strength-pivot P5.2). Surfaces the top prescriptive
/// `Recommendation` from the engine: a concrete next action plus a loggable
/// `SetTarget` (sets·reps·load·RIR in the user's unit), with an always-available
/// "Why / the science" expander and its citation (decision D3). The read-only
/// `Insight`s remain reachable behind "See all insights".
struct CoachCardView: View {
    let recommendation: Recommendation
    var insightCount: Int
    var unit: MeasurementUnitPreference
    /// "Do this workout" — materialize the prescription into a pre-filled logger
    /// session (strength-pivot P5.3). The fast, default path.
    var onDoThis: () -> Void
    var onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "figure.mind.and.body")
                Text("COACH").font(.caption.bold()).tracking(1.2)
                Spacer()
                Text("Do next").font(.caption).foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)

            RecommendationContentView(recommendation: recommendation, unit: unit, headline: true)

            // The primary action — open the logger pre-filled with this prescription's
            // movement, planned sets, target reps, and (when prescribed) load (P5.3).
            Button { Haptics.selection(); onDoThis() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checklist")
                    Text("Do this workout").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline).opacity(0.8)
                }
                .padding(.vertical, 12).padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .foregroundStyle(.white)
                .background(.tint, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach.card.doThis")
            .accessibilityLabel("Do this workout — start the prescribed session")

            if insightCount > 0 {
                Button { Haptics.selection(); onSeeAll() } label: {
                    HStack(spacing: 4) {
                        Text("See all insights (\(insightCount))").font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("coach.card.seeAll")
            }

            Text("Coaching, not medical advice.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.tint.opacity(0.25), lineWidth: 1))
        // Keep inner controls (coach.card.target / .why / .citation) individually
        // addressable; the background+overlay would otherwise collapse the card.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card")
    }
}

/// One prescription's body: title, imperative action, a concrete `SetTarget` chip,
/// and an expandable why + citation. The P5 evolution of `InsightContentView` — it
/// reuses the same `coach.card.why` / `coach.card.citation` a11y ids so the cited
/// rationale (D3) stays testable.
struct RecommendationContentView: View {
    let recommendation: Recommendation
    var unit: MeasurementUnitPreference
    var headline: Bool = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: recommendation.kind.symbol)
                    .foregroundStyle(recommendation.kind.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(recommendation.title)
                        .font(headline ? .title3.bold() : .headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(recommendation.action)
                        .font(headline ? .subheadline : .footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("coach.card.action")
                }
            }

            // The concrete, loggable target — the heart of a prescription (P5).
            // CardioHIIT recs (P6) show the interval protocol name instead of a SetTarget.
            if let cardio = recommendation.cardioPrescription {
                HStack(spacing: 8) {
                    Image(systemName: "figure.highintensity.intervaltraining").font(.caption)
                    Text(cardio)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(recommendation.confidence.label)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("coach.card.target")
            } else if let target = recommendation.target {
                HStack(spacing: 8) {
                    Image(systemName: "dumbbell.fill").font(.caption)
                    Text(target.summary(unit: unit))
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text(recommendation.confidence.label)
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.vertical, 8).padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("coach.card.target")
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
                    Text(recommendation.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    CitationLink(citation: recommendation.citation)
                }
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
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
        case .assessment: return "checklist"
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

extension RecommendationKind {
    var symbol: String {
        switch self {
        case .progression: return "chart.line.uptrend.xyaxis"
        case .deload:      return "arrow.down.right.circle"
        case .addVolume:   return "plus.circle"
        case .starter:     return "sparkles"
        case .cardioHIIT:  return "figure.highintensity.intervaltraining"
        }
    }

    var tint: Color {
        switch self {
        case .progression: return .green
        case .deload:      return .orange
        case .addVolume:   return .accentColor
        case .starter:     return .accentColor
        case .cardioHIIT:  return .pink
        }
    }
}
