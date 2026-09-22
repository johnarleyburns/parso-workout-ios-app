import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Unified entry sheet for Home. Strength choices are deliberately explicit;
/// cardio keeps the existing downstream setup and recorder routes.
struct SelectWorkoutView: View {
    let onQuickStart: () -> Void
    let onSuggestedWorkout: (SuggestedWorkoutModality) -> Void
    let onEditorStart: (EditablePlan) -> Void
    let onScheduleStrength: () -> Void
    let onLogWorkout: () -> Void
    let onScheduleCardio: (WorkoutType) -> Void
    let onSelect: (WorkoutType) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    var recentCardioTypes: [WorkoutType] = []
    var inline = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var cardioChoicesExpanded = false
    @State private var moreStrengthExpanded = false
    @State private var moreWaysExpanded = false

    private let cardioTypes: [WorkoutType] = [.run, .walk, .cycle, .rowing, .swim,
                                               .elliptical, .stairClimber, .hiit, .boxing]
    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    private var initialCardioTypes: [WorkoutType] {
        CardioStartChoicesPresenter.initial(recent: recentCardioTypes, all: cardioTypes)
    }

    private var additionalCardioTypes: [WorkoutType] {
        CardioStartChoicesPresenter.remaining(initial: initialCardioTypes, all: cardioTypes)
    }

