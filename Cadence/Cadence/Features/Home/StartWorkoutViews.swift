import SwiftUI
import CadenceCore
import CadenceFeatures

/// The single start hub exposed from Today. Recommendations and user-directed
/// workout choices intentionally live in separate sections so the next action
/// is always explicit.
struct StartWorkoutView: View {
    let onEditorStart: (EditablePlan) -> Void
    let onScheduleStrength: () -> Void
    let onLogWorkout: () -> Void
    let onStartCardio: (WorkoutType) -> Void
    let onScheduleCardio: (WorkoutType) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    let recentCardioTypes: [WorkoutType]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                actionSection(
                    title: "Pick Your Own Workout",
                    subtitle: "Choose exactly how you want to train today.") {
                        NavigationLink {
                            PickWorkoutView(
                                onEditorStart: onEditorStart,
                                onScheduleStrength: onScheduleStrength,
                                onLogWorkout: onLogWorkout)
                        } label: {
                            startActionLabel("Strength", symbol: "dumbbell.fill", tint: .green)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("startWorkout.pick.strength")

                        NavigationLink {
                            CardioPickerView(
                                mode: .start,
                                recentCardioTypes: recentCardioTypes,
                                onSelect: onStartCardio,
                                onSchedule: onScheduleCardio,
                                onOtherCardio: onOtherCardio)
                        } label: {
                            startActionLabel("Cardio", symbol: "figure.run", tint: .blue)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("startWorkout.pick.cardio")

                        NavigationLink {
                            TemplatesView(onStart: onEditorStart)
                        } label: {
                            startActionLabel("Saved workouts", symbol: "bookmark.fill", tint: .secondary)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("startWorkout.pick.saved")

                    }
            }
            .padding(CGFloat(LayoutMetrics.pagePadding))
        }
        .navigationTitle("Start Workout")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("startWorkout")
    }

    private func actionSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(CGFloat(LayoutMetrics.cardPadding))
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: CadenceCardShape.rounded, tint: .green)
    }

    private func startActionLabel(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.headline)
            Text(title).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline).opacity(0.8)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .tint(tint)
    }
}

/// User-directed strength choices. Recommendation generation deliberately does
/// not appear here; Today owns the reviewed coach suggestion.
struct PickWorkoutView: View {
    let onEditorStart: (EditablePlan) -> Void
    let onScheduleStrength: () -> Void
    let onLogWorkout: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                pickAction("Custom Workout", symbol: "slider.horizontal.3") {
                    WorkoutPlanEditor(
                        plan: .empty(warmup: settings.warmupMinutes,
                                     cooldown: settings.cooldownMinutes),
                        startInEditMode: true,
                        onStart: onEditorStart)
                }
                .accessibilityIdentifier("pickWorkout.custom")

                NavigationLink {
                    PreviousWorkoutsView(onEditorStart: onEditorStart)
                } label: {
                    pickActionLabel("Do a Previous Workout", symbol: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pickWorkout.previous")

                Button {
                    dismiss()
                    onScheduleStrength()
                } label: {
                    pickActionLabel("Schedule Workout", symbol: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pickWorkout.schedule")

                Button {
                    dismiss()
                    onLogWorkout()
                } label: {
                    pickActionLabel("Log Workout", symbol: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pickWorkout.log")
            }
            .padding(CGFloat(LayoutMetrics.pagePadding))
        }
        .navigationTitle("Pick Workout")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("pickWorkout")
    }

    private func pickAction<Destination: View>(
        _ title: String,
        symbol: String,
        @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink { destination() } label: {
            pickActionLabel(title, symbol: symbol)
        }
        .buttonStyle(.bordered)
    }

    private func pickActionLabel(_ title: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.headline)
            Text(title).font(.headline)
            Spacer()
            Image(systemName: "chevron.right").font(.subheadline).opacity(0.8)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
        .cadenceActionLabel()
    }
}

enum CardioPickerMode: Equatable {
    case start
    case schedule
}

/// Shared cardio choice surface. Start mode has no schedule controls on the
/// cardio tiles; scheduling is a separate intent reached by the bottom action.
struct CardioPickerView: View {
    let mode: CardioPickerMode
    let recentCardioTypes: [WorkoutType]
    let onSelect: (WorkoutType) -> Void
    let onSchedule: (WorkoutType) -> Void
    let onOtherCardio: (_ description: String, _ gps: Bool) -> Void
    @State private var expanded = false
    @Environment(\.dismiss) private var dismiss

    private let cardioTypes: [WorkoutType] = [
        .run, .walk, .cycle, .rowing, .swim, .elliptical, .stairClimber,
        .hiit, .boxing, .other
    ]
    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    private var initialTypes: [WorkoutType] {
        CardioStartChoicesPresenter.initial(recent: recentCardioTypes,
                                            all: cardioTypes.filter { $0 != .other })
    }

    private var additionalTypes: [WorkoutType] {
        CardioStartChoicesPresenter.remaining(initial: initialTypes, all: cardioTypes)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(initialTypes) { type in cardioChoice(type) }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                } label: {
                    HStack {
                        Text(expanded ? "Show less" : "Show more…")
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(maxWidth: .infinity,
                           minHeight: CGFloat(LayoutMetrics.actionButtonHeight))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cardioPicker.showMore")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")

                if expanded {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(additionalTypes.filter { $0 != .other }) { type in
                            cardioChoice(type)
                        }
                        otherCardioChoice
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

            }
            .padding(CGFloat(LayoutMetrics.pagePadding))
        }
        .navigationTitle(mode == .start ? "Cardio" : "Schedule Cardio")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(mode == .start ? "cardioPicker" : "cardioPicker.scheduleMode")
    }

    private func cardioChoice(_ type: WorkoutType) -> some View {
        Button {
            dismiss()
            if mode == .start { onSelect(type) } else { onSchedule(type) }
        } label: {
            WorkoutHero(type: type, compact: true)
        }
        .buttonStyle(.plain)
        .tapHaptic()
        .accessibilityIdentifier("cardioPicker.\(mode == .start ? "start" : "schedule").\(type.rawValue)")
        .accessibilityLabel(mode == .start ? "Start \(type.displayName)" : "Schedule \(type.displayName)")
    }

    @ViewBuilder
    private var otherCardioChoice: some View {
        if mode == .start {
            NavigationLink { OtherCardioEntryView(onStart: onOtherCardio) } label: {
                WorkoutHero(type: .other, compact: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cardioPicker.start.other")
        } else {
            Button {
                dismiss()
                onSchedule(.other)
            } label: {
                WorkoutHero(type: .other, compact: true)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cardioPicker.schedule.other")
        }
    }
}
