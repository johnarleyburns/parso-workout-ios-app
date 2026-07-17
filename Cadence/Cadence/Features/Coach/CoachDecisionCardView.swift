import SwiftUI
import CadenceCore

struct CoachDecisionCardView: View {
    let decision: CoachDecision
    let addOnRecommendation: CoachAddOnRecommendation
    let topInsight: Insight?
    var onStart: (CoachSession) -> Void
    var onAddOn: (CoachSession, CoachAddOnStatus) -> Void = { _, _ in }
    var onSeeInsights: () -> Void
    var onPreferences: () -> Void
    var onPickAlternative: () -> Void = {}
    var onFixCustomExercises: () -> Void = {}
    var onStrengthAnyway: () -> Void = {}
    var onSwapComponent: (CoachSession) -> Void = { _ in }

    @State private var warningsExpanded = false
    @State private var addOnsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: stateIcon)
                    .font(.caption)
                Text("COACH · \(stateKind)")
                    .font(.caption.bold()).tracking(1.2)
                Spacer()
                Button { onPreferences() } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.card.preferences")
                .accessibilityLabel("Coach preferences")
            }
            .foregroundStyle(stateColor)

            HStack(alignment: .top, spacing: 13) {
                if stateKind == "RECOVERY" || stateKind == "REST" {
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
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("coach.card.heroTitle")
                    Text(heroSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                        .accessibilityIdentifier("coach.card.heroSubtitle")
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

                if let structure = sessionStructureFact {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.grid.2x2")
                            Text("\(structure.title): \(structure.value)")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                        if let detail = structure.detail {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(structure.citationIds.compactMap { CitationRegistry.citation(forId: $0) }) { citation in
                            CitationLink(citation: citation, compact: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("coach.card.sessionStructure")
                }
            }

            if isCompleteState {
                // Completed state: acknowledgement + optional add-on CTAs
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Plan followed")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(stateColor, in: RoundedRectangle(cornerRadius: 13))
                    // Combine into one element so the identifier resolves uniquely
                    // (otherwise it propagates to both the icon and the label).
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("coach.card.completeBanner")
                    .accessibilityLabel("Plan followed — today's session done")

                    // Encouraged primary add-on
                    if let primary = addOnRecommendation.primaryOption, primary.status == .encouraged {
                        CoachAddOnButton(option: primary) { onAddOn(primary.session, primary.status) }
                    }

                    // Neutral / warn secondary options
                    if !addOnRecommendation.secondaryOptions.isEmpty {
                        Button {
                            withAnimation { addOnsExpanded.toggle() }
                        } label: {
                            HStack {
                                Image(systemName: addOnsExpanded ? "chevron.up" : "plus.circle")
                                Text("Choose extra workout")
                            }
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                        }
                        .foregroundStyle(stateColor)
                        .background(stateColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                        .buttonStyle(.plain)
                    }

                    if addOnsExpanded {
                        ForEach(addOnRecommendation.secondaryOptions) { option in
                            CoachAddOnButton(option: option) { onAddOn(option.session, option.status) }
                        }
                    }
                }
            } else if decision.todayPlannedRecommendations.count > 1 {
                // Two-a-day: show each planned workout as an independent row with
                // its own Start button. The scored primary's CTA is replaced by
                // this stack.
                twoADayStack
            } else {
                VStack(spacing: 8) {
                    Button { onStart(decision.primary) } label: {
                        Label(ctaLabel, systemImage: ctaSymbol)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .cadenceGlassButton(prominent: true, tint: stateColor)
                    .accessibilityIdentifier("home.coachStart")
                    .accessibilityLabel(ctaLabel)

                    if showsAlternativesLink {
                        Button { onPickAlternative() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.caption2.weight(.bold))
                                Text("Not feeling it? Pick another")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(stateColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("coach.card.pickAlternative")
                        .accessibilityLabel("Pick an alternative workout")
                    }

                    if showsStrengthAnywayLink {
                        Button { onStrengthAnyway() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "dumbbell")
                                    .font(.caption2.weight(.bold))
                                Text("Want to lift? Build a strength session")
                            }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("coach.card.strengthAnyway")
                        .accessibilityLabel("Build a strength session anyway")
                    }
                }
            }

            if let topInsight {
                Divider().padding(.top, 2)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: topInsight.kind.symbol)
                            .font(.subheadline)
                            .foregroundStyle(topInsight.severity.tint)
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(topInsight.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Text(topInsight.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                    }

                    Button { onSeeInsights() } label: {
                        HStack(spacing: 4) {
                            Text("More insights")
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(stateColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("coach.card.insights")

                    if topInsight.kind == .exerciseDefinition {
                        Button { onFixCustomExercises() } label: {
                            Label("Fix in Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(
            in: RoundedRectangle(cornerRadius: 20, style: .continuous),
            tint: stateColor)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.card")
    }

    // MARK: - State-aware hero content

    private var isCompleteState: Bool {
        if case .planComplete = decision.planAdherence { return true }
        return false
    }

    /// The coach's transparent full-body-vs-split explanation for the primary
    /// strength session, when one is being recommended (open-door principle).
    private var sessionStructureFact: ObservedFact? {
        decision.observedFacts.first { $0.kind == .sessionStructure }
    }

    private var todayCompleteDescription: String {
        if case .planComplete(_, let desc, _) = decision.planAdherence { return desc }
        return ""
    }

    private var planAdherenceCompletedKind: CoachSessionKind? {
        if case .planComplete(let kind, _, _) = decision.planAdherence { return kind }
        return nil
    }

    private var stateKind: String {
        if isCompleteState { return "PLAN DONE" }
        if remainingPlannedRecommendation?.isAerobic == true { return "AEROBIC" }
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
            switch planAdherenceCompletedKind {
            case .strength:
                return "You put in the work"
            case .easyAerobic, .moderateAerobic:
                return "Cardio banked for today"
            case .vo2Intervals:
                return "Speed work in the books"
            case .recovery:
                return "Recovery done for today"
            case .rest:
                return "Rest earned for today"
            case .assessment:
                return "Baseline in the books"
            case nil:
                return "Today's workouts are completed"
            }
        }
        if let planned = remainingPlannedRecommendation {
            return planned.title
        }
        if hasRecentStrength && decision.primary.kind != .strength {
            // Name the actual follow-up when it's a trainable cardio session so the
            // two-a-day's remaining half is explicit; otherwise acknowledge strength.
            switch decision.primary.kind {
            case .easyAerobic, .moderateAerobic, .vo2Intervals:
                return decision.primary.title
            default:
                return "Strength is done today"
            }
        }
        if decision.primary.kind == .rest {
            return "Rest is training too"
        }
        return decision.primary.title
    }

    private var heroSubtitle: String {
        if isCompleteState {
            return todayCompleteDescription
        }
        let recent = decision.observedFacts.first.map { "\($0.title): \($0.value)" } ?? ""
        if let planned = remainingPlannedRecommendation {
            return planned.subtitle.isEmpty ? recent : planned.subtitle
        }
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

    private var remainingPlannedRecommendation: CoachSession? {
        guard decision.todayPlannedRecommendations.count == 1 else { return nil }
        return decision.todayPlannedRecommendations.first
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

    /// "Pick another" is offered whenever the coach scored alternatives to swap
    /// to — the user can always redirect the prescription, whatever its kind
    /// (coach-user-control Phase 5 relaxed the old cardio-only gate).
    private var showsAlternativesLink: Bool {
        !decision.alternatives.isEmpty
    }

    /// "Strength anyway" appears when today's coach output carries no strength
    /// at all — the coach suggests, it does not proscribe: the user can always
    /// ask for a strength session and peruse it in the plan editor.
    private var showsStrengthAnywayLink: Bool {
        guard !isCompleteState else { return false }
        let offered = [decision.primary] + decision.alternatives + decision.todayPlannedRecommendations
        return !offered.contains { $0.kind == .strength }
    }

    private var nextEligibleTime: String? {
        guard hasRecentStrength else { return nil }
        let reason = decision.deferred.first { $0.session.kind == .strength }?.reason.message
        return reason
    }

    // MARK: - Two-a-day stack

    private var twoADayStack: some View {
        CoachTwoADayStack(sessions: decision.todayPlannedRecommendations,
                          onStart: onStart,
                          onSwap: onSwapComponent)
    }
}
