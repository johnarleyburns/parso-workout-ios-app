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
                Image(systemName: stateIcon)
                    .font(.caption)
                Text("COACH · \(stateKind)")
                    .font(.caption.bold()).tracking(1.2)
                Spacer()
            }
            .foregroundStyle(stateColor)

            HStack(alignment: .top, spacing: 13) {
                if stateKind == "RECOVERY" || stateKind == "REST" {
                    ZStack {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 46, height: 46)
                        Image(systemName: "checkmark")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(heroTitle)
                        .font(.title2.bold())
                        .lineLimit(2)
                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            if !recoveryChips.isEmpty {
                HStack(spacing: 7) {
                    ForEach(recoveryChips, id: \.0) { label, _ in
                        VStack(spacing: 2) {
                            Text(label).font(.caption).bold()
                            Text("recovering").font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }

            if !decision.warnings.isEmpty {
                Button { withAnimation { warningsExpanded.toggle() } } label: {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Coach notes (\(decision.warnings.count))")
                    }
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
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next hard strength").font(.caption).bold()
                        Text(nextEligible).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
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
                    .accessibilityIdentifier("coach.card.whyToday")
                Button("Your week") { onSeeWeek() }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach.card.yourWeek")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(stateColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(stateColor.opacity(0.35), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card")
    }

    // MARK: - State-aware hero content

    private var stateKind: String {
        switch decision.primary.kind {
        case .rest: return "RECOVERY"
        case .recovery: return "RECOVERY"
        case .easyAerobic: return hasRecentStrength ? "RECOVERY" : "AEROBIC"
        case .moderateAerobic: return "AEROBIC"
        case .vo2Intervals: return "AEROBIC"
        default: return "TRAIN"
        }
    }

    private var stateIcon: String {
        switch decision.primary.kind {
        case .rest, .recovery: return "moon.zzz.fill"
        case .easyAerobic, .moderateAerobic: return "heart.fill"
        default: return "figure.mind.and.body"
        }
    }

    private var stateColor: Color {
        switch decision.primary.kind {
        case .rest, .recovery: return .orange
        case .easyAerobic, .moderateAerobic, .vo2Intervals: return .teal
        default: return .green
        }
    }

    private var heroTitle: String {
        if hasRecentStrength && decision.primary.kind != .strength {
            return "Strength work\nis complete"
        }
        if decision.primary.kind == .rest {
            return "Rest is\ntraining too"
        }
        return decision.primary.title
    }

    private var heroSubtitle: String {
        let recent = decision.observedFacts.first?.label ?? ""
        if hasRecentStrength && decision.primary.kind != .strength {
            let exercises = recentlyTrainedExercises()
            if exercises.isEmpty { return recent }
            return "\(exercises) logged \(recent)."
        }
        if decision.primary.subtitle.isEmpty { return recent }
        return decision.primary.subtitle
    }

    private var recoveryChips: [(String, String)] {
        let deferredExercises = decision.deferred.compactMap { d -> String? in
            guard d.session.kind == .strength, let ex = d.session.exercises?.first else { return nil }
            let parts = BodyPart.parts(forMuscleIDs: ex.primaryMuscles)
            return parts.first?.displayName
        }
        let unique = Array(Set(deferredExercises)).prefix(3)
        return unique.map { ($0, "recovering") }
    }

    private var hasRecentStrength: Bool {
        decision.deferred.contains { $0.session.kind == .strength && !$0.reason.id.isEmpty }
    }

    private func recentlyTrainedExercises() -> String {
        let names = decision.deferred
            .filter { $0.session.kind == .strength }
            .compactMap { $0.session.exercises?.first?.name }
            .prefix(3)
        let list = Array(names)
        if list.isEmpty { return "" }
        if list.count == 1 { return list[0] }
        if list.count == 2 { return "\(list[0]) and \(list[1])" }
        return "\(list[0]), \(list[1]), and \(list[2])"
    }

    // MARK: - CTA

    private var ctaLabel: String {
        switch decision.primary.kind {
        case .rest: return "Take a rest day"
        case .recovery: return "Start recovery"
        case .easyAerobic: return "Start easy cardio"
        case .moderateAerobic: return "Start cardio"
        case .strength: return "Start workout"
        default: return "Start"
        }
    }

    private var ctaSymbol: String {
        decision.primary.kind == .rest || decision.primary.kind == .recovery ? "moon.fill" : "play.fill"
    }

    private var nextEligibleTime: String? {
        guard hasRecentStrength else { return nil }
        let reason = decision.deferred.first { $0.session.kind == .strength }?.reason.message
        return reason
    }
}
