import SwiftUI
import WatchKit
import CadenceCore
import CadenceFeatures

/// Watch redesign §5 S1–S5 — the Set Card. Replaces the 12-control scrolling keypad: two big
/// pre-filled numbers, progress dots, one button. The Crown adjusts the outlined number (weight by
/// default, D-W4); Double Tap logs; holding Log set starts Quick Talk (D12). Everything rare —
/// warm-up, plate step, this workout's sets, Last set, dictation — is one level down in More.
struct WatchSetKeypadView: View {
    @Bindable var bindableModel: WatchStrengthFlowModel
    var model: WatchStrengthFlowModel { bindableModel }
    let talk: WatchQuickTalkController

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var focus: WatchSetCardField = .weight
    /// The initial step is a common smallest practical plate. People can change it in More;
    /// both the Crown and visible buttons always use this same step.
    @State private var weightStep: Double
    @State private var showingMore = false
    @State private var showingLifters = false
    @State private var holdStartedTalk = false
    @State private var isLogging = false
    @State private var toastLastTime: String?

    init(model: WatchStrengthFlowModel, talk: WatchQuickTalkController) {
        self.bindableModel = model
        self.talk = talk
        self._weightStep = State(initialValue: model.unit == .pounds ? 5 : 2.5)
    }

    private var increment: WeightIncrement { WeightIncrement(unit: model.unit) }

