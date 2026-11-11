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
    /// Home's cached weekly cardio credit, shown at the top of the Cardio picker.
    let weeklyCardioCredit: CardioWeeklyCreditDisplay
    var onFillGaps: (() -> Void)? = nil
    var onSuggestCardio: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                actionSection(
                    title: String(localized: "Pick Your Own Workout"),
                    subtitle: String(localized: "Choose exactly how you want to train today.")) {
                        NavigationLink {
                            PickWorkoutView(
                                onEditorStart: onEditorStart,
                                onScheduleStrength: onScheduleStrength,
                                onLogWorkout: onLogWorkout,
                                onFillGaps: onFillGaps)
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
                                onOtherCardio: onOtherCardio,
                                onSuggestCardio: onSuggestCardio,
                                weeklyCredit: weeklyCardioCredit)
                        } label: {
                            startActionLabel("Cardio", symbol: "figure.run", tint: .blue)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("startWorkout.pick.cardio")

                        NavigationLink {
                            TemplatesView(onStart: onEditorStart)
                        } label: {
                            startActionLabel(String(localized: "Saved workouts"), symbol: "bookmark.fill", tint: .secondary)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("startWorkout.pick.saved")

                        NavigationLink {
                            SendCardioToWatchView()
                        } label: {
                            startActionLabel(String(localized: "Send cardio to Watch"), symbol: "applewatch", tint: .blue)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("startWorkout.pick.sendCardioToWatch")

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
    var onFillGaps: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                // Shortcut to the muscle-coverage "Fill the gaps" flow, which
                // builds a workout from this week's least-trained groups.
                Button {
                    onFillGaps?()
                } label: {
                    pickActionLabel(String(localized: "Suggest a workout"), symbol: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pickWorkout.suggestWorkout")

                pickAction(String(localized: "Custom Workout"), symbol: "slider.horizontal.3") {
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
                    pickActionLabel(String(localized: "Do a Previous Workout"), symbol: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pickWorkout.previous")

                Button {
                    dismiss()
                    onScheduleStrength()
                } label: {
                    pickActionLabel(String(localized: "Schedule Workout"), symbol: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("pickWorkout.schedule")

                Button {
                    dismiss()
                    onLogWorkout()
                } label: {
                    pickActionLabel(String(localized: "Log Workout"), symbol: "square.and.pencil")
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

/// Designs a cardio workout on the phone and sends it to the Watch's "Sent from your phone" list.
/// Strength workouts are sent from their editor ("Send Workout to Watch").
struct SendCardioToWatchView: View {
    @Environment(AppModel.self) private var model
    @State private var type: CardioType = .run
    @State private var minutes = 30
    @State private var result: Bool?

    private let types: [CardioType] = CardioType.allCases.filter { $0 != .other }

    var body: some View {
        Form {
            Picker("Type", selection: $type) {
                ForEach(types) { Text($0.displayName).tag($0) }
            }
            Stepper("\(minutes) min", value: $minutes, in: 5...240, step: 5)
            Section {
                Button {
                    let workout = WatchSentWorkouts.cardioSession(
                        title: type.displayName, cardioType: type.rawValue, durationMinutes: minutes)
                    result = model.sendWorkoutToWatch(workout)
                } label: {
                    Label("Send Workout to Watch", systemImage: "applewatch")
                }
                .accessibilityIdentifier("sendCardio.send")
            } footer: {
                Text("It appears on your Watch under Sent from your phone. You start it there, and it leaves that list once started.")
            }
            if let result {
                Text(result ? "Sent to your Watch." : "Couldn't reach a paired Apple Watch with Cladiron installed.")
                    .font(.footnote)
                    .foregroundStyle(result ? Color.secondary : Color.red)
                    .accessibilityIdentifier("sendCardio.result")
            }
        }
        .navigationTitle("Send to Watch")
        .navigationBarTitleDisplayMode(.inline)
    }
}
