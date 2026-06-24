import SwiftUI
import CadenceCore

struct WhyThisTodayView: View {
    let decision: CoachDecision
    var onAltTap: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                whatYouDidSection
                coachPickSection
                ruledOutSection
                whyWonSection
                warningsSection
                policySection
            }
            .padding()
        }
        .navigationTitle("Why this today")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - What you did

    private var whatYouDidSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("What you did")
            card {
                ForEach(decision.observedFacts) { fact in
                    if fact.id != decision.observedFacts.first?.id {
                        Divider()
                    }
                    factRow(fact)
                }
            }
        }
    }

    private func factRow(_ fact: ObservedFact) -> some View {
        HStack(spacing: 10) {
            glyph(for: fact.kind)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(fact.title)
                    .font(.subheadline.weight(.semibold))
                if let detail = fact.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(fact.value)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("whyToday.fact.\(fact.id)")
    }

    private func glyph(for kind: ObservedFact.Kind) -> some View {
        let (bg, content, icon): (Color, Color, String) = switch kind {
        case .lastStrength:   (.green, .white, "figure.strengthtraining.traditional")
        case .lastCardio:     (.teal, .white, "figure.run")
        case .weeklyStrengthDays: (.orange, .white, "7")
        case .weeklyModerateEquivalentMinutes: (.blue, .white, "M")
        }
        return ZStack {
            Circle().fill(bg)
            if icon.allSatisfy(\.isNumber) {
                Text(icon).font(.caption2.weight(.heavy)).foregroundStyle(content)
            } else {
                Image(systemName: icon).font(.caption2.weight(.bold)).foregroundStyle(content)
            }
        }
    }

    // MARK: - Coach's Pick

    private var coachPickSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Coach's Pick")
            card(highlight: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        pickIcon
                            .frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(decision.primary.title)
                                .font(.title3.bold())
                            Text(coachPickSubtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    targetGrid
                    if !decision.alternatives.isEmpty {
                        Divider()
                        Button {
                            onAltTap?()
                        } label: {
                            HStack {
                                Text("alternatives").font(.subheadline.weight(.bold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2.bold())
                            }
                            .foregroundStyle(.teal)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("whyToday.coachPick.alternatives")
                    }
                }
            }
            .accessibilityIdentifier("whyToday.coachPick")
        }
    }

    private var coachPickSubtitle: String {
        var parts: [String] = []
        if !decision.primary.subtitle.isEmpty { parts.append(decision.primary.subtitle) }
        if let dur = decision.primary.durationMinutes {
            parts.append("\(dur) min")
        }
        parts.append(decision.primary.kind.rawValue)
        return parts.joined(separator: " · ")
    }

    private var pickIcon: some View {
        let icon: String = switch decision.primary.kind {
        case .strength: "figure.strengthtraining.traditional"
        case .easyAerobic, .moderateAerobic, .vo2Intervals: "figure.run"
        case .recovery: "figure.mind.and.body"
        case .rest: "moon.zzz.fill"
        case .assessment: "checklist"
        }
        return ZStack {
            RoundedRectangle(cornerRadius: 14).fill(.teal)
            Image(systemName: icon).font(.title3.weight(.bold)).foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var targetGrid: some View {
        if let dur = decision.primary.durationMinutes {
            HStack(spacing: 7) {
                targetChip("\(dur) min", label: "duration")
                if let mod = decision.primary.modality {
                    targetChip(mod.rawValue.capitalized, label: "type")
                }
                if decision.primary.kind == .moderateAerobic || decision.primary.kind == .easyAerobic {
                    let modEq = Double(dur)
                    targetChip("\(Int(modEq))", label: "mod-eq min")
                }
            }
        }
    }

    private func targetChip(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.bold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - What Coach ruled out

    @ViewBuilder
    private var ruledOutSection: some View {
        if !decision.deferred.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("What Coach ruled out")
                card {
                    ForEach(decision.deferred) { d in
                        if d.id != decision.deferred.first?.id {
                            Divider()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(d.session.title).font(.subheadline.weight(.semibold))
                            Text(d.reason.message).font(.caption).foregroundStyle(.red)
                            let resolved = resolvedCitations(d.reason.citationIds)
                            if !resolved.isEmpty {
                                ForEach(resolved) { citation in
                                    CitationLink(citation: citation, compact: true)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    // MARK: - Why this won

    private var whyWonSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Why this won")
            card {
                let isStrength = decision.primary.kind == .strength
                if isStrength {
                    inlineClaim("• \(decision.weeklyBalance.strengthDays) strength days this week (target: 2+)",
                                citation: CitationRegistry.schoenfeld2021)
                }
                inlineClaim("• \(Int(decision.weeklyBalance.moderateEquivalentMinutes)) moderate-equivalent aerobic minutes (target: 150)",
                            citation: CitationRegistry.ekelundActivityMortality2016)
                inlineClaim("• \(decision.weeklyBalance.consecutiveHardDays) consecutive hard days",
                            citation: CitationRegistry.meeusenOvertraining2013)
            }
        }
    }

    @ViewBuilder
    private func inlineClaim(_ text: String, citation: Citation) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(.caption)
            Spacer()
        }
        CitationLink(citation: citation, compact: true)
    }

    // MARK: - Warnings

    @ViewBuilder
    private var warningsSection: some View {
        if !decision.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                sectionLabel("Coach Warnings")
                card {
                    ForEach(decision.warnings) { w in
                        if w.id != decision.warnings.first?.id {
                            Divider()
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.message).font(.caption)
                            let resolved = resolvedCitations(w.citationIds)
                            if !resolved.isEmpty {
                                ForEach(resolved) { citation in
                                    CitationLink(citation: citation, compact: true)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    // MARK: - Policy

    private var policySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Policy")
            card {
                Text("Coach's recovery windows are conservative defaults. They are not a diagnosis or a universal physiological law. Actual recovery varies by person, sleep, nutrition, and stress.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.heavy))
            .tracking(1)
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
            .padding(.leading, 3)
    }

    private func card(highlight: Bool = false, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(highlight ? Color.teal.opacity(0.05) : Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(highlight ? Color.teal.opacity(0.3) : Color(.separator).opacity(0.5), lineWidth: 1)
            )
    }

    private func resolvedCitations(_ ids: [String]) -> [Citation] {
        ids.compactMap { CitationRegistry.citation(forId: $0) }
    }
}
