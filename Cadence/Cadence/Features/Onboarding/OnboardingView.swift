import SwiftUI
import CadenceCore
import CadenceFeatures

/// First-run flow: states the privacy stance, then captures the three things the
/// Coach engine needs (goal, experience, units) so the very first Home view is
/// already personalized. Skippable; never gates on a permission.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var flow = OnboardingModel()

    var body: some View {
        @Bindable var flow = flow
        return VStack(spacing: 0) {
            header
            TabView(selection: $flow.step) {
                welcomePage.tag(0)
                trainingPage.tag(1)
                setupPage.tag(2)
                programPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: flow.step)
            footer
        }
        .interactiveDismissDisabled()
        .onAppear {
            flow.goal = settings.trainingGoal
            flow.experience = settings.experienceLevel
            flow.preferredWorkoutStyle = settings.preferredWorkoutStyle
            flow.unit = settings.unit
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            if flow.canGoBack {
                Button { Haptics.selection(); withAnimation { flow.back() } } label: {
                    Image(systemName: "chevron.left").font(.headline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.back")
                .accessibilityLabel("Back")
            }
            Spacer()
            Button("Skip") { Haptics.selection(); finish() }
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding.skip")
        }
        .padding(.horizontal).padding(.top, 8).frame(height: 32)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            Button {
                Haptics.selection()
                switch flow.primaryAction {
                case .complete:
                    finish()
                case .advance:
                    withAnimation { flow.advance() }
                }
            } label: {
                Text(flow.footerTitle)
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(flow.isLastStep ? AnyShapeStyle(.green) : AnyShapeStyle(.tint),
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.primary")

            if flow.isLastStep {
                Button("Maybe later — explore the free app") { Haptics.selection(); finish() }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.exploreFree")
            }

            PageDots(count: flow.lastStep + 1, index: flow.step)
        }
        .padding(.horizontal).padding(.bottom, 12)
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "lock.fill")
                .scaledSystemFont(34, relativeTo: .largeTitle).foregroundStyle(.tint)
                .frame(width: 72, height: 72)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            Text("Free and open source").font(.title.bold()).padding(.top, 22)
            Text("A private strength coach built on cited sport science, with no account or paywall.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 14) {
                valueRow("checkmark.circle.fill", "Free forever. No ads. No account. No tracking.")
                valueRow("iphone", "Your data stays on your iPhone")
                valueRow("book.closed", "Every recommendation is sourced")
            }
            CitationLink(citation: CitationRegistry.volumeDoseResponse,
                         context: "Read the science behind coaching", compact: true)
                .padding(.top, 12)
            .padding(.top, 28)
            Text("Location is used only while you're recording an outdoor run, walk, or ride you start — it maps your route in the background (shown by the blue status bar) and stops the moment you finish. Never at any other time.")
                .font(.caption2).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22).padding(.horizontal, 8)
            Spacer(); Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var trainingPage: some View {
        pageScaffold(title: "What are you training for?",
                     subtitle: "These defaults shape your first workout. You can change them anytime in Coach settings.") {
            ForEach(TrainingGoal.allCases) { g in
                selectCard(title: g.displayName, subtitle: g.summary,
                           systemImage: goalSymbol(g), selected: flow.goal == g) { flow.goal = g }
            }
            Divider().padding(.vertical, 4)
            Text("Training experience").font(.subheadline.weight(.medium))
            ForEach(ExperienceLevel.allCases) { e in
                selectCard(title: e.displayName, subtitle: e.summary,
                           systemImage: experienceSymbol(e), selected: flow.experience == e) { flow.experience = e }
            }
            Divider().padding(.vertical, 4)
            Text("Workout style").font(.subheadline.weight(.medium))
            ForEach([SuggestedWorkoutStyle.fitness, .bodyweight, .powerlifting, .olympic, .strongman], id: \.self) { style in
                selectCard(title: style == .olympic ? "Olympic" : style.displayName,
                           subtitle: style.subtitle, systemImage: workoutTypeSymbol(style),
                           selected: flow.preferredWorkoutStyle == style) {
                    flow.preferredWorkoutStyle = style
                }
            }
        }
    }

    private var setupPage: some View {
        @Bindable var flow = flow
        return pageScaffold(title: "Make it fit your week",
                            subtitle: "Cladiron starts with a sensible plan and learns from what you actually complete.") {
            Text("Strength days per week").font(.subheadline.weight(.medium))
            Picker("Strength days", selection: $flow.strengthDays) {
                ForEach(2...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.strengthDays")
            Text("Cardio days per week").font(.subheadline.weight(.medium)).padding(.top, 4)
            Picker("Cardio days", selection: $flow.cardioDays) {
                ForEach(0...6, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.cardioDays")
            Divider().padding(.vertical, 4)
            Text("Units").font(.subheadline.weight(.medium))
            Picker("Units", selection: $flow.unit) {
                Text("Pounds (lb)").tag(MeasurementUnitPreference.pounds)
                Text("Kilograms (kg)").tag(MeasurementUnitPreference.kilograms)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.units")
            Text("Age is asked later when a heart-rate zone feature needs it.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func valueRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.green).frame(width: 26)
            Text(text).font(.subheadline)
            Spacer()
        }
    }

    private var programPage: some View {
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Here's today's workout").font(.title.bold()).padding(.top, 4)
                Text("A concrete starter plan, shown for your review before anything is started or saved.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    Label("Your first workout", systemImage: "wand.and.stars")
                        .font(.headline)
                    if let session = flow.previewPlan(formula: settings.formula).today?.sessions.first(where: { !$0.isRest }),
                       let exercises = session.exercises, !exercises.isEmpty {
                        ForEach(exercises.prefix(4), id: \.name) { exercise in
                            HStack {
                                Text(exercise.name).lineLimit(1)
                                Spacer()
                                Text("\(exercise.sets ?? 3) × \(exercise.repsLow ?? 8)")
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("A full-body strength session will be ready after you choose Start Workout.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text("Nothing starts or schedules automatically. You stay in control.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("onboarding.workoutFlowPreview")

                Text("Not medical advice. Learn more in Settings. Everything else in Cladiron — logging, history, trends, export — is free forever.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    private func pageScaffold<Content: View>(title: String, subtitle: String,
                                              @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.title.bold()).padding(.top, 4)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).padding(.bottom, 10)
                content()
            }
            .padding(.horizontal, 24).padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func selectCard(title: String, subtitle: String, systemImage: String,
                            selected: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage).font(.title2).frame(width: 30)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint) }
            }
            .padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.background.secondary),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.tint, lineWidth: selected ? 2 : 0))
        }
        .buttonStyle(.plain)
    }

    private func goalSymbol(_ g: TrainingGoal) -> String {
        switch g {
        case .strength:    "dumbbell.fill"
        case .hypertrophy: "figure.strengthtraining.traditional"
        case .endurance:   "figure.run"
        }
    }

    private func experienceSymbol(_ e: ExperienceLevel) -> String {
        switch e {
        case .beginner:     "leaf.fill"
        case .intermediate: "flame.fill"
        case .advanced:     "trophy.fill"
        }
    }

    private func workoutTypeSymbol(_ style: SuggestedWorkoutStyle) -> String {
        switch style {
        case .fitness: "dumbbell.fill"
        case .bodyweight: "figure.flexibility"
        case .powerlifting: "scalemass.fill"
        case .olympic: "figure.strengthtraining.traditional"
        case .strongman: "figure.strengthtraining.functional"
        case .personalized: "sparkles"
        }
    }

    private func finish() {
        settings.trainingGoal = flow.goal
        settings.experienceLevel = flow.experience
        settings.preferredWorkoutStyle = flow.preferredWorkoutStyle
        settings.unit = flow.unit
        settings.coachSchedulePreferences = flow.schedulePreferences
        settings.hasCompletedOnboarding = true
        // Persist age only if the user set it; otherwise leave nil so the HR-zone
        // estimator uses its 40-year default (US median).
        if let age = flow.persistedAge { settings.userAge = age }
        dismiss()
    }
}

private struct PageDots: View {
    let count: Int
    let index: Int
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .frame(width: i == index ? 18 : 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}
