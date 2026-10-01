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
    @State private var holdStartedTalk = false
    @State private var isLogging = false

    init(model: WatchStrengthFlowModel, talk: WatchQuickTalkController) {
        self.bindableModel = model
        self.talk = talk
    }

    private var increment: WeightIncrement { WeightIncrement(unit: model.unit) }

    var body: some View {
        if let card = model.setCardState {
            VStack(spacing: 4) {
                if let lifter = card.lifterText {
                    Button { showingLifters = true } label: {
                        Label(lifter, systemImage: "person.fill")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(WatchTone.accentSoft))
                            .foregroundStyle(WatchTone.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("watchStrength.lifterChip")
                    .accessibilityHint(Text("Choose who lifts next"))
                }
                WatchSetDots(dots: card.dots)
                fields(card)
                if !isLuminanceReduced {
                    if let last = card.lastTimeText {
                        Text(last).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let line = card.planLine { WatchCoachLineView(line: line) }
                    secondaryRow(card)
                    logButton(card)
                    Text(talk.isPhoneReachable ? "Hold to talk" : "iPhone not nearby — dictate in ⋯")
                        .font(.caption2).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
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
            .accessibilityAction(named: Text("Log set")) { log() }
            .accessibilityAction(named: Text("Talk")) { talk.startListening() }
            .accessibilityAction(named: Text("More")) { showingMore = true }
        }
    }

    // MARK: Fields

    @ViewBuilder
    private func fields(_ card: WatchSetCardState) -> some View {
        let weight = WatchMetricField(value: card.weightText, unit: card.unitText, isFocused: focus == .weight,
                                      accessibilityName: Text("Weight")) { focus = .weight }
            .accessibilityIdentifier("watchWeight.current")
        let reps = WatchMetricField(value: "\(card.reps)", unit: String(localized: "reps"), isFocused: focus == .reps,
                                    accessibilityName: Text("Reps")) { focus = .reps }
            .accessibilityIdentifier("watchReps.current")
        if dynamicTypeSize >= .accessibility1 {
            VStack(spacing: 4) { weight; reps }
        } else {
            HStack(spacing: 4) { weight; reps }
        }
    }

    private var crownBinding: Binding<Double> {
        focus == .weight ? $bindableModel.currentWeightDisplay : $bindableModel.currentReps
    }

    private var crownRange: ClosedRange<Double> { focus == .weight ? increment.range : 1...50 }

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
                .frame(width: 44)
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
    @State private var plate: Double = 0
    @State private var dictation = ""

    private var increment: WeightIncrement { WeightIncrement(unit: model.unit) }

    var body: some View {
        List {
            Toggle(isOn: Binding(get: { model.isWarmupSet }, set: { if $0 != model.isWarmupSet { model.toggleWarmup() } })) {
                Label("Warm-up set", systemImage: "flame.fill")
            }
            .accessibilityIdentifier("watchSet.warmup")

            Section("Weight") {
                Picker("Plate step", selection: $plate) {
                    ForEach(increment.plateOptions, id: \.self) { value in
                        Text(verbatim: "\(plateText(value)) \(model.unit.abbreviation)").tag(value)
                    }
                }
                .accessibilityIdentifier("watchWeight.platePicker")
                HStack {
                    Button { adjust(-plate) } label: { Image(systemName: "minus") }
                        .accessibilityLabel(Text("Subtract \(plateText(plate)) \(model.unit.abbreviation)"))
                        .accessibilityIdentifier("watchWeight.minusPlate")
                    Text(verbatim: "\(model.currentWeightText) \(model.unit.abbreviation)")
                        .monospacedDigit().frame(maxWidth: .infinity)
                    Button { adjust(plate) } label: { Image(systemName: "plus") }
                        .accessibilityLabel(Text("Add \(plateText(plate)) \(model.unit.abbreviation)"))
                        .accessibilityIdentifier("watchWeight.plusPlate")
                }
                .buttonStyle(.bordered)
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
        }
        .navigationTitle("More")
        .onAppear { plate = increment.plateOptions.first(where: { $0 >= 2.5 }) ?? increment.plateOptions.first ?? 2.5 }
    }

    private func adjust(_ delta: Double) {
        WatchHaptics.tap()
        model.currentWeightDisplay = min(increment.range.upperBound, max(increment.range.lowerBound, model.currentWeightDisplay + delta))
    }

    private func plateText(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
