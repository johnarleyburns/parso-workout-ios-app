import SwiftUI
import SwiftData
import CadenceCore

struct TestsView: View {
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Assessment.date, order: .reverse) private var assessments: [Assessment]

    @State private var showAdvanced = false

    private var summaries: [AssessmentSummary] { AssessmentMath.summaries(from: assessments) }

    private func latestSummary(for kind: AssessmentKind) -> AssessmentSummary? {
        summaries.first { $0.kind == kind }
    }

    private var advancedKinds: [AssessmentKind] {
        AssessmentKind.allCases.filter { $0.isAdvanced }
    }

    private var latestVO2max: Double? {
        let cardioKinds: [AssessmentKind] = [.cooper12min, .run1_5mile, .rockportWalk, .queensCollegeStep, .vo2maxField]
        return cardioKinds.compactMap { latestSummary(for: $0)?.latest }.max()
    }

    var body: some View {
        NavigationStack {
            List {
                baselineSection

                Section {
                    Text("Standardized tests your coach tracks over time. Re-test on the same protocol after a training block to measure real change.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("tests.assessments.intro")
                }

                ForEach(AssessmentCategory.allCases) { category in
                    let kinds = AssessmentKind.defaultBattery.filter { $0.category == category }
                    if !kinds.isEmpty {
                        Section(category.displayName) {
                            ForEach(kinds) { kind in
                                NavigationLink {
                                    AssessmentDetailView(kind: kind)
                                } label: {
                                    batteryRow(kind)
                                }
                                .accessibilityIdentifier("tests.assessment.\(kind.rawValue)")
                            }
                        }
                    }
                }

                if !advancedKinds.isEmpty {
                    Section {
                        DisclosureGroup("Advanced Tests", isExpanded: $showAdvanced) {
                            Text("These tests require specialized equipment.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(advancedKinds) { kind in
                                NavigationLink {
                                    AssessmentDetailView(kind: kind)
                                } label: {
                                    batteryRow(kind)
                                }
                                .accessibilityIdentifier("tests.assessment.\(kind.rawValue)")
                            }
                        }
                        .accessibilityIdentifier("tests.advanced")
                    }
                }
            }
            .navigationTitle("Tests")
            .accessibilityIdentifier("tests.assessments.list")
        }
    }

    // MARK: - Fitness Baseline Card

    private var baselineSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your Fitness").font(.headline)
                    .accessibilityIdentifier("tests.baseline.header")

                if summaries.isEmpty {
                    Text("Run tests below to build your baseline. Results feed the coach\u{2019}s prescriptions.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    baselineContent
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var baselineContent: some View {
        let strengthSummaries = summaries.filter { $0.kind == .e1RM }
        let enduranceSummaries = summaries.filter { $0.kind.category == .strengthEndurance }

        if !strengthSummaries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Strength").font(.subheadline.weight(.semibold))
                ForEach(strengthSummaries.prefix(4)) { s in
                    baselineRow(title: AssessmentDisplay.seriesTitle(s),
                                value: AssessmentDisplay.value(s.latest, kind: s.kind, unit: settings.unit),
                                trend: s.count >= 2 ? s.trend : nil,
                                retestDue: AssessmentMath.isRetestDue(s))
                }
            }
        }

        if let vo2 = latestVO2max {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cardio").font(.subheadline.weight(.semibold))
                let category = CardioMath.fitnessCategory(vo2max: vo2, ageYears: 30, sexCode: 1)
                baselineRow(title: "VO\u{2082}max",
                            value: String(format: "%.1f mL/kg/min (%@)", vo2, category.rawValue),
                            trend: nil,
                            retestDue: false)
            }
        }

        if !enduranceSummaries.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Endurance").font(.subheadline.weight(.semibold))
                ForEach(enduranceSummaries.prefix(4)) { s in
                    baselineRow(title: s.kind.displayName,
                                value: AssessmentDisplay.value(s.latest, kind: s.kind, unit: settings.unit),
                                trend: s.count >= 2 ? s.trend : nil,
                                retestDue: AssessmentMath.isRetestDue(s))
                }
            }
        }
    }

    private func baselineRow(title: String, value: String, trend: AssessmentTrend?, retestDue: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium)).monospacedDigit()
            if let trend {
                TrendBadge(trend: trend)
            }
            if retestDue {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.orange)
                    .accessibilityLabel("Re-test due")
            }
        }
    }

    // MARK: - Battery Row

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
