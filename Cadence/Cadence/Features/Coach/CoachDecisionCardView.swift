import SwiftUI
import CadenceCore
import CadenceFeatures

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
    var onInsightAction: ((Insight.Action) -> Void)? = nil
    /// Phase B: true when a strength event was completed today (from actual log data).
    var hasTodayStrengthCompleted: Bool = false
    /// Phase B: exercise names from completed strength today, deduped, newest first.
    var todayLoggedExerciseNames: [String] = []

    @State var warningsExpanded = false
    @State var addOnsExpanded = false

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
                                CoachSourcesLink(citationIds: w.citationIds,
                                                 identifier: "coach.card.warnings.science")
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
                        CoachSourcesLink(citationIds: structure.citationIds,
                                         identifier: "coach.card.structure.science")
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

                    if let action = topInsight.action, let onAction = onInsightAction {
                        Button { onAction(action) } label: {
                            switch action {
                            case .addGapsToPlan:
                                Label("Add these gaps to my planned workouts", systemImage: "plus.circle")
                            case .revertToSafePlan:
                                Label("Back to safe planning", systemImage: "arrow.uturn.backward")
                            }
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

}
