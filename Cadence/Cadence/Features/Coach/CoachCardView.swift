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
    var onStart: () -> Void
    var onSeeAll: () -> Void

    @State private var scienceExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1 — eyebrow: "COACH · TODAY" + About (info) link
            HStack(spacing: 8) {
                Image(systemName: "figure.mind.and.body").font(.caption)
                Text("COACH · TODAY").font(.caption.bold()).tracking(1.2)
                Spacer()
                NavigationLink { CoachAboutView() } label: {
                    Image(systemName: "info.circle").font(.subheadline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.card.about")
                .accessibilityLabel("About the Coach")
            }
            .foregroundStyle(.tint)

            // 2 — recommendation title, action, and the loggable target chip.
            //     showScience: false suppresses this component's own toggle so
            //     "The science" can live in the footer (item 4) instead.
            RecommendationContentView(recommendation: recommendation,
                                      unit: unit,
                                      headline: true,
                                      showScience: false)

            // 3 — the one primary action
            Button { Haptics.selection(); onStart() } label: {
                Label("Start workout", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                    .background(.green, in: RoundedRectangle(cornerRadius: 13))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.coachStart")
            .accessibilityLabel("Start the coach's workout")

            // 4 — footer row: "The science" (left) · "All insights (n)" (right)
            HStack(spacing: 8) {
                Button { withAnimation(.easeInOut(duration: 0.2)) { scienceExpanded.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "book.closed").font(.caption2)
                        Text("The science")
                        Image(systemName: scienceExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.card.why")
                .accessibilityLabel(scienceExpanded ? "Hide the science" : "Why — show the science")

                Spacer()

                if insightCount > 0 {
                    Button { Haptics.selection(); onSeeAll() } label: {
                        HStack(spacing: 3) {
                            Text("All insights (\(insightCount))")
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach.card.seeAll")
                }
            }

            // 5 — expanded science: detail + citations, revealed under the footer
            if scienceExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recommendation.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(recommendation.allCitations) { c in
                        CitationLink(citation: c)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.tint.opacity(0.40), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
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
    var showScience: Bool = true
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

            if showScience {
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
                        ForEach(recommendation.allCitations) { c in
                            CitationLink(citation: c)
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity)
                }
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
    var context: String?
    var compact: Bool = false

    var body: some View {
        NavigationLink {
            CitationDetailView(citation: citation, context: context)
        } label: {
            compact ? AnyView(compactLabel) : AnyView(label)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(compact ? "progress.card.citation" : "coach.card.citation")
        .accessibilityLabel("Source: \(citation.shortText)")
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "quote.opening").font(.caption2)
            Text(citation.shortText)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right").font(.caption2)
        }
        .foregroundStyle(.tint)
    }

    private var compactLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("the science")
                .font(.caption2).foregroundStyle(.tint)
            Image(systemName: "chevron.forward")
                .font(.caption2).foregroundStyle(.tint)
        }
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
