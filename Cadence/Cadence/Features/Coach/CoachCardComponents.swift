import SwiftUI
import CadenceCore

/// The two-a-day plan stack (coach-user-control Phase 5): each planned component
/// renders as an independent row with its own Start button AND its own swap
/// affordance — the user can redirect either component without abandoning the
/// other. Extracted from `CoachDecisionCardView` (LOC ratchet).
struct CoachTwoADayStack: View {
    let sessions: [CoachSession]
    var onStart: (CoachSession) -> Void
    var onSwap: (CoachSession) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .font(.caption)
                Text("Today's plan")
                    .font(.caption.bold())
                Spacer()
            }
            .foregroundStyle(.secondary)

            ForEach(sessions) { session in
                row(session)
            }
        }
    }

    private func row(_ session: CoachSession) -> some View {
        HStack(spacing: 6) {
            Button { onStart(session) } label: {
                HStack(spacing: 10) {
                    Image(systemName: CoachSessionStyle.icon(session))
                        .font(.title3)
                        .foregroundStyle(CoachSessionStyle.color(session))
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if !session.subtitle.isEmpty {
                            Text(session.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Label("Start", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(CoachSessionStyle.color(session), in: RoundedRectangle(cornerRadius: 9))
                }
                .padding(10)
                .cadenceGlassBackground(
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    interactive: true,
                    fallback: AnyShapeStyle(CoachSessionStyle.color(session).opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach.card.twoADay.\(session.id)")

            Button { onSwap(session) } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CoachSessionStyle.color(session))
                    .frame(width: 34, height: 34)
                    .cadenceGlassBackground(
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                        interactive: true,
                        fallback: AnyShapeStyle(CoachSessionStyle.color(session).opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach.card.twoADay.swap.\(session.id)")
            .accessibilityLabel("Swap \(session.title) for something else")
        }
    }
}

/// Shared icon/color mapping for a coach session by kind.
enum CoachSessionStyle {
    static func icon(_ session: CoachSession) -> String {
        switch session.kind {
        case .strength: return "dumbbell.fill"
        case .easyAerobic, .moderateAerobic, .vo2Intervals: return "heart.fill"
        case .recovery: return "moon.zzz.fill"
        case .rest: return "bed.double.fill"
        case .assessment: return "checklist"
        }
    }

    static func color(_ session: CoachSession) -> Color {
        switch session.kind {
        case .strength: return .green
        case .easyAerobic, .moderateAerobic, .vo2Intervals: return .teal
        case .recovery: return .orange
        case .rest: return .orange
        case .assessment: return .blue
        }
    }
}

/// One add-on option row (post-completion extras). Extracted from
/// `CoachDecisionCardView` (LOC ratchet).
struct CoachAddOnButton: View {
    let option: CoachAddOnOption
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon(option.status))
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.session.title)
                        .font(.subheadline.weight(.medium))
                    Text(option.message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .opacity(0.6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .foregroundStyle(statusColor(option.status))
        .cadenceGlassBackground(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            interactive: true,
            fallback: AnyShapeStyle(statusColor(option.status).opacity(0.10)))
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach.addon.\(option.session.id)")
    }

    private func icon(_ status: CoachAddOnStatus) -> String {
        switch status {
        case .encouraged: return "hand.thumbsup.fill"
        case .neutral: return "circle"
        case .warn: return "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(_ status: CoachAddOnStatus) -> Color {
        switch status {
        case .encouraged: return .green
        case .neutral: return .secondary
        case .warn: return .orange
        }
    }
}
