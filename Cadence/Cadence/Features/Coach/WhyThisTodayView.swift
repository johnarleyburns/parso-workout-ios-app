import SwiftUI
import CadenceCore

struct WhyThisTodayView: View {
    let decision: CoachDecision
    var onAltTap: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                completedTodaySection
                whatYouDidSection
                weeklyBalanceSection
                coachPickSection
                ruledOutSection
                whyWonSection
                warningsSection
            }
            .padding()
        }
        .navigationTitle("Why this today")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Completed today banner

    @ViewBuilder
    private var completedTodaySection: some View {
        if case .planComplete(let kind, let desc, let tomorrow) = decision.planAdherence {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("On plan")
                        .font(.headline)
                }
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let tomorrow = tomorrow {
                    HStack(spacing: 4) {
                        Image(systemName: "forward.fill")
                            .font(.caption2)
                        Text("Tomorrow: \(tomorrow)")
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(.green)
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: - What you did (compact)

    private var whatYouDidSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What you did")
                .font(.headline)
                .padding(.bottom, 4)

            let facts = decision.observedFacts
                .filter { $0.kind == .lastStrength || $0.kind == .lastCardio }
                .sorted { ($0.occurredAt ?? .distantPast) > ($1.occurredAt ?? .distantPast) }

            if facts.isEmpty {
                Text("No recent training data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(facts.enumerated()), id: \.element.id) { i, fact in
                        if i > 0 { Divider().padding(.leading, 40) }
                        compactFactRow(fact)
                    }
                }
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func compactFactRow(_ fact: ObservedFact) -> some View {
        HStack(spacing: 8) {
            Image(systemName: fact.kind == .lastStrength ? "dumbbell.fill" : "heart.fill")
                .font(.caption)
                .foregroundStyle(fact.kind == .lastStrength ? .green : .teal)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(fact.title)
                    .font(.subheadline.weight(.medium))
                if let detail = fact.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(fact.value)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("whyToday.fact.\(fact.id)")
    }

    // MARK: - Weekly balance (compact)

    private var weeklyBalanceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("This week")
                .font(.headline)
                .padding(.bottom, 4)

            HStack(spacing: 0) {
                compactMetric("\(decision.weeklyBalance.strengthDays)", "strength days")
                compactMetric("\(Int(decision.weeklyBalance.moderateEquivalentMinutes))", "mod-equivalent min")
                compactMetric("\(decision.weeklyBalance.consecutiveHardDays)", "hard day streak")
            }
            .padding(.vertical, 8)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func compactMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold())
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Coach's Pick

    private var coachPickSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Coach's Pick")
                .font(.headline)
                .padding(.bottom, 4)

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
                    systemsRow
                    confidenceCaveat
                    if !decision.alternatives.isEmpty {
                        Divider()
                        Button {
                            onAltTap?()
                        } label: {
                            HStack {
                                Text("Alternatives").font(.subheadline.weight(.bold))
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
                    targetChip("\(Int(Double(dur)))", label: "mod-eq min")
                }
            }
        }
    }

    @ViewBuilder
    private var systemsRow: some View {
        let systems = decision.primary.systemsTrained
        if !systems.isEmpty {
            (Text("Targets: ").font(.caption2).foregroundStyle(.secondary)
                + Text(systems.map(\.displayName).joined(separator: " · ")).font(.caption2.weight(.semibold)))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("whyToday.coachPick.systems")
        }
    }

    @ViewBuilder
    private var confidenceCaveat: some View {
        if (decision.scoreBreakdowns[decision.primary.id]?.confidencePenalty ?? 0) > 0,
           let citation = CitationRegistry.citation(forId: "tanakaMaxHR2001") {
            VStack(alignment: .leading, spacing: 2) {
                Label("HR zones use an age-estimated max — log a tested max HR for precision.",
                      systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                CitationLink(citation: citation, compact: true)
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
            VStack(alignment: .leading, spacing: 4) {
                Text("What Coach ruled out")
                    .font(.headline)
                    .padding(.bottom, 4)
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
        VStack(alignment: .leading, spacing: 4) {
            Text("Why this won")
                .font(.headline)
                .padding(.bottom, 4)
            card {
                let claims = buildWhyThisWonClaims()
                ForEach(claims, id: \.id) { claim in
                    if claim.id != claims.first?.id {
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(claim.text)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        if let citation = CitationRegistry.citation(forId: claim.selectedCitationId) {
                            CitationLink(citation: citation, compact: true)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func buildWhyThisWonClaims() -> [EvidenceClaim] {
        let bal = decision.weeklyBalance
        let date = decision.generatedAt
        var claims: [EvidenceClaim] = []

        // Each weekly-balance claim is backed by its own typed evidence category, so
        // the citation can only come from that claim's curated pool (no shared pool).
        claims.append(EvidenceClaim(
            id: "strengthDays",
            text: "\(bal.strengthDays) strength days this week (target: 2+)",
            category: .strengthFrequency, date: date))

        claims.append(EvidenceClaim(
            id: "aerobicMinutes",
            text: "\(Int(bal.moderateEquivalentMinutes)) moderate-equivalent aerobic minutes (target: 150)",
            category: .activityMinutesHealth, date: date))

        claims.append(EvidenceClaim(
            id: "recoveryLoad",
            text: "\(bal.consecutiveHardDays) consecutive hard days",
            category: .recoveryMonitoring, date: date))

        // Surface the system-need rationale that helped this session win, if any —
        // these reasons already carry their own typed category + citation.
        if let breakdown = decision.scoreBreakdowns[decision.primary.id] {
            claims.append(contentsOf: breakdown.reasons)
        }

        return claims
    }

    // MARK: - Warnings

    @ViewBuilder
    private var warningsSection: some View {
        if !decision.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Coach Warnings")
                    .font(.headline)
                    .padding(.bottom, 4)
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

    // MARK: - Helpers

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
