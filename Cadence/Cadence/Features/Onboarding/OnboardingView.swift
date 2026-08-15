import SwiftUI
import CadenceCore
import CadenceFeatures

/// First-run flow: states the privacy stance, then captures the three things the
/// Coach engine needs (goal, experience, units) so the very first Home view is
/// already personalized. Skippable; never gates on a permission.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var flow = OnboardingModel()
    @State private var healthRequested = false

    var body: some View {
        @Bindable var flow = flow
        return VStack(spacing: 0) {
            header
            TabView(selection: $flow.step) {
                welcomePage.tag(0)
                goalPage.tag(1)
                experiencePage.tag(2)
                schedulePage.tag(3)
                unitsPage.tag(4)
                disclaimerPage.tag(5)
                programPage.tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: flow.step)
            footer
        }
        .interactiveDismissDisabled()
        .onAppear {
            flow.goal = settings.trainingGoal
            flow.experience = settings.experienceLevel
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
                    .background(flow.step == 5 || flow.isLastStep ? AnyShapeStyle(.green) : AnyShapeStyle(.tint),
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
            Text("Private by design").font(.title.bold()).padding(.top, 22)
            Text("A strength coach built on cited sport science — that never asks you to give anything up.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 14) {
                valueRow("checkmark.circle.fill", "No ads. No account. No tracking.")
                valueRow("iphone", "Your data stays on your iPhone")
                valueRow("book.closed", "Every recommendation is sourced")
            }
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

    private func valueRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.green).frame(width: 26)
            Text(text).font(.subheadline)
            Spacer()
        }
    }

    private var goalPage: some View {
        pageScaffold(title: "What are you training for?",
                     subtitle: "This shapes your rep ranges and loads.") {
            ForEach(TrainingGoal.allCases) { g in
                selectCard(title: g.displayName, subtitle: g.summary,
                           systemImage: goalSymbol(g), selected: flow.goal == g) { flow.goal = g }
            }
        }
    }

    private var experiencePage: some View {
        pageScaffold(title: "How much training behind you?",
                     subtitle: "Sets your starting weekly volume.") {
            ForEach(ExperienceLevel.allCases) { e in
                selectCard(title: e.displayName, subtitle: e.summary,
                           systemImage: experienceSymbol(e), selected: flow.experience == e) { flow.experience = e }
            }
        }
    }

    private var schedulePage: some View {
        @Bindable var flow = flow
        return pageScaffold(title: "How often do you train?",
                     subtitle: "You can fine-tune rest days and two-a-days in preferences.") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Strength days per week").font(.subheadline.weight(.medium))
                Picker("Strength days", selection: $flow.strengthDays) {
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                    Text("5").tag(5)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("onboarding.strengthDays")

                Text("Cardio days per week").font(.subheadline.weight(.medium))
                Picker("Cardio days", selection: $flow.cardioDays) {
                    Text("0").tag(0)
                    Text("1").tag(1)
                    Text("2").tag(2)
                    Text("3").tag(3)
                    Text("4").tag(4)
                    Text("5").tag(5)
                    Text("6").tag(6)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("onboarding.cardioDays")
            }
        }
    }

    private var unitsPage: some View {
        @Bindable var flow = flow
        return pageScaffold(title: "One last thing",
                     subtitle: "You can change these anytime in Settings.") {
            Text("Units").font(.subheadline.weight(.medium))
            Picker("Units", selection: $flow.unit) {
                Text("Pounds (lb)").tag(MeasurementUnitPreference.pounds)
                Text("Kilograms (kg)").tag(MeasurementUnitPreference.kilograms)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.units")

            // Optional age for HR-zone estimation (issue 7). Skippable → defaults 40.
            VStack(alignment: .leading, spacing: 6) {
                Text("Age (optional)").font(.subheadline.weight(.medium))
                Stepper(value: $flow.age, in: 13...100, onEditingChanged: { _ in flow.ageProvided = true }) {
                    HStack {
                        Text("Used to estimate heart-rate zones")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(flow.ageProvided ? "\(flow.age)" : "—").monospacedDigit()
                    }
                }
                .accessibilityIdentifier("onboarding.age")
            }
            .padding(.top, 8)

            Button {
                Task { _ = await model.health.requestAuthorization(); healthRequested = true }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "heart.fill").font(.title2).foregroundStyle(.pink).frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect Apple Health").font(.headline)
                        Text("Pull in steps & past workouts. Optional.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: healthRequested ? "checkmark.circle.fill" : "chevron.right")
                        .font(healthRequested ? .body : .caption)
                        .foregroundStyle(healthRequested ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .accessibilityIdentifier("onboarding.health")
        }
    }

    private var disclaimerPage: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "stethoscope")
                .scaledSystemFont(30, relativeTo: .largeTitle).foregroundStyle(.orange)
                .frame(width: 72, height: 72)
                .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            Text("Coaching, not medical advice")
                .font(.title2.bold()).padding(.top, 22)
            Text("Cladiron's assessments and recommendations are general training guidance, not medical advice, diagnosis, or treatment. Consult a qualified professional before starting or changing an exercise program.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(); Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var programPage: some View {
        let days = flow.previewPlan(formula: settings.formula).days.filter { !$0.sessions.isEmpty }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your program is ready").font(.title.bold()).padding(.top, 4)
                Text("Built from your goals and schedule. The Coach fills in the exact sets, reps, and loads — then adapts them to what you log, and cites the research for every call.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if days.isEmpty {
                    Text("A balanced week tuned to your \(flow.goal.displayName.lowercased()) goal.")
                        .font(.subheadline)
                        .padding().frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                            if index > 0 { Divider().padding(.leading, 38) }
                            CoachPlanDayRow(day: day)
                        }
                    }
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("onboarding.programPreview")
                }

                Text("Everything else in Cladiron — logging, history, trends, export — is free forever.")
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

    private func finish() {
        settings.trainingGoal = flow.goal
        settings.experienceLevel = flow.experience
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
