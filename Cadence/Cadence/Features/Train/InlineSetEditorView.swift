import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// Full-screen add/edit set entry. The filename is retained to avoid changing
/// the Xcode project graph; the old inline implementation is no longer used.
struct InlineSetEditorView: View {
    @Environment(AppSettings.self) private var settings
    let config: InlineEditorConfig
    let wouldBePR: ((Double, Int) -> Bool)?
    let onSave: (SetDraft) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void
    let onActivity: () -> Void
    let onEffortMode: (WatchEffortMode) -> Void
    let onAddPartner: (() -> Void)?

    @State private var draft: ExpandedSetDraftModel
    @State private var increment: Double
    @State private var typedWeight: String
    @State private var typedReps: String
    @State private var hasExplicitWeightEntry: Bool
    @State private var keypadPresented = false
    @State private var repsKeypadPresented = false
    @State private var keypadError: String?
    @State private var deletePresented = false
    @State private var performerID: UUID?

    init(config: InlineEditorConfig, wouldBePR: ((Double, Int) -> Bool)?,
         onSave: @escaping (SetDraft) -> Void, onDelete: (() -> Void)?,
         onCancel: @escaping () -> Void, onActivity: @escaping () -> Void,
         onEffortMode: @escaping (WatchEffortMode) -> Void = { _ in },
         onAddPartner: (() -> Void)? = nil) {
        self.config = config; self.wouldBePR = wouldBePR; self.onSave = onSave
        self.onDelete = onDelete; self.onCancel = onCancel; self.onActivity = onActivity
        self.onEffortMode = onEffortMode
        self.onAddPartner = onAddPartner
        let value = Double(config.weight.replacingOccurrences(of: ",", with: ".")) ?? 0
        _draft = State(initialValue: ExpandedSetDraftModel(weight: value, reps: config.reps,
                                                            rpe: config.rpe.map(Double.init), unit: config.unit,
                                                            effortMode: config.effortMode))
        _increment = State(initialValue: config.unit == .pounds ? 5 : 2.5)
        _typedWeight = State(initialValue: config.weight)
        _typedReps = State(initialValue: "\(config.reps)")
        _hasExplicitWeightEntry = State(initialValue: !config.weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        _performerID = State(initialValue: config.performerID)
    }

    private var weightText: String {
        ExpandedSetDraftModel.displayWeightText(draft.weight,
                                                hasExplicitEntry: hasExplicitWeightEntry,
                                                bodyweight: config.bodyweight)
    }
    private var isPR: Bool { wouldBePR?(draft.canonicalWeightKg, draft.reps) ?? false }
    private var effortValueText: String {
        draft.effort.map { "\(Int($0.rounded()))" } ?? "—"
    }
    private var effortAccessibilityText: String {
        if let effort = draft.effort {
            return "\(draft.effortMode.displayName) \(Int(effort.rounded()))"
        }
        return String(localized: "No effort selected")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerContext
                    performerSection
                    historySection
                    if config.nonWeighted {
                        Label("Non-weighted movement · no load entry", systemImage: "figure.strengthtraining.traditional")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(.background, in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        weightSection
                    }
                    repsSection
                    effortSection
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) { footer }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if onDelete != nil { ToolbarItem(placement: .topBarTrailing) { Button("Delete", role: .destructive) { deletePresented = true }.accessibilityIdentifier("setEditor.delete") } }
            }
            .alert("Delete \(config.exerciseName), \(config.setNumberText)?", isPresented: $deletePresented) {
                Button("Delete", role: .destructive) { Haptics.restComplete(); onDelete?() }
                Button("Cancel", role: .cancel) { }
            } message: { Text("This set will be removed from the workout.") }
            .sheet(isPresented: $keypadPresented) { keypad }
            .sheet(isPresented: $repsKeypadPresented) { repsKeypad }
        }
        // Leave the live workout header (elapsed / BPM / Work-Rest) visible
        // above the editor instead of covering it with a full-height sheet.
        .presentationDetents([PresentationDetent.custom { context in
            max(320, context.maxDetentValue - 96)
        }])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("setEditor.sheet")
        // Performer selection changes attribution/history only. The current
        // reps and load are the user's in-progress set, so switching the partner
        // at the end of entry must never overwrite work already typed.
    }

    private var headerContext: some View {
        VStack(spacing: 6) {
            Text(config.exerciseName.localizedExerciseName).font(.headline).frame(maxWidth: .infinity)
                .accessibilityIdentifier("setEditor.exerciseName")
            Text(config.setNumberText).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityIdentifier("setEditor.setNumber")
            if let context = config.recordedText { Text(context).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
        }
    }

    /// The roster entry for whoever is currently selected. The History card reads
    /// this, so it re-derives by SwiftUI recompute whenever the performer
    /// changes.
    private var selectedDefault: InlineEditorConfig.PerformerDefault? {
        config.performerDefaults.first { $0.performerID == performerID }
    }

    /// Per-selected-performer history: prior-session sets on this movement
    /// ("Last time") and the most recent set logged today ("Last set today").
    /// Decision D8: an explicit "No previous history for <name>" line satisfies
    /// "always show (if any)" and is assertable in the smoke test.
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History").font(.headline)
            if let lastTime = historyLastTimeText {
                Text("Last time: \(lastTime)")
                    .accessibilityIdentifier("setEditor.history.lastTime")
            } else {
                Text("No previous history for \(selectedPerformerName)")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("setEditor.history.noHistory")
            }
            if let lastSet = selectedDefault?.lastSetThisSession {
                Text("Last set today: \(lastSet)")
                    .accessibilityIdentifier("setEditor.history.lastSet")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setEditor.history")
    }

    private var selectedPerformerName: String {
        guard let performerID else { return "Me" }
        return config.roster.first(where: { $0.personID == performerID })?.name ?? String(localized: "Partner")
    }

    private var historyLastTimeText: String? {
        if let text = selectedDefault?.lastTimeText { return text }
        // The owner's card history is the page's source of truth. Use it when
        // the per-performer default is missing rather than showing a false
        // "No previous history".
        return performerID == nil ? config.lastTimeText : nil
    }

    private var performerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                Button("Me") { performerID = nil }
                ForEach(config.roster.filter { !$0.isMe && $0.personID != nil }) { person in
                    Button(person.name) { performerID = person.personID }
                }
                if let onAddPartner {
                    Divider()
                    Button("Add Partner…") { onAddPartner() }
                }
            } label: {
                HStack {
                    Image(systemName: performerID == nil ? "person.fill" : "person.2.fill")
                    Text(selectedPerformerName).fontWeight(.semibold)
                    Spacer()
                    Text("Change").foregroundStyle(.tint)
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Performer, \(selectedPerformerName)")
            .accessibilityIdentifier("setEditor.performer")
            if let onAddPartner {
                Button("＋ Add Partner", action: onAddPartner)
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("setEditor.performer.add")
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(config.bodyweight ? "Added weight" : "Weight").font(.headline)
            if config.bodyweight { Text("Bodyweight movement · enter added load only").font(.caption).foregroundStyle(.secondary) }
            HStack(spacing: 12) {
                weightStepButton("−", label: "Decrease weight",
                                 identifier: "setEditor.weight.minus") {
                    hasExplicitWeightEntry = true
                    draft.adjustWeight(by: -increment)
                    Haptics.selection()
                }
                Button { typedWeight = weightText; keypadPresented = true } label: {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(weightText)
                            .scaledSystemFont(52, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                            .monospacedDigit()
                        Text(config.unit.abbreviation).font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("setEditor.weightValue")
                .accessibilityValue("\(weightText) \(config.unit.abbreviation)")
                weightStepButton("+", label: "Increase weight",
                                 identifier: "setEditor.weight.plus") {
                    hasExplicitWeightEntry = true
                    draft.adjustWeight(by: increment)
                    Haptics.selection()
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ExpandedSetDraftModel.increments(for: config.unit), id: \.self) { value in
                            Button { increment = value; Haptics.selection() } label: {
                                Text(incrementLabel(value))
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(minHeight: 48)
                                    .padding(.horizontal, 10)
                            }.buttonStyle(.bordered).tint(increment == value ? .green : .secondary)
                                .accessibilityIdentifier("setEditor.weight.increment.\(displayID(value))").accessibilityAddTraits(increment == value ? .isSelected : [])
                                .id(value)
                        }
                        Button { typedWeight = weightText; keypadPresented = true } label: {
                            Text("Type")
                                .frame(minHeight: 48)
                                .padding(.horizontal, 10)
                                .accessibilityLabel("Type weight")
                        }.buttonStyle(.bordered).accessibilityIdentifier("setEditor.weight.type")
                    }
                    .padding(.horizontal, 2)
                }
                .contentMargins(.horizontal, 2, for: .scrollContent)
                .onAppear { proxy.scrollTo(increment, anchor: .center) }
            }
            if isPR { Label("Would be a PR", systemImage: "trophy.fill").foregroundStyle(.orange).font(.subheadline.weight(.semibold)) }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private var repsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reps").font(.headline)
            HStack(spacing: 12) {
                adjustmentButton("−") { draft.adjustReps(by: -1); Haptics.selection() }.accessibilityLabel("Decrease reps").accessibilityIdentifier("setEditor.reps.minus")
                Button {
                    typedReps = "\(draft.reps)"
                    repsKeypadPresented = true
                } label: {
                    Text("\(draft.reps)")
                        .scaledSystemFont(42, relativeTo: .title, weight: .bold, design: .rounded)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("\(draft.reps) reps")
                .accessibilityHint("Tap to enter a rep count")
                .accessibilityIdentifier("setEditor.reps.value")
                adjustmentButton("+") { draft.adjustReps(by: 1); Haptics.selection() }.accessibilityLabel("Increase reps").accessibilityIdentifier("setEditor.reps.plus")
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private var effortSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Effort").font(.headline)
            HStack(spacing: 0) {
                ForEach(WatchEffortMode.allCases) { mode in
                    Button(mode.displayName) { draft.selectMode(mode); onEffortMode(mode); Haptics.selection() }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        .background(draft.effortMode == mode ? Color.green.opacity(0.22) : .clear)
                        .accessibilityIdentifier("setEditor.effort.\(mode.rawValue)")
                        .accessibilityAddTraits(draft.effortMode == mode ? .isSelected : [])
                }
            }.background(.background, in: RoundedRectangle(cornerRadius: 10)).clipShape(RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 12) {
                adjustmentButton("−") { adjustEffort(by: -1) }
                    .accessibilityLabel("Decrease effort")
                    .accessibilityIdentifier("setEditor.effort.minus")
                Text(effortValueText)
                    .scaledSystemFont(42, relativeTo: .title, weight: .bold, design: .rounded)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("setEditor.effort.value")
                    .accessibilityLabel(effortAccessibilityText)
                adjustmentButton("+") { adjustEffort(by: 1) }
                    .accessibilityLabel("Increase effort")
                    .accessibilityIdentifier("setEditor.effort.plus")
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private func adjustEffort(by delta: Double) {
        draft.adjustEffort(by: delta)
        Haptics.selection()
    }
    private var footer: some View {
        Button(action: {
            guard let result = draft.submit() else { return }
            // Gate through CuePolicy (via CelebrationCuePlayer) so Settings →
            // Celebrations controls this manual-log haptic the same way as the
            // primary set-logging path in SessionView+SetActions.
            if let kind = CelebrationCuePlayer(celebrationStyle: settings.celebrationStyle)
                .decide(for: .loggedSet(isPersonalBest: isPR))?.kind {
                Haptics.play(kind)
            }
            onSave(SetDraft(weightString: config.nonWeighted ? "0" : weightText, unit: config.unit, reps: result.reps, rpe: result.rpe.map { Int($0) }, bodyweight: config.bodyweight, performerID: performerID, repsWereEdited: draft.didEditReps))
        }) {
            Text("Log Set").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(CadenceTheme.accent)
        .controlSize(.large)
        .frame(maxWidth: .infinity, minHeight: 56)
        .disabled(draft.hasSubmitted)
        .overlay { if draft.hasSubmitted { ProgressView() } }
        .accessibilityIdentifier(config.isEditing ? "setEditor.save" : "session.set.log")
        .padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
    }
    private func adjustmentButton(_ title: String, action: @escaping () -> Void) -> some View { Button(title, action: action).font(.title3.weight(.bold)).buttonStyle(.bordered).tint(.green).frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle()).padding(.vertical, 9) }
    private func weightStepButton(_ title: String, label: LocalizedStringKey,
                                  identifier: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.title2.weight(.bold))
                .frame(width: 52, height: 56)
        }
        .buttonStyle(.bordered)
        .tint(.green)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
    private func display(_ value: Double) -> String { value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value).replacingOccurrences(of: "0+$", with: "", options: .regularExpression) }
    private func displayID(_ value: Double) -> String { display(value) }
    private func incrementLabel(_ value: Double) -> String { "\(value >= 10 ? "+" : "±")\(display(value))" }
    private var keypad: some View {
        NavigationStack { VStack(spacing: 12) { TextField("Weight", text: $typedWeight).keyboardType(.decimalPad).font(.largeTitle.monospacedDigit()).multilineTextAlignment(.center).textFieldStyle(.roundedBorder).padding(); if let keypadError { Text(keypadError).font(.caption).foregroundStyle(CadenceTheme.attention) }; ForEach([["1","2","3"],["4","5","6"],["7","8","9"],[".","0","⌫"]], id: \.self) { row in HStack { ForEach(row, id: \.self) { key in Button(key) { if key == "⌫" { if !typedWeight.isEmpty { typedWeight.removeLast() } } else if key == "." && !typedWeight.contains(".") { typedWeight += "." } else if key != "." { typedWeight += key } }.font(.title).frame(maxWidth: .infinity, minHeight: 56).buttonStyle(.bordered) } } }; Spacer() }.padding().navigationTitle(config.bodyweight ? "Enter added weight" : "Enter weight").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if let value = Double(typedWeight), value.isFinite { hasExplicitWeightEntry = true; draft.setWeight(value); keypadError = nil; keypadPresented = false } else { keypadError = "Enter a valid number" } } } } }
    }
    private var repsKeypad: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(typedReps.isEmpty ? "0" : typedReps)
                    .font(.largeTitle.monospacedDigit().bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .accessibilityIdentifier("setEditor.reps.typed")
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]], id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { key in
                            Button(key.isEmpty ? " " : key) {
                                if key == "⌫" {
                                    if !typedReps.isEmpty { typedReps.removeLast() }
                                } else if !key.isEmpty, typedReps.count < 3 {
                                    if typedReps == "0" { typedReps = key } else { typedReps += key }
                                }
                            }
                            .font(.title)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .buttonStyle(.bordered)
                            .disabled(key.isEmpty)
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Enter reps")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let reps = Int(typedReps), (1...100).contains(reps) {
                            draft.setReps(reps)
                            repsKeypadPresented = false
                        }
                    }
                }
            }
        }
    }
}
