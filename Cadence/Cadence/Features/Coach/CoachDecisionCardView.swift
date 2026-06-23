import SwiftUI
import CadenceCore

struct CoachDecisionCardView: View {
    let decision: CoachDecision
    var onStart: (CoachSession) -> Void
    var onSeeWeek: () -> Void
    var onSeeWhy: () -> Void

    @State private var warningsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: decision.primary.kind == .rest ? "moon.zzz.fill" : "figure.mind.and.body")
                Text(stateLabel).font(.caption.bold()).tracking(1.2)
                Spacer()
            }
            .foregroundStyle(stateColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(decision.primary.title)
                    .font(.title3.bold())
                Text(decision.primary.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !decision.warnings.isEmpty {
                Button { withAnimation { warningsExpanded.toggle() } } label: {
                    HStack { Image(systemName: "exclamationmark.triangle.fill"); Text("Coach notes (\(decision.warnings.count))") }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                if warningsExpanded {
                    ForEach(decision.warnings) { w in
                        Text(w.message)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                }
            }

            if let nextEligible = nextEligibleTime {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Next hard strength").font(.caption)
                    Text("· \(nextEligible)").font(.caption.bold())
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("coach.card.nextEligible")
            }

            Button { onStart(decision.primary) } label: {
                Label(ctaLabel, systemImage: ctaSymbol)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .foregroundStyle(.white)
            .background(stateColor, in: RoundedRectangle(cornerRadius: 13))
            .accessibilityIdentifier("coach.card.state")
            .accessibilityLabel(ctaLabel)

            HStack {
                Text("\(Int(decision.weeklyBalance.moderateEquivalentMinutes)) / 150 mod-equiv min")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Why this today") { onSeeWhy() }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                Button("Your week") { onSeeWeek() }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stateColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(stateColor.opacity(0.35), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card")
    }

    private var stateKind: String {
        switch decision.primary.kind {
        case .rest: return "RECOVERY"
        case .recovery: return "RECOVERY"
        case .easyAerobic: return "AEROBIC"
        default: return "TRAIN"
        }
    }

    private var stateLabel: String { "COACH · \(stateKind)" }

    private var stateColor: Color {
        switch decision.primary.kind {
        case .rest, .recovery: return .orange
        case .easyAerobic, .moderateAerobic, .vo2Intervals: return .teal
        default: return .green
        }
    }

    private var ctaLabel: String {
        switch decision.primary.kind {
        case .rest: return "Take a rest day"
        case .recovery: return "Start recovery"
        case .easyAerobic: return "Start easy cardio"
        case .strength: return "Start workout"
        default: return "Start"
        }
    }

    private var ctaSymbol: String {
        decision.primary.kind == .rest ? "moon.fill" : "play.fill"
    }

    private var nextEligibleTime: String? {
        guard decision.primary.kind == .recovery || decision.primary.kind == .easyAerobic else { return nil }
        let maxDeferred = decision.deferred.map { $0.reason }.compactMap { _ in
            decision.deferred.first?.reason.message
        }.first
        return maxDeferred ?? decision.deferred.first?.reason.message
    }
}
