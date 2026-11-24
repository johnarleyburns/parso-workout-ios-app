import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Watch redesign §5 S1–S5 — the Set Card. Replaces the 12-control scrolling keypad: two big
/// pre-filled numbers, exercise progress, one button. The Crown adjusts the outlined number (weight by
/// default, D-W4); Double Tap logs. The "…" at the top opens RPE entry directly; the bottom bar's
/// − / + step the focused number by the same amount the Crown does.
struct WatchSetKeypadView: View {
    @Bindable var bindableModel: WatchStrengthFlowModel
    var model: WatchStrengthFlowModel { bindableModel }

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var focus: WatchSetCardField = .weight
    @State private var showingMore = false
    @State private var showingLifters = false
    @State private var isLogging = false
    @State private var toastLastTime: String?
    @State private var showingExerciseInfo = false

    init(model: WatchStrengthFlowModel) {
        self.bindableModel = model
    }

    private var increment: WeightIncrement { WeightIncrement(unit: model.unit) }

    var body: some View {
        if let card = model.setCardState {
            VStack(spacing: CGFloat(WatchSetEntryPresentation.headerSpacing)) {
                HStack(spacing: 6) {
                    WatchExerciseProgressRing(presentation: card.exerciseProgress)
                    Text(card.exerciseName.localizedExerciseName)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(card.exerciseProgress.accessibilityLabel)
                        .accessibilityAddTraits(.isHeader)
                }
                if card.lifterText != nil {
                  HStack(spacing: 6) {
                    if let lifter = card.lifterText {
                        Spacer(minLength: 0)
                        Button { showingLifters = true } label: {
                            Label(lifter, systemImage: "person.fill")
                                .font(.caption2.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 7).padding(.vertical, 1)
                                .background(Capsule().fill(WatchTone.accentSoft))
                                .foregroundStyle(WatchTone.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("watchStrength.lifterChip")
                        .accessibilityHint(Text("Choose who lifts next"))
                    }
                  }
                }
                fields(card)
                    .padding(.top, CGFloat(WatchSetEntryPresentation.fieldTopSpacing))
            }
            .padding(.horizontal, 4)
            // Keep the title, exercise name, and fields together at the top;
            // the default pager centering left a large empty band below them.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // "Last time" is a transient toast so it never pushes the weight/reps rows into the title.
            .overlay(alignment: .top) {
                if let toastLastTime {
                    Text(toastLastTime)
                        .font(.caption2).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.regularMaterial))
                        .transition(.opacity)
                        .accessibilityIdentifier("watchSet.lastTimeToast")
                }
            }
            .task(id: card.lastTimeText) {
                guard let last = card.lastTimeText else { toastLastTime = nil; return }
                withAnimation { toastLastTime = last }
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                withAnimation { toastLastTime = nil }
            }
            .navigationBarTitleDisplayMode(.inline)
            .focusable()
            .digitalCrownRotation(crownBinding, from: crownRange.lowerBound, through: crownRange.upperBound,
                                  by: WatchSetCardMetricLayout.crownStep(weightFocused: focus == .weight,
                                                                       nonWeighted: card.isNonWeighted),
                                  sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingMore = true } label: {
                        Text("RPE")
                    }
                    .accessibilityLabel(Text("RPE"))
                    .accessibilityIdentifier("watchSet.more")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(context.date, format: .dateTime.hour().minute())
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .accessibilityIdentifier("watchSet.clock")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingExerciseInfo = true } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel(Text("Exercise info"))
                    .accessibilityIdentifier("watchSet.exerciseInfo")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    let isWeight = focus == .weight && !card.isNonWeighted
                    let amount = isWeight ? WatchSetCardMetricLayout.buttonWeightStep(unit: model.unit) : 1
                    Button { adjustFocusedValue(by: -amount) } label: {
                        Image(systemName: "minus")
                    }
                    .accessibilityLabel("Subtract \(stepText(amount)) \(isWeight ? card.unitText : "reps")")
                    .accessibilityIdentifier(isWeight ? "watchWeight.minus" : "watchReps.minus")
                    Spacer()
                    if !isLuminanceReduced {
                        logButton(card)
                    }
                    Spacer()
                    Button { adjustFocusedValue(by: amount) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add \(stepText(amount)) \(isWeight ? card.unitText : "reps")")
                    .accessibilityIdentifier(isWeight ? "watchWeight.plus" : "watchReps.plus")
                }
            }
            .sheet(isPresented: $showingMore) {
                NavigationStack { WatchRPEPickerSheet(onSelect: selectRPE) }
            }
            .sheet(isPresented: $showingLifters) {
                NavigationStack { WatchPartnersView(model: model) }
            }
            .sheet(isPresented: $showingExerciseInfo) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if let exercise = currentExercise {
                                WatchExerciseDetailContent(exercise: exercise)
                            } else {
                                Text("No exercise details available")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .navigationTitle(card.exerciseName.localizedExerciseName)
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .accessibilityAction(named: Text("Log set")) { log() }
            .accessibilityAction(named: Text("RPE")) { showingMore = true }
        }
    }

    // MARK: Fields

    @ViewBuilder
    private func fields(_ card: WatchSetCardState) -> some View {
        let weight = WatchMetricField(value: card.weightText, unit: card.unitText, isFocused: focus == .weight,
                                      accessibilityName: Text("Weight"),
                                      hint: Text("Select weight, then use the plus and minus buttons or turn the Digital Crown"),
                                      onFocus: { focus = .weight })
            .accessibilityIdentifier("watchWeight.current")
        let reps = WatchMetricField(value: "\(card.reps)", unit: String(localized: "rps"), isFocused: focus == .reps || card.isNonWeighted,
                                    accessibilityName: Text("Reps"),
                                    hint: Text("Select reps, then use the plus and minus buttons or turn the Digital Crown"),
                                    onFocus: { focus = .reps })
            .accessibilityIdentifier("watchReps.current")
        if card.isNonWeighted {
            HStack(spacing: 4) {
                Text(card.weightText == "BW" ? "BW" : "Non-\nWeighted")
                    .font(.caption2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel(card.weightText == "BW" ? "Bodyweight, no external load" : "Non-weighted movement")
                    .accessibilityIdentifier("watchSet.nonWeighted")
                reps
            }
        } else if WatchSetCardMetricLayout.fields(isAccessibilitySize: dynamicTypeSize >= .accessibility1) == .stacked {
            VStack(spacing: 4) { weight; reps }
        } else {
            HStack(spacing: 4) { weight; reps }
        }
    }

    private func adjustFocusedValue(by amount: Double) {
        if focus == .weight && !isCurrentExerciseNonWeighted {
            bindableModel.currentWeightDisplay = min(increment.range.upperBound,
                                                      max(increment.range.lowerBound, model.currentWeightDisplay + amount))
        } else {
            bindableModel.currentReps = min(100, max(1, model.currentReps + amount))
        }
        WatchHaptics.tap()
    }

    private func stepText(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func selectRPE(_ choice: Int?) {
        WatchHaptics.tap()
        var mode = model.effortMode
        var value = model.effortValue
        WatchRPESelection.apply(choice, mode: &mode, value: &value)
        model.effortMode = mode
        model.effortValue = value
        showingMore = false
    }

    private var crownBinding: Binding<Double> {
        focus == .weight && !isCurrentExerciseNonWeighted
            ? $bindableModel.currentWeightDisplay
            : $bindableModel.currentReps
    }

    private var crownRange: ClosedRange<Double> {
        focus == .weight && !isCurrentExerciseNonWeighted ? increment.range : 1...100
    }

    private var isCurrentExerciseNonWeighted: Bool {
        guard case .keypad(let exercise) = model.stage else { return false }
        return SessionViewModel.isNonWeighted(exercise)
    }

    private var currentExercise: Exercise? {
        guard case .keypad(let exercise) = model.stage else { return nil }
        return exercise
    }

    // MARK: Log (tap / Double Tap)

    private func logButton(_ card: WatchSetCardState) -> some View {
        Button {
            log()
        } label: {
            Group {
                if isLogging {
                    ProgressView()
                } else {
                    Image(systemName: WatchSetEntryPresentation.logButtonSystemImage)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(WatchTone.accent)
                }
            }
            // Bare green checkbox: the toolbar already gives it a 44 pt hit area,
            // without a capsule/box around it.
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .disabled(isLogging)
        .handGestureShortcut(.primaryAction)
        .accessibilityLabel(Text(card.logTitle))
        .accessibilityIdentifier("logSetButton")
    }

    private func log() {
        guard !isLogging else { return }
        isLogging = true
        WatchHaptics.success()
        DispatchQueue.main.async {
            if model.logSet() != nil, let payload = model.lastSyncPayload {
                WatchSyncSender.send(payload)
            }
            isLogging = false
        }
    }
}