    var body: some View {
        if let card = model.setCardState {
            VStack(spacing: 3) {
                Text(card.exerciseName)
                    .font(.footnote.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                // Dots and (with partners) who is lifting share one row, so the card fits under the title.
                HStack(spacing: 6) {
                    WatchSetDots(dots: card.dots)
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
                fields(card)
                if !isLuminanceReduced {
                    if let line = card.planLine { WatchCoachLineView(line: line) }
                    secondaryRow(card)
                    logButton(card)
                    // The teaching hint gives way to the lifter row when partners take the space.
                    if WatchQuickTalkController.isEnabled, card.lifterText == nil {
                        Text(talk.isPhoneReachable ? "Hold to talk" : "iPhone not nearby — dictate in ⋯")
                            .font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 4)
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .focusable()
            .digitalCrownRotation(crownBinding, from: crownRange.lowerBound, through: crownRange.upperBound,
                                  by: focus == .weight ? weightStep : 1,
                                  sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            .sheet(isPresented: $showingMore) {
                NavigationStack { WatchSetMoreView(model: model, talk: talk, weightStep: $weightStep) }
            }
            .sheet(isPresented: $showingLifters) {
                NavigationStack { WatchPartnersView(model: model) }
            }
            .accessibilityAction(named: Text("Log set")) { log() }
            .accessibilityAction(named: Text("More")) { showingMore = true }
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
        let reps = WatchMetricField(value: "\(card.reps)", unit: String(localized: "reps"), isFocused: focus == .reps,
                                    accessibilityName: Text("Reps"),
                                    hint: Text("Select reps, then use the plus and minus buttons or turn the Digital Crown"),
                                    onFocus: { focus = .reps })
            .accessibilityIdentifier("watchReps.current")
        if card.isNonWeighted {
            VStack(spacing: 4) {
                Label("Non-weighted movement", systemImage: "figure.strengthtraining.traditional")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .accessibilityIdentifier("watchSet.nonWeighted")
                reps
                adjustmentControls(card)
            }
        } else if WatchSetCardMetricLayout.fields(isAccessibilitySize: dynamicTypeSize >= .accessibility1) == .stacked {
            VStack(spacing: 4) { weight; reps; adjustmentControls(card) }
        } else {
            VStack(spacing: 4) { HStack(spacing: 4) { weight; reps }; adjustmentControls(card) }
        }
    }

    /// Apple advises backing a Crown interaction with touch controls. This is deliberately shown
    /// on the Set Card rather than hidden in More, and changes exactly the focused Crown value.
    @ViewBuilder
    private func adjustmentControls(_ card: WatchSetCardState) -> some View {
        let isWeight = focus == .weight && !card.isNonWeighted
        let amount = isWeight ? weightStep : 1
        let label = isWeight ? "Weight" : "Reps"
        HStack(spacing: 6) {
            Button { adjustFocusedValue(by: -amount) } label: {
                Label("−\(stepText(amount))", systemImage: "minus")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .accessibilityLabel("Subtract \(stepText(amount)) \(isWeight ? card.unitText : "reps")")
            .accessibilityIdentifier(isWeight ? "watchWeight.minus" : "watchReps.minus")

            Text("\(label) · turn Crown")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 64)
                .accessibilityHidden(true)

            Button { adjustFocusedValue(by: amount) } label: {
                Label("+\(stepText(amount))", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .accessibilityLabel("Add \(stepText(amount)) \(isWeight ? card.unitText : "reps")")
            .accessibilityIdentifier(isWeight ? "watchWeight.plus" : "watchReps.plus")
        }
        .buttonStyle(.bordered)
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

    private var crownBinding: Binding<Double> {
        focus == .weight && !isCurrentExerciseNonWeighted
            ? $bindableModel.currentWeightDisplay
            : $bindableModel.currentReps
    }

    private var crownRange: ClosedRange<Double> {
        focus == .weight && !isCurrentExerciseNonWeighted ? increment.range : 1...50
    }

    private var isCurrentExerciseNonWeighted: Bool {
        guard case .keypad(let exercise) = model.stage else { return false }
        return SessionViewModel.isNonWeighted(exercise)
    }

    // MARK: Effort + More

    private func secondaryRow(_ card: WatchSetCardState) -> some View {
        HStack(spacing: 6) {
            Button { WatchHaptics.tap(); model.cycleEffort() } label: {
                Text(card.effortText ?? String(localized: "\(model.effortMode.displayName) —"))
            }
            .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
            .accessibilityIdentifier("watchEffort.value")
            .accessibilityHint(Text("Cycles the effort rating"))
            if card.isWarmup {
                Label("Warm-up", systemImage: "flame.fill").font(.caption2).foregroundStyle(WatchTone.attention)
            }
            Button { showingMore = true } label: { Image(systemName: "ellipsis") }
                .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                .frame(minWidth: 52)
                .contentShape(Rectangle())
                .accessibilityLabel(Text("More"))
                .accessibilityIdentifier("watchSet.more")
        }
    }

    // MARK: Log (tap / Double Tap) and hold-to-talk

    private func logButton(_ card: WatchSetCardState) -> some View {
        Button {
            if holdStartedTalk { holdStartedTalk = false; return }
            log()
        } label: {
            if isLogging {
                ProgressView()
            } else {
                Label(card.logTitle, systemImage: "checkmark")
            }
        }
        .buttonStyle(WatchPillStyle(kind: .primary))
        .disabled(isLogging)
        .handGestureShortcut(.primaryAction)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
            guard WatchQuickTalkController.isEnabled else { return }
            guard talk.isPhoneReachable else { showingMore = true; return }
            holdStartedTalk = true
            talk.startListening()
        })
        .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { value in
            guard holdStartedTalk else { return }
            // Slide well off the button to cancel; otherwise release sends the clip.
            if abs(value.translation.width) > 60 || abs(value.translation.height) > 60 {
                talk.cancelListening()
            } else {
                talk.finishListening()
            }
        })
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

/// S3 — More: warm-up, plate step with ± (Crown-free adjustment), this workout's sets with delete,
/// Last set (finish the exercise), and dictation when the iPhone isn't nearby (Quick Talk C).
struct WatchSetMoreView: View {
    @Bindable var model: WatchStrengthFlowModel
    let talk: WatchQuickTalkController
    @Binding var weightStep: Double
    @Environment(\.dismiss) private var dismiss
    @State private var dictation = ""
    @State private var confirmRemove = false
    @State private var showingExactWeight = false
    @State private var showingExactReps = false

    var body: some View {
        List {
            Toggle(isOn: Binding(get: { model.isWarmupSet }, set: { if $0 != model.isWarmupSet { model.toggleWarmup() } })) {
                Label("Warm-up set", systemImage: "flame.fill")
            }
            .accessibilityIdentifier("watchSet.warmup")

            if !isCurrentExerciseNonWeighted {
                WatchWeightAdjustSection(value: $model.currentWeightDisplay, unit: model.unit, plate: $weightStep)
            }
            WatchRepsAdjustSection(value: $model.currentReps)

            Section("Exact value") {
                if !isCurrentExerciseNonWeighted {
                    Button("Enter exact weight") { showingExactWeight = true }
                        .accessibilityIdentifier("watchWeight.exactEntry")
                }
                Button("Enter exact reps") { showingExactReps = true }
                    .accessibilityIdentifier("watchReps.exactEntry")
            }

            if !model.currentWorkoutHistoryLines.isEmpty {
                Section("This workout") {
                    ForEach(model.currentWorkoutHistoryLines) { line in
                        HStack {
                            Text(verbatim: "\(line.label)  \(line.weightText) × \(line.reps)").monospacedDigit()
                            Spacer()
                            if let setID = line.setID {
                                Button(role: .destructive) {
                                    WatchHaptics.delete()
                                    if let payload = model.deleteSet(id: setID) { WatchSyncSender.send(payload) }
                                } label: { Image(systemName: "trash") }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text("Delete set \(line.label)"))
                                .accessibilityIdentifier("watchSet.delete.\(line.label)")
                            }
                        }
                        .font(.footnote)
                    }
                }
            }

            Section {
                if WatchQuickTalkController.isEnabled, !talk.isPhoneReachable {
                    TextField("Dictate a set", text: $dictation)
                        .onSubmit {
                            let text = dictation
                            dictation = ""
                            dismiss()
                            talk.handle(transcript: text, source: .dictation)
                        }
                        .accessibilityIdentifier("watchSet.dictate")
                }
                Button {
                    WatchHaptics.success()
                    if model.logLastSet() != nil, let payload = model.lastSyncPayload { WatchSyncSender.send(payload) }
                    dismiss()
                } label: {
                    Label("Log as last set", systemImage: "flag.checkered")
                }
                .accessibilityIdentifier("lastSetButton")
            }

            if case .keypad(let exercise) = model.stage {
                Section {
                    Button(role: .destructive) { confirmRemove = true } label: {
                        Label("Remove exercise", systemImage: "trash")
                    }
                    .accessibilityIdentifier("watchStrength.deleteExercise.\(exercise.name)")
                }
            }
        }
        .navigationTitle("More")
        .sheet(isPresented: $showingExactWeight) {
            WatchNumericEntrySheet(field: .weight, initial: "", title: Text("Enter weight in \(model.unit.abbreviation)")) { raw in
                applyExactWeight(raw)
            }
        }
        .sheet(isPresented: $showingExactReps) {
            WatchNumericEntrySheet(field: .reps, initial: "", title: Text("Enter reps")) { raw in
                applyExactReps(raw)
            }
        }
        .alert("Remove \(removableExercise?.name ?? "")?", isPresented: $confirmRemove, presenting: removableExercise) { exercise in
            Button("Remove", role: .destructive) {
                WatchHaptics.delete()
                dismiss()
                if let payload = model.deleteExercise(exercise) { WatchSyncSender.send(payload) }
                model.goBackToHome()
            }
            .accessibilityIdentifier("watchStrength.deleteExercise.confirm")
            Button("Keep", role: .cancel) {}
        } message: { _ in
            Text("Its sets in this workout are removed too.")
        }
    }

    private var isCurrentExerciseNonWeighted: Bool {
        guard case .keypad(let exercise) = model.stage else { return false }
        return SessionViewModel.isNonWeighted(exercise)
    }

    private var removableExercise: Exercise? {
        if case .keypad(let exercise) = model.stage { return exercise }
        return nil
    }

    private func applyExactWeight(_ raw: String) {
        let increment = WeightIncrement(unit: model.unit)
        if case .success(let value) = WatchSetEntryParser.weight(raw, unit: model.unit, range: increment.range) {
            model.currentWeightDisplay = value
            WatchHaptics.success()
        }
    }

    private func applyExactReps(_ raw: String) {
        if case .success(let value) = WatchSetEntryParser.reps(raw) {
            model.currentReps = Double(value)
            WatchHaptics.success()
        }
    }

}
