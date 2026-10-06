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
    @State private var showingMore = false
    @State private var showingLifters = false
    @State private var showingWeightEntry = false
    @State private var showingRepsEntry = false
    @State private var holdStartedTalk = false
    @State private var isLogging = false

    init(model: WatchStrengthFlowModel, talk: WatchQuickTalkController) {
        self.bindableModel = model
        self.talk = talk
    }

    private var increment: WeightIncrement { WeightIncrement(unit: model.unit) }

    var body: some View {
        if let card = model.setCardState {
            VStack(spacing: 3) {
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
                    if let last = card.lastTimeText {
                        Text(last).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let line = card.planLine { WatchCoachLineView(line: line) }
                    secondaryRow(card)
                    logButton(card)
                    // The teaching hint gives way to the lifter row when partners take the space.
                    if card.lifterText == nil {
                        Text(talk.isPhoneReachable ? "Hold to talk" : "iPhone not nearby — dictate in ⋯")
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .accessibilityHidden(true)
                    }
                }
            }
            .padding(.horizontal, 4)
            .navigationTitle(card.exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .focusable()
            .digitalCrownRotation(crownBinding, from: crownRange.lowerBound, through: crownRange.upperBound,
                                  by: focus == .weight ? increment.crownDetent : 1,
                                  sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
            .sheet(isPresented: $showingMore) {
                NavigationStack { WatchSetMoreView(model: model, talk: talk) }
            }
            .sheet(isPresented: $showingLifters) {
                NavigationStack { WatchPartnersView(model: model) }
            }
            .sheet(isPresented: $showingWeightEntry) {
                WatchWeightEntryView(value: $bindableModel.currentWeightDisplay, unit: model.unit)
            }
            .sheet(isPresented: $showingRepsEntry) {
                WatchRepsEntryView(value: $bindableModel.currentReps)
            }
            .accessibilityAction(named: Text("Log set")) { log() }
            .accessibilityAction(named: Text("Talk")) { talk.startListening() }
            .accessibilityAction(named: Text("More")) { showingMore = true }
        }
    }

    // MARK: Fields

    @ViewBuilder
    private func fields(_ card: WatchSetCardState) -> some View {
        let weight = WatchMetricField(value: card.weightText, unit: card.unitText, isFocused: focus == .weight,
                                      accessibilityName: Text("Weight")) {
            focus = .weight
            showingWeightEntry = true
        }
            .accessibilityIdentifier("watchWeight.current")
        let reps = WatchMetricField(value: "\(card.reps)", unit: String(localized: "reps"), isFocused: focus == .reps,
                                    accessibilityName: Text("Reps")) {
            focus = .reps
            showingRepsEntry = true
        }
            .accessibilityIdentifier("watchReps.current")
        if card.isNonWeighted {
            VStack(spacing: 4) {
                Label("Non-weighted movement", systemImage: "figure.strengthtraining.traditional")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .accessibilityIdentifier("watchSet.nonWeighted")
                reps
            }
        } else if dynamicTypeSize >= .accessibility1 {
            VStack(spacing: 4) { weight; reps }
        } else {
            HStack(spacing: 4) { weight; reps }
        }
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
            Button { showingMore = true } label: { Image(systemName: "ellipsis")
                .frame(minWidth: 44, minHeight: 44)
            }
                .buttonStyle(WatchPillStyle(kind: .secondary, small: true))
                .frame(minWidth: 52, minHeight: 44)
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
        .accessibilityHint(Text("Hold to log by voice"))
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
    @Environment(\.dismiss) private var dismiss
    @State private var dictation = ""
    @State private var confirmRemove = false

    var body: some View {
        List {
            Toggle(isOn: Binding(get: { model.isWarmupSet }, set: { if $0 != model.isWarmupSet { model.toggleWarmup() } })) {
                Label("Warm-up set", systemImage: "flame.fill")
            }
            .accessibilityIdentifier("watchSet.warmup")

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
                if !talk.isPhoneReachable {
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

    private var removableExercise: Exercise? {
        if case .keypad(let exercise) = model.stage { return exercise }
        return nil
    }

}

/// Dedicated weight entry. Plate math lives here, while the exact-value keypad
/// is one more tap away from the large current value.
struct WatchWeightEntryView: View {
    @Binding var value: Double
    let unit: MeasurementUnitPreference
    @Environment(\.dismiss) private var dismiss
    @State private var plate: Double = 2.5
    @State private var directEntry = false

    private var increment: WeightIncrement { WeightIncrement(unit: unit) }
    private var range: ClosedRange<Double> { increment.range }

    var body: some View {
        List {
            Section {
                Button { directEntry = true } label: {
                    VStack(spacing: 2) {
                        Text(Format.weightValue(value, unit: unit, decimals: 1))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.55)
                        Text("Tap again to type exact weight")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watchWeight.entry.value")
            }
            Section("Plate math") {
                Picker("Plate step", selection: $plate) {
                    ForEach(increment.plateOptions, id: \.self) { option in
                        Text("\(plateText(option)) \(unit.abbreviation)").tag(option)
                    }
                }
                HStack(spacing: 8) {
                    Button { adjust(-plate) } label: { Label("Subtract", systemImage: "minus") }
                        .accessibilityIdentifier("watchWeight.minusPlate")
                    Button { adjust(plate) } label: { Label("Add", systemImage: "plus") }
                        .accessibilityIdentifier("watchWeight.plusPlate")
                }
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .onAppear {
            plate = increment.plateOptions.filter { $0 >= (unit == .pounds ? 5 : 2.5) }.min()
                ?? increment.plateOptions.min() ?? 2.5
        }
        .sheet(isPresented: $directEntry) {
            WatchNumericEntryView(title: "Enter weight", initialValue: Format.weightValue(value, unit: unit, decimals: 1), allowsDecimal: true) { text in
                if let number = Double(text), number.isFinite {
                    value = min(range.upperBound, max(range.lowerBound, number))
                }
            }
        }
    }

    private func adjust(_ amount: Double) {
        WatchHaptics.tap()
        value = min(range.upperBound, max(range.lowerBound, value + amount))
    }

    private func plateText(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

/// Dedicated reps entry. The number is editable through the same second-tap
/// interaction as weight, while the common +/- path remains one touch away.
struct WatchRepsEntryView: View {
    @Binding var value: Double
    @Environment(\.dismiss) private var dismiss
    @State private var directEntry = false

    var body: some View {
        List {
            Section {
                Button { directEntry = true } label: {
                    VStack(spacing: 2) {
                        Text("\(Int(value.rounded()))")
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        Text("Tap again to type reps")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("watchReps.entry.value")
            }
            Section("Adjust reps") {
                HStack(spacing: 8) {
                    Button { value = max(1, value - 1); WatchHaptics.tap() } label: { Label("Minus", systemImage: "minus") }
                        .accessibilityIdentifier("watchReps.minus")
                    Button { value = min(100, value + 1); WatchHaptics.tap() } label: { Label("Plus", systemImage: "plus") }
                        .accessibilityIdentifier("watchReps.plus")
                }
                .buttonStyle(.bordered)
            }
        }
        .navigationTitle("Reps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .sheet(isPresented: $directEntry) {
            WatchNumericEntryView(title: "Enter reps", initialValue: "\(Int(value.rounded()))", allowsDecimal: false) { text in
                if let number = Int(text) { value = Double(min(100, max(1, number))) }
            }
        }
    }
}

/// A tiny numeric keypad that works consistently on the watch simulator and
/// device instead of relying on the system keyboard appearing over a compact
/// sheet.
struct WatchNumericEntryView: View {
    let title: String
    let initialValue: String
    let allowsDecimal: Bool
    let onCommit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var rows: [[String]] {
        allowsDecimal ? [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], [".", "0", "⌫"]]
            : [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(text.isEmpty ? initialValue : text)
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 34)
                .accessibilityIdentifier("watchNumeric.value")
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(row, id: \.self) { key in
                        Button { tap(key) } label: {
                            Text(key).font(.headline).frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                        .disabled(key.isEmpty)
                    }
                }
            }
            Button("Done") { onCommit(text.isEmpty ? initialValue : text); dismiss() }
                .buttonStyle(WatchPillStyle(kind: .primary, small: true))
                .accessibilityIdentifier("watchNumeric.done")
        }
        .padding(8)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { text = initialValue }
    }

    private func tap(_ key: String) {
        switch key {
        case "⌫": if !text.isEmpty { text.removeLast() }
        case ".": if allowsDecimal && !text.contains(".") { text += text.isEmpty ? "0." : "." }
        default: if text == "0" { text = key } else if text.count < 7 { text += key }
        }
    }
}
