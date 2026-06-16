import SwiftUI
import SwiftData
import CadenceCore

/// The **Plan** tab (strength-pivot P4). Its first real content is the coach's
/// **assessment battery**: standardized, repeatable strength and strength-endurance
/// tests the engine tracks over time and re-tests like a pre/post study. Goals, a
/// training calendar, and favorited exercises join it in a later phase.
struct PlanView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Assessment.date, order: .reverse) private var assessments: [Assessment]

    private var summaries: [AssessmentSummary] { AssessmentMath.summaries(from: assessments) }

    /// The most-recent summary for a given kind (kinds may have several series —
    /// e.g. e1RM per lift; the battery row shows the latest activity).
    private func latestSummary(for kind: AssessmentKind) -> AssessmentSummary? {
        summaries.first { $0.kind == kind }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Standardized tests your coach tracks over time. Re-test on the same protocol after a training block to measure real change.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("plan.assessments.intro")
                }

                ForEach(AssessmentCategory.allCases) { category in
                    Section(category.displayName) {
                        ForEach(AssessmentKind.allCases.filter { $0.category == category }) { kind in
                            NavigationLink {
                                AssessmentDetailView(kind: kind)
                            } label: {
                                batteryRow(kind)
                            }
                            .accessibilityIdentifier("plan.assessment.\(kind.rawValue)")
                        }
                    }
                }
            }
            .navigationTitle("Plan")
            .accessibilityIdentifier("plan.assessments.list")
        }
    }

    @ViewBuilder
    private func batteryRow(_ kind: AssessmentKind) -> some View {
        let latest = latestSummary(for: kind)
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName).font(.body)
                if let latest {
                    Text("Last: \(AssessmentDisplay.value(latest.latest, kind: kind, unit: settings.unit))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Not tested yet").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if let latest, latest.count >= 2 {
                TrendBadge(trend: latest.trend)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A compact up/down/hold pill for an assessment series.
struct TrendBadge: View {
    let trend: AssessmentTrend
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: trend.symbol).font(.caption2)
            Text(trend.label).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(trend.tint)
        .background(trend.tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trend: \(trend.label)")
    }
}

/// Shared "coming soon" scaffold for the not-yet-built tabs.
struct ComingSoonPlaceholder: View {
    let systemImage: String
    let title: String
    let message: String
    let identifier: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}
