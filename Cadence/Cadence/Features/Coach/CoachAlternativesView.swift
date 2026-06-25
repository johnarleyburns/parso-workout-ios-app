import SwiftUI
import CadenceCore

struct CoachAlternativesView: View {
    let decision: CoachDecision
    var onSelect: (CoachSession) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Same prescription, different way.")
                        .font(.title3.bold())
                    Text("Coach needs \(prescriptionSummary) today. These options satisfy the target or come closest while respecting recovery.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)

                ForEach(alternativesList) { session in
                    alternativeCard(session)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("After selection").font(.subheadline.weight(.semibold))
                    Text("Coach records a preference for this choice when the prescription is \(prescriptionSummary) work. Next time, it can become Coach's Pick if it's eligible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .navigationTitle("Alternatives")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach.alternatives")
    }

    private var prescriptionSummary: String {
        switch decision.primary.kind {
        case .moderateAerobic: return "moderate aerobic"
        case .easyAerobic: return "easy aerobic"
        case .vo2Intervals: return "vigorous aerobic"
        case .strength: return "strength"
        case .recovery: return "recovery"
        case .rest: return "rest"
        case .assessment: return "assessment"
        }
    }

    private var alternativesList: [CoachSession] {
        [decision.primary] + decision.alternatives
    }

    private func alternativeCard(_ session: CoachSession) -> some View {
        let isPrimary = session.id == decision.primary.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                altIcon(for: session)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title)
                        .font(.headline)
                    Text(altSubtitle(for: session))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    pills(for: session)
                    if let citation = session.citationIds.lazy
                        .compactMap({ CitationRegistry.citation(forId: $0) }).first {
                        CitationLink(citation: citation, compact: true)
                    }
                    Button {
                        onSelect(session)
                    } label: {
                        Text("Choose \(session.title.lowercased())")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .foregroundStyle(.white)
                    .background(.teal, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("coach.alternatives.choose.\(session.id)")
                }
            }
        }
        .padding(15)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isPrimary ? Color.teal.opacity(0.08) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isPrimary ? Color.teal.opacity(0.3) : Color(.separator).opacity(0.5), lineWidth: 1)
        )
        .accessibilityIdentifier("coach.alternatives.row.\(session.id)")
    }

    private func altIcon(for session: CoachSession) -> some View {
        let icon: String = switch session.modality {
        case .walk: "figure.walk"
        case .run: "figure.run"
        case .cycle: "figure.outdoor.cycle"
        case .swim: "figure.pool.swim"
        case .row: "figure.rower"
        case .boxing: "figure.boxing"
        case .other, nil:
            switch session.kind {
            case .strength: "dumbbell.fill"
            case .vo2Intervals: "figure.highintensity.intervaltraining"
            case .recovery: "figure.mind.and.body"
            case .rest: "moon.zzz.fill"
            default: "figure.run"
            }
        }
        return ZStack {
            RoundedRectangle(cornerRadius: 12).fill(.teal)
            Image(systemName: icon).font(.body.weight(.bold)).foregroundStyle(.white)
        }
    }

    private func altSubtitle(for session: CoachSession) -> String {
        if !session.subtitle.isEmpty { return session.subtitle }
        var parts: [String] = []
        if let dur = session.durationMinutes { parts.append("\(dur) min") }
        if let intensity = session.intensity { parts.append(intensity.rawValue) }
        return parts.joined(separator: " · ")
    }

    private func pills(for session: CoachSession) -> some View {
        let isPrimary = session.id == decision.primary.id
        return HStack(spacing: 6) {
            matchPill(isPrimary ? "coach's pick" : matchLabel(for: session), isFull: isPrimary)
            if let mod = session.modality {
                impactPill(for: mod)
            }
            if let dur = session.durationMinutes {
                modEqPill(for: session, duration: dur)
            }
        }
    }

    private func matchPill(_ text: String, isFull: Bool) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .fill(isFull ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
            )
            .foregroundStyle(isFull ? .green : .orange)
    }

    private func matchLabel(for session: CoachSession) -> String {
        if session.kind == decision.primary.kind { return "full match" }
        return "close match"
    }

    private func impactPill(for modality: CoachSession.AerobicModality) -> some View {
        let (label, color): (String, Color) = switch modality {
        case .walk, .swim: ("low impact", .green)
        case .cycle, .row: ("low impact", .green)
        case .run: ("moderate impact", .orange)
        case .boxing: ("high impact", .orange)
        case .other: ("varied", .secondary)
        }
        return Text(label)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 999).fill(color.opacity(0.12)))
            .foregroundStyle(color)
    }

    private func modEqPill(for session: CoachSession, duration: Int) -> some View {
        let modEq: Double = switch session.intensity {
        case .easy: Double(duration) * 0.5
        case .moderate: Double(duration)
        case .vigorous: Double(duration) * 2
        case nil: Double(duration)
        }
        return Text("+\(Int(modEq)) mod-eq min")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 999).fill(Color.blue.opacity(0.12)))
            .foregroundStyle(.blue)
    }
}
