import SwiftUI
import CadenceCore
import CadenceFeatures

/// Test-results card of `TrainingProgressView`.
extension TrainingProgressView {

    @ViewBuilder var testResultsCard: some View {
        card(title: String(localized: "Test results"), citation: nil, tint: .blue) {
            if let facts {
                if facts.assessments.isEmpty {
                    emptyNote(String(localized: "Run a test from the Tests tab \u{2014} strength, push-ups, plank, or a VO\u{2082}max field test \u{2014} and your results trend here, noise-guarded."))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(facts.assessments.enumerated()), id: \.element.id) { idx, s in
                            if idx > 0 { Divider() }
                            Button { Haptics.selection(); path.append(s.kind) } label: { testRow(s) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("progress.trend.\(s.id)")
                        }
                    }
                    ForEach(facts.assessmentsDueForRetest) { s in
                        HStack(spacing: 7) {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(.orange)
                            Text("\(AssessmentDisplay.seriesTitle(s)) is due to re-test (\(s.daysSinceLatest() / 7) weeks).")
                                .font(.caption).foregroundStyle(.orange)
                        }
                        .padding(9).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 8)
                    }
                    Divider().padding(.top, 12).padding(.bottom, 8)
                    CitationLink(citation: CitationRegistry.oneRMEstimation, context: String(localized: "Test methods & validity"), compact: true)
                }
            } else {
                ProgressView("Preparing test results")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    func testRow(_ s: AssessmentSummary) -> some View {
        HStack(spacing: 10) {
            Image(systemName: s.kind.symbol).foregroundStyle(.tint).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(AssessmentDisplay.seriesTitle(s)).font(.subheadline)
                Text(AssessmentDisplay.value(s.latest, kind: s.kind, unit: settings.unit))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            testTrendPill(s.trend)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6).contentShape(Rectangle())
    }

    @ViewBuilder func testTrendPill(_ t: AssessmentTrend) -> some View {
        switch t {
        case .improved:
            pill("improved", .green, bg: .green.opacity(0.15))
        case .declined:
            pill("declined", .red, bg: .red.opacity(0.15))
        case .unchanged:
            pill("no change \u{00b7} within noise", .secondary, bg: .gray.opacity(0.15))
        case .single:
            Text("baseline").font(.caption2).foregroundStyle(.tertiary)
        }
    }
    func pill(_ t: String, _ fg: Color, bg: Color) -> some View {
        Text(t).font(.caption2).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(bg, in: Capsule())
    }
}
