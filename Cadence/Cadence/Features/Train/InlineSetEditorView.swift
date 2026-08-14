import SwiftUI
import CadenceCore
import CadenceFeatures

struct InlineSetEditorView: View {
    let config: InlineEditorConfig
    let wouldBePR: ((Double, Int) -> Bool)?
    let onSave: (SetDraft) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void
    let onActivity: () -> Void

    @State private var weight: String
    @State private var reps: Int
    @State private var rpe: Int?
    @State private var effortMode: WatchEffortMode = .rpe
    @State private var bodyweight: Bool
    @State private var performerID: UUID?
    @FocusState private var weightFocused: Bool
    @State private var showRPEInfo = false
    @State private var showWeightInfo = false

    init(config: InlineEditorConfig,
         wouldBePR: ((Double, Int) -> Bool)?,
         onSave: @escaping (SetDraft) -> Void,
         onDelete: (() -> Void)?,
         onCancel: @escaping () -> Void,
         onActivity: @escaping () -> Void) {
        self.config = config
        self.wouldBePR = wouldBePR
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        self.onActivity = onActivity
        _weight = State(initialValue: config.weight)
        _reps = State(initialValue: config.reps)
        _rpe = State(initialValue: config.rpe)
        _bodyweight = State(initialValue: config.bodyweight)
        _performerID = State(initialValue: config.performerID)
    }

    private var parsedWeightKg: Double {
        let parsed = Double(weight) ?? 0
        return WorkoutMath.canonical(parsed, from: config.unit)
    }

    private var isPR: Bool {
        guard parsedWeightKg > 0, reps > 0 else { return false }
        return wouldBePR?(parsedWeightKg, reps) ?? false
    }

    private var priorHintText: String? {
        guard let hint = config.priorWeightHint, hint > 0 else { return nil }
        return Format.weightValue(hint, unit: config.unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Effort", selection: $effortMode) {
                ForEach(WatchEffortMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("set.effortMode")
            HStack(spacing: SetCol.gap) {
            if config.hasPartners {
                performerPicker
            } else {
                Color.clear.frame(width: SetCol.num)
            }

            weightField
            repsField
            rpeField
            actionButtons
            }
        }
        .frame(minHeight: 44)
        .onAppear { weightFocused = true }
        .onChange(of: weight) { _, _ in onActivity() }
        .onChange(of: reps) { _, _ in onActivity() }
        .onChange(of: rpe) { _, _ in onActivity() }
        .sheet(isPresented: $showRPEInfo) { RPEInfoView() }
        .sheet(isPresented: $showWeightInfo) { weightInfoSheet }
    }

    // MARK: - Subviews

    private var performerPicker: some View {
        Menu {
            ForEach(config.roster) { entry in
                Button {
                    performerID = entry.personID
                    onActivity()
                } label: {
                    HStack {
                        Text(entry.name)
                        if performerID == entry.personID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            performerChip
        }
    }

    private var performerChip: some View {
        let p = config.roster.first { $0.personID == performerID }
        ?? config.roster.first { $0.isMe }
        ?? config.roster.first
        let label = p?.isMe ?? true ? "M" : String((p?.name ?? "?").prefix(1)).uppercased()
        let color: Color = {
            guard let p, !p.isMe else { return .accentColor }
            let palette: [Color] = [.purple, .teal, .pink, .indigo, .orange, .mint]
            return palette[abs(p.name.hashValue) % palette.count]
        }()
        return Text(label)
            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color, in: Circle())
    }

    private var weightField: some View {
        HStack(spacing: 2) {
            TextField("Weight", text: $weight)
                .keyboardType(.decimalPad)
                .focused($weightFocused)
                .multilineTextAlignment(.center)
                .font(.body.monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityIdentifier("set.weightField")

            if isPR {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityLabel("Would be a PR")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var repsField: some View {
        HStack(spacing: 0) {
            Button {
                reps = max(1, reps - 1)
            } label: {
                Image(systemName: "minus").font(.caption2.weight(.semibold))
                    .frame(width: 22, height: 32)
                    .contentShape(Rectangle())
            }

            Text("\(reps)").monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .frame(minWidth: 16, maxWidth: .infinity)

            Button {
                reps += 1
            } label: {
                Image(systemName: "plus").font(.caption2.weight(.semibold))
                    .frame(width: 22, height: 32)
                    .contentShape(Rectangle())
            }
        }
        .frame(width: SetCol.reps)
        .buttonStyle(.borderless)
    }

    private var rpeField: some View {
        Button {
            showRPEInfo = true
        } label: {
            if let r = rpe {
                Text("\(r)").font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 3))
            } else {
                Text(effortMode.displayName).font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: SetCol.rpe)
        .buttonStyle(.borderless)
        .contextMenu {
            ForEach(Array(1...10), id: \.self) { value in
                Button {
                    rpe = effortMode.rpeValue(from: Double(value)).map { Int($0) }
                } label: { Text("\(effortMode.displayName) \(value)") }
            }
            if rpe != nil {
                Divider()
                Button(role: .destructive) { rpe = nil } label: { Text("Clear") }
            }
        }
        .accessibilityLabel("\(effortMode.displayName) effort")
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            if onDelete != nil {
                Button {
                    onDelete?()
                } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                }
                .accessibilityIdentifier("set.delete")
            }

            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark").font(.caption)
            }
            .accessibilityIdentifier("set.cancel")

            Button {
                onSave(SetDraft(
                    weightString: weight,
                    unit: config.unit,
                    reps: reps,
                    rpe: rpe,
                    bodyweight: bodyweight,
                    performerID: performerID))
            } label: {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.green)
            }
            .accessibilityIdentifier("set.save")
        }
        .frame(width: SetCol.check + 20)
    }

    private var weightInfoSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight").font(.headline)
            Text("Enter the weight per side for this set. \(config.unit.abbreviation).")
                .font(.subheadline).foregroundStyle(.secondary)
            if let hint = priorHintText, config.priorWeightHint != nil {
                Text("Previous: \(hint) \(config.unit.abbreviation)")
                    .font(.caption).foregroundStyle(.tint)
                    .onTapGesture {
                        weight = hint
                    }
            }
        }
        .padding()
        .presentationDetents([.height(200)])
    }
}
