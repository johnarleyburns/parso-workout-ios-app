import SwiftUI
import CadenceCore

/// First-run flow: states the privacy stance, then captures the three things the
/// Coach engine needs (goal, experience, units) so the very first Home view is
/// already personalized. Skippable; never gates on a permission.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var goal: TrainingGoal = .strength
    @State private var experience: ExperienceLevel = .intermediate
    @State private var unit: MeasurementUnitPreference = .pounds
    @State private var healthRequested = false

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $step) {
                welcomePage.tag(0)
                goalPage.tag(1)
                experiencePage.tag(2)
                unitsPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: step)
            footer
        }
        .interactiveDismissDisabled()
        .onAppear {
            goal = settings.trainingGoal
            experience = settings.experienceLevel
            unit = settings.unit
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack {
            if step > 0 {
                Button { Haptics.selection(); withAnimation { step -= 1 } } label: {
                    Image(systemName: "chevron.left").font(.headline)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.back")
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
                if step < lastStep { withAnimation { step += 1 } } else { finish() }
            } label: {
                Text(step < lastStep ? "Continue" : "Start training")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(step < lastStep ? AnyShapeStyle(.tint) : AnyShapeStyle(.green),
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding.primary")
            PageDots(count: lastStep + 1, index: step)
        }
        .padding(.horizontal).padding(.bottom, 12)
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 34)).foregroundStyle(.tint)
                .frame(width: 72, height: 72)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
            Text("Private by design").font(.title.bold()).padding(.top, 22)
            Text("A strength coach built on cited sport science — that never asks you to give anything up.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.top, 8).padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 14) {
                valueRow("checkmark.circle.fill", "No ads, no account, no subscription")
                valueRow("iphone", "Your data stays on your iPhone")
                valueRow("book.closed", "Every recommendation is sourced")
            }
            .padding(.top, 28)
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
                           systemImage: goalSymbol(g), selected: goal == g) { goal = g }
            }
        }
    }

    private var experiencePage: some View {
        pageScaffold(title: "How much training behind you?",
                     subtitle: "Sets your starting weekly volume.") {
            ForEach(ExperienceLevel.allCases) { e in
                selectCard(title: e.displayName, subtitle: e.summary,
                           systemImage: experienceSymbol(e), selected: experience == e) { experience = e }
            }
        }
    }

    private var unitsPage: some View {
        pageScaffold(title: "One last thing",
                     subtitle: "You can change these anytime in Settings.") {
            Text("Units").font(.subheadline.weight(.medium))
            Picker("Units", selection: $unit) {
                Text("Pounds (lb)").tag(MeasurementUnitPreference.pounds)
                Text("Kilograms (kg)").tag(MeasurementUnitPreference.kilograms)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("onboarding.units")

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
        settings.trainingGoal = goal
        settings.experienceLevel = experience
        settings.unit = unit
        settings.hasCompletedOnboarding = true
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
