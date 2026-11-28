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

    @State var draft: ExpandedSetDraftModel
    @State private var increment: Double
    @State var typedWeight: String
    @State var typedReps: String
    @State var hasExplicitWeightEntry: Bool
    @State var keypadPresented = false
    @State var repsKeypadPresented = false
    @State var keypadError: String?
    @State private var deletePresented = false
    @State var performerID: UUID?
    @State var showHistory = false
    @State var historyPresented = false
    @State var partnersPresented = false
    @State var effortPresented = false

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

    var weightText: String {
        ExpandedSetDraftModel.displayWeightText(draft.weight,
                                                hasExplicitEntry: hasExplicitWeightEntry,
                                                bodyweight: config.bodyweight)
    }
    var isPR: Bool { wouldBePR?(draft.canonicalWeightKg, draft.reps) ?? false }
    var effortValueText: String {
        draft.effort.map { "\(Int($0.rounded()))" } ?? "—"
    }
    var effortAccessibilityText: String {
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
            .sheet(isPresented: $historyPresented) {
                setEditorSheet(title: "History") { historySection }
            }
            .sheet(isPresented: $partnersPresented) {
                setEditorSheet(title: "Partner") { performerSection }
            }
            .sheet(isPresented: $effortPresented) {
                setEditorSheet(title: "Effort") { effortSection }
            }
            .sheet(isPresented: $keypadPresented) { keypad }
            .sheet(isPresented: $repsKeypadPresented) { repsKeypad }
        }
        // Leave the live workout header (elapsed / BPM / Work-Rest) visible
        // above the editor instead of covering it with a full-height sheet.
        .presentationDetents([.custom(SetEditorSheetDetent.self)])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("setEditor.sheet")
        // Performer selection changes attribution/history only. The current
        // reps and load are the user's in-progress set, so switching the partner
        // at the end of entry must never overwrite work already typed.
    }

    private var headerContext: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                if config.setTotal > 0 {
                    setProgressRing
                    Text("\(config.setNumber)/\(config.setTotal)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("setEditor.setGauge")
                        .accessibilityLabel("Set \(config.setNumber) of \(config.setTotal)")
                }
                Text(config.exerciseName.localizedExerciseName)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("setEditor.exerciseName")
                Menu {
                    Button {
                        showHistory = true
                        historyPresented = true
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("setEditor.menu.history")
                    Button { partnersPresented = true } label: {
                        Label("Partner", systemImage: "person.2")
                    }
                    .accessibilityIdentifier("setEditor.menu.partner")
                    Button { effortPresented = true } label: {
                        Label("Effort", systemImage: "flame")
                    }
                    .accessibilityIdentifier("setEditor.menu.effort")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityIdentifier("setEditor.menu")
                .accessibilityLabel("Set options")
            }
            if let context = config.recordedText {
                Text(context).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var setProgressRing: some View {
        let progress = config.setTotal > 0
            ? min(1, max(0, Double(config.setNumber) / Double(config.setTotal)))
            : 0
        return ZStack {
            Circle().stroke(Color.green.opacity(0.22), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 20, height: 20)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func setEditorSheet<Content: View>(title: String,
                                               @ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            ScrollView {
                content()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        historyPresented = false
                        partnersPresented = false
                        effortPresented = false
                    }
                }
            }
        }
    }

    private var weightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(config.bodyweight ? "Added weight" : "Weight")
                    .font(.headline)
                    .fixedSize()
                // Plate/increment buttons live on the Weight title row so they
                // no longer take a whole extra row above the number.
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ExpandedSetDraftModel.increments(for: config.unit), id: \.self) { value in
                                Button { increment = value; Haptics.selection() } label: {
                                    Text(incrementLabel(value))
                                        .font(.caption2.weight(.semibold))
                                        .fixedSize(horizontal: true, vertical: false)
                                        .frame(minHeight: 28)
                                        .padding(.horizontal, 4)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                .tint(increment == value ? .green : .secondary)
                                .accessibilityIdentifier("setEditor.weight.increment.\(displayID(value))")
                                .accessibilityAddTraits(increment == value ? .isSelected : [])
                                .id(value)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    .contentMargins(.horizontal, 1, for: .scrollContent)
                    .onAppear { proxy.scrollTo(increment, anchor: .center) }
                }
                .frame(height: 34)
            }
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
                            .scaledSystemFont(40, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .lineLimit(1)
                            .allowsTightening(true)
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
            if isPR { Label("Would be a PR", systemImage: "trophy.fill").foregroundStyle(.orange).font(.subheadline.weight(.semibold)) }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
    private var repsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Reps").font(.headline)
            HStack(spacing: 12) {
                weightStepButton("−", label: "Decrease reps",
                                 identifier: "setEditor.reps.minus") {
                    draft.adjustReps(by: -1)
                    Haptics.selection()
                }
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
                weightStepButton("+", label: "Increase reps",
                                 identifier: "setEditor.reps.plus") {
                    draft.adjustReps(by: 1)
                    Haptics.selection()
                }
            }
        }.padding(16).background(.background, in: RoundedRectangle(cornerRadius: 16))
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
    func adjustmentButton(_ title: String, action: @escaping () -> Void) -> some View { Button(title, action: action).font(.title3.weight(.bold)).buttonStyle(.bordered).tint(.green).frame(maxWidth: .infinity, minHeight: 56).contentShape(Rectangle()).padding(.vertical, 9) }
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

}
