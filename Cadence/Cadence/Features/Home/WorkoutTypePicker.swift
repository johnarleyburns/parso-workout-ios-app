import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

struct WorkoutTypePicker: View {
    let onSelect: (WorkoutType) -> Void
    let onEditorStart: (EditablePlan) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    var onSuggestedWorkout: (() -> Void)? = nil
    var types: [WorkoutType] = WorkoutType.allCases
    var title: String = "Start Workout"
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 16),
                           GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(types) { type in
                        switch type {
                        case .weights:
                            NavigationLink {
                                WeightsStartView(onEditorStart: onEditorStart,
                                                 onSuggestedWorkout: {
                                                    dismiss()
                                                    onSuggestedWorkout?()
                                                 })
                            } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain)
                                .tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        case .other:
                            NavigationLink {
                                OtherCardioEntryView(onStart: onOtherCardio)
                            } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain)
                                .tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        default:
                            Button { onSelect(type) } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain)
                                .tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("startType.cancel")
                }
            }
        }
    }
}

/// Unified entry sheet for Home. Strength choices are deliberately explicit;
/// cardio keeps the existing downstream setup and recorder routes.
struct SelectWorkoutView: View {
    let onQuickStart: () -> Void
    let onSuggestedWorkout: () -> Void
    let onEditorStart: (EditablePlan) -> Void
    let onSelect: (WorkoutType) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    var recentCardioTypes: [WorkoutType] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var cardioChoicesExpanded = false
    @State private var moreStrengthExpanded = false

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.sectionSpacing)) {
                    strengthCard
                    cardioCard
                }
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

                Button(action: onSuggestedWorkout) {
                    workoutChoiceLabel("Personalized Workout", symbol: "wand.and.stars")
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
                        Button { onSelect(type) } label: {
                            WorkoutHero(type: type)
                        }
                        .buttonStyle(.plain)
                        .tapHaptic()
                        .accessibilityIdentifier("startType.\(type.rawValue)")
                        .accessibilityLabel(type.displayName)
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
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("selectWorkout.cardioChoices")
            if cardioChoicesExpanded {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(additionalCardioTypes) { type in
                            Button { onSelect(type) } label: { WorkoutHero(type: type) }
                                .buttonStyle(.plain).tapHaptic()
                                .accessibilityIdentifier("startType.\(type.rawValue)")
                                .accessibilityLabel(type.displayName)
                        }
                        NavigationLink { OtherCardioEntryView(onStart: onOtherCardio) } label: {
                            WorkoutHero(type: .other)
                        }
                        .buttonStyle(.plain).tapHaptic()
                        .accessibilityIdentifier("startType.other")
                        .accessibilityLabel("Other Cardio")
                    }
            }
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .blue)
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

private struct PreviousWorkoutsView: View {
    let onEditorStart: (EditablePlan) -> Void

    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    private var previous: [WorkoutSession] {
        Array(sessions.filter { !$0.orderedSets.isEmpty && $0.deletedAt == nil }.prefix(20))
    }

    var body: some View {
        List {
            if previous.isEmpty {
                ContentUnavailableView("No previous workouts", systemImage: "clock.arrow.circlepath",
                                       description: Text("Complete a strength workout to reuse it as a template."))
            } else {
                ForEach(previous) { session in
                    NavigationLink {
                        WorkoutPlanEditor(plan: .from(session: session), onStart: onEditorStart)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.title.isEmpty ? "Previous Workout" : session.title)
                                .font(.headline)
                            Text("\(session.date.formatted(date: .abbreviated, time: .omitted)) · \(session.exercisesInOrder.count) exercises · \(session.orderedSets.count) sets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("selectWorkout.previous")
                    .accessibilityValue(session.id.uuidString)
                }
            }
        }
        .navigationTitle("Previous Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("selectWorkout.previousList")
    }
}

struct WorkoutHero: View {
    let type: WorkoutType

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            gradient
            if let ui = UIImage(named: "hero-\(type.rawValue)") {
                Image(uiImage: ui).resizable().scaledToFill()
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.5)],
                                            startPoint: .top, endPoint: .bottom))
            }
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: type.symbol).scaledSystemFont(30, relativeTo: .title, weight: .bold)
                Text(type.displayName).font(.title3.bold())
            }
            .foregroundStyle(.white)
            .padding(12)
            .cadenceGlassIfAvailable(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                interactive: true)
            .padding(2)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var gradient: some View {
        LinearGradient(colors: Self.colors(type), startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func colors(_ type: WorkoutType) -> [Color] {
        switch type {
        case .weights: return [.indigo, .purple]
        case .run: return [.blue, .teal]
        case .walk: return [.teal, .green]
        case .cycle: return [.orange, .yellow]
        case .rowing: return [.purple, .indigo]
        case .swim: return [.cyan, .blue]
        case .elliptical: return [.mint, .teal]
        case .stairClimber: return [.orange, .red]
        case .hiit: return [.pink, .red]
        case .boxing: return [.red, .orange]
        case .other: return [.gray, .blue]
        }
    }
}