    var body: some View {
        if inline {
            VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.sectionSpacing)) {
                Text("Start Workout")
                    .font(.headline)
                    .accessibilityIdentifier("home.startWorkout.title")
                inlineOptionsContent
            }
            .accessibilityIdentifier("home.startWorkout")
        } else {
            NavigationStack {
                ScrollView {
                    optionsContent
                        .padding(CGFloat(LayoutMetrics.pagePadding))
                }
                .navigationTitle("Start Workout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .accessibilityIdentifier("selectWorkout.cancel")
                    }
                }
            }
        }
    }

    /// Today stays focused on the two common actions. The full start catalog
    /// remains one tap away, but does not push My Workouts below the fold.
    private var inlineOptionsContent: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
            NavigationLink {
                WorkoutForYouModalityView(onSelect: onSuggestedWorkout)
            } label: {
                workoutChoiceLabel("Workout for You", symbol: "wand.and.stars")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("selectWorkout.suggestWorkout")

            Button(action: onQuickStart) {
                Label("Quick Start", systemImage: "bolt.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: CGFloat(LayoutMetrics.actionButtonHeight))
                    .background(Color.accentColor.opacity(0.12), in: CadenceActionShape.rounded)
                    .overlay(CadenceActionShape.rounded.stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("selectWorkout.quickStart")

            Button {
                withAnimation(.easeInOut(duration: 0.18)) { moreWaysExpanded.toggle() }
            } label: {
                HStack {
                    Text(moreWaysExpanded ? "Show fewer ways to start" : "More ways to start…")
                    Spacer()
                    Image(systemName: moreWaysExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, minHeight: CGFloat(LayoutMetrics.actionButtonHeight), alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("selectWorkout.moreWays")
            .accessibilityValue(moreWaysExpanded ? "Expanded" : "Collapsed")

            if moreWaysExpanded {
                VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                    NavigationLink {
                        WorkoutPlanEditor(
                            plan: .empty(warmup: settings.warmupMinutes, cooldown: settings.cooldownMinutes),
                            startInEditMode: true, onStart: onEditorStart)
                    } label: {
                        workoutChoiceLabel("Custom Workout", symbol: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selectWorkout.custom")

                    Button(action: onLogWorkout) {
                        workoutChoiceLabel("Log Workout", symbol: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selectWorkout.log")

                    Button(action: onScheduleStrength) {
                        workoutChoiceLabel("Schedule Workout", symbol: "calendar.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selectWorkout.schedule")

                    NavigationLink {
                        PreviousWorkoutsView(onEditorStart: onEditorStart)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Start from a previous workout…")
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, minHeight: CGFloat(LayoutMetrics.actionButtonHeight))
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("selectWorkout.previousLink")

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(initialCardioTypes) { type in cardioChoice(type) }
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { cardioChoicesExpanded.toggle() }
                    } label: {
                        HStack {
                            Text(cardioChoicesExpanded ? "Show less cardio" : "Show all cardio…")
                            Spacer()
                            Image(systemName: cardioChoicesExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, minHeight: CGFloat(LayoutMetrics.actionButtonHeight), alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selectWorkout.showAllCardio")
                    .accessibilityValue(cardioChoicesExpanded ? "Expanded" : "Collapsed")

                    if cardioChoicesExpanded {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(additionalCardioTypes) { type in cardioChoice(type) }
                            VStack(spacing: 4) {
                                NavigationLink { OtherCardioEntryView(onStart: onOtherCardio) } label: {
                                    WorkoutHero(type: .other, compact: true)
                                }
                                .buttonStyle(.plain).tapHaptic()
                                .accessibilityIdentifier("startType.other")
                                .accessibilityLabel("Other Cardio")
                                Button("Schedule Other") { onScheduleCardio(.other) }
                                    .font(.caption.weight(.semibold))
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.tint)
                                    .accessibilityIdentifier("scheduleType.other")
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var optionsContent: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.sectionSpacing)) {
            strengthCard
            cardioCard
        }
    }

    /// Home's card rhythm: heading, `cardHeadingSpacing`, then rows separated by
    /// `cardRowSpacing` (field test 2026-08-18 #5).
    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardHeadingSpacing)) {
            Text("Strength").font(.headline)
            VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                Button(action: onQuickStart) {
                    workoutChoiceLabel("Quick Start", symbol: "bolt.fill")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("selectWorkout.quickStart")

                NavigationLink {
                    WorkoutForYouModalityView(onSelect: onSuggestedWorkout)
                } label: {
                    workoutChoiceLabel("Workout for You", symbol: "wand.and.stars")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("selectWorkout.suggestWorkout")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { moreStrengthExpanded.toggle() }
                } label: {
                        HStack {
                        Text(moreStrengthExpanded ? "Show less" : "Show more…")
                        Spacer()
                        Image(systemName: moreStrengthExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("selectWorkout.moreStrength")

                if moreStrengthExpanded {
                    Button(action: onScheduleStrength) {
                        workoutChoiceLabel("Schedule Workout", symbol: "calendar.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selectWorkout.schedule")

                    Button(action: onLogWorkout) {
                        workoutChoiceLabel("Log Workout", symbol: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selectWorkout.log")

                    NavigationLink {
                        WorkoutPlanEditor(
                            plan: .empty(warmup: settings.warmupMinutes,
                                         cooldown: settings.cooldownMinutes),
                            startInEditMode: true,
                            onStart: onEditorStart)
                    } label: {
                        workoutChoiceLabel("Custom Workout", symbol: "slider.horizontal.3")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("selectWorkout.custom")

                    NavigationLink {
                        PreviousWorkoutsView(onEditorStart: onEditorStart)
                    } label: {
                        HStack(spacing: 4) {
                            Text("Start from a previous workout…")
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity,
                               minHeight: CGFloat(LayoutMetrics.actionButtonHeight))
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("selectWorkout.previousLink")
                }
            }
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
    }

    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardHeadingSpacing)) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cardio").font(.headline)
                Text("Choose a cardio workout when you need one.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(initialCardioTypes) { type in
                        cardioChoice(type)
                    }
            }
            Button {
                    withAnimation(.easeInOut(duration: 0.18)) { cardioChoicesExpanded.toggle() }
                } label: {
                    HStack {
                        Text(cardioChoicesExpanded ? "Show less" : "Show more…")
                        Spacer()
                        Image(systemName: cardioChoicesExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity,
                           minHeight: CGFloat(LayoutMetrics.actionButtonHeight))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("selectWorkout.cardioChoices")
            if cardioChoicesExpanded {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(additionalCardioTypes) { type in
                            cardioChoice(type)
                        }
                        VStack(spacing: 4) {
                            NavigationLink { OtherCardioEntryView(onStart: onOtherCardio) } label: {
                                WorkoutHero(type: .other, compact: true)
                            }
                            .buttonStyle(.plain).tapHaptic()
                            .accessibilityIdentifier("startType.other")
                            .accessibilityLabel("Other Cardio")
                            Button("Schedule Other") { onScheduleCardio(.other) }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.plain)
                                .foregroundStyle(.tint)
                                .accessibilityIdentifier("scheduleType.other")
                        }
                    }
            }
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .blue)
    }

    private func cardioChoice(_ type: WorkoutType) -> some View {
        VStack(spacing: 4) {
            Button { onSelect(type) } label: {
                WorkoutHero(type: type, compact: true)
            }
            .buttonStyle(.plain)
            .tapHaptic()
            .accessibilityIdentifier("startType.\(type.rawValue)")
            .accessibilityLabel(type.displayName)

            Button("Schedule \(type.displayName)") {
                onScheduleCardio(type)
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("scheduleType.\(type.rawValue)")
        }
    }

    /// Geometry comes from `cadenceActionLabel()` so these match Home's
    /// Start Workout and the plan editor exactly (field test 2026-08-18 #3);
    /// only the gradient fill is local.
    private func workoutChoiceLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.headline)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline).opacity(0.8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .cadenceActionLabel()
        .background(
            LinearGradient(colors: [.green, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: CadenceActionShape.rounded)
    }
}
