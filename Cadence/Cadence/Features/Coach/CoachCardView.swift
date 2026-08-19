import SwiftUI
import CadenceCore
import CadenceFeatures

/// One insight's body: title, message, and an expandable why + citation. Reused by
/// the Coach card (headline styling) and the full insights list.
struct InsightContentView: View {
    let insight: Insight
    var headline: Bool = false
    var onFixCustomExercises: (() -> Void)? = nil
    var onInsightAction: ((Insight.Action) -> Void)? = nil
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
            .accessibilityLabel(expanded ? "Hide the science" : "Show the science")

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

            if let action = insight.action, let onAction = onInsightAction {
                Button {
                    onAction(action)
                } label: {
                    HStack {
                        switch action {
                        case .addGapsToPlan:
                            Label("Add these gaps to my planned workouts", systemImage: "plus.circle")
                                .font(.caption.weight(.medium))
                        case .revertToSafePlan:
                            Label("Back to safe planning", systemImage: "arrow.uturn.backward")
                                .font(.caption.weight(.medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }

            if insight.kind == .exerciseDefinition, let onFix = onFixCustomExercises {
                Button(action: onFix) {
                    Label("Fix in Settings", systemImage: "gearshape")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
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
            Text("The science")
                .font(.caption2).foregroundStyle(.tint)
            Image(systemName: "chevron.forward")
                .font(.caption2).foregroundStyle(.tint)
        }
    }
}

/// One `The science ›` row for a coaching output, however many studies back it
/// (field test 2026-08-18 #10, decision **D9**). It pushes `CoachSourcesView`,
/// which lists them all vertically — a coach surface never stacks a science row
/// per citation again.
struct CoachSourcesLink: View {
    let citationIds: [String]
    /// Optional per-id "How this applies" copy; the registry supplies the rest.
    var contexts: [String: String] = [:]
    var identifier: String = "coach.sources.link"

    var body: some View {
        let citations = CitationPresenter.citations(forIds: citationIds)
        if !citations.isEmpty {
            NavigationLink {
                CoachSourcesView(citations: citations, contexts: contexts)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("The science")
                    Image(systemName: "chevron.forward")
                }
                .font(.caption2)
                .foregroundStyle(.tint)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel("The science, \(citations.count) source\(citations.count == 1 ? "" : "s")")
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
        case .exerciseDefinition: return "exclamationmark.triangle.fill"
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
