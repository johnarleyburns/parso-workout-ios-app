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
                if isCompleteState || stateKind == "RECOVERY" || stateKind == "REST" {
                    ZStack {
                        Circle()
                            .fill(stateColor)
                            .frame(width: 46, height: 46)
                        Image(systemName: isCompleteState ? "checkmark.circle.fill" : "checkmark")
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
                    if isCompleteState, let tomorrow = tomorrowPreview {
                        HStack(spacing: 4) {
                            Image(systemName: "forward.fill")
                                .font(.caption2)
                            Text("Tomorrow: \(tomorrow)")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(stateColor)
                        .padding(.top, 4)
                    }
                }
            }

            if !isCompleteState {
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
                            VStack(alignment: .leading, spacing: 3) {
                                Text(w.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                ForEach(w.citationIds.compactMap { CitationRegistry.citation(forId: $0) }) { citation in
                                    CitationLink(citation: citation, compact: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
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
            }

            if isCompleteState {
                // Completed state: no Start button, just acknowledgement
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("On plan")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.white)
                .background(stateColor, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityIdentifier("coach.card.completeBanner")
                .accessibilityLabel("On plan — today's session complete")
            } else {
                Button { onStart(decision.primary) } label: {
                    Label(ctaLabel, systemImage: ctaSymbol)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .foregroundStyle(.white)
                .background(stateColor, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityIdentifier("home.coachStart")
                .accessibilityLabel(ctaLabel)
            }

            HStack {
                Button("Why this today") { onSeeWhy() }
                    .font(.caption.weight(.medium))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach.card.whyToday")
                Spacer()
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

    private var isCompleteState: Bool {
        if case .planComplete = decision.planAdherence { return true }
        return false
    }

    private var tomorrowPreview: String? {
        if case .planComplete(_, _, let preview) = decision.planAdherence { return preview }
        return nil
    }

    private var todayCompleteDescription: String {
        if case .planComplete(_, let desc, _) = decision.planAdherence { return desc }
        return ""
    }

    private var stateKind: String {
        if isCompleteState { return "COMPLETE" }
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
        if isCompleteState { return "checkmark.seal.fill" }
        switch decision.primary.kind {
        case .rest, .recovery: return "moon.zzz.fill"
        case .easyAerobic, .moderateAerobic: return "heart.fill"
        default: return "figure.mind.and.body"
        }
    }

    private var stateColor: Color {
        if isCompleteState { return .green }
        switch decision.primary.kind {
        case .rest, .recovery: return .orange
        case .easyAerobic, .moderateAerobic, .vo2Intervals: return .teal
        default: return .green
        }
    }

    private var heroTitle: String {
        if isCompleteState {
            let kindName: String = switch decision.primary.kind {
            case .moderateAerobic: fallthrough
            case .easyAerobic: "Cardio"
            case .strength: "Strength"
            case .recovery: "Recovery"
            case .rest: "Rest"
            case .vo2Intervals: "Intervals"
            case .assessment: "Assessment"
            }
            return "\(kindName)\ncomplete"
        }
        if hasRecentStrength && decision.primary.kind != .strength {
            return "Strength work\nis complete"
        }
        if decision.primary.kind == .rest {
            return "Rest is\ntraining too"
        }
        return decision.primary.title
    }

    private var heroSubtitle: String {
        if isCompleteState {
            return todayCompleteDescription
        }
        let recent = decision.observedFacts.first.map { "\($0.title): \($0.value)" } ?? ""
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
        // Every trainable recommendation reads "Start" and routes to that
        // workout's setup surface first (never an active recorder). Only rest /
        // recovery keep bespoke copy because they aren't a workout launch.
        switch decision.primary.kind {
        case .rest: return "Take a rest day"
        case .recovery: return "Start recovery"
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
