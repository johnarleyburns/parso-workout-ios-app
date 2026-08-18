import SwiftUI
import CadenceCore
import CadenceFeatures
struct ExerciseCardView: View {
    let context: SessionRenderModel.ExerciseContext
    let prSetIDs: Set<UUID>
    let roster: [RosterEntry]
    let hasPartners: Bool
    let unit: MeasurementUnitPreference
    let prRule: PRRule
    let prescriptionText: String?
    let isExpanded: Bool
    let isCurrent: Bool
    let compactSummary: String
    let onToggleExpansion: () -> Void

    let isInlineActive: Bool
    let inlineEditingSetID: UUID?
    let inlineConfig: InlineEditorConfig?
    let wouldBePR: ((Double, Int) -> Bool)?

    let onTapSet: (SessionRenderModel.SetDisplay) -> Void
    let onTapPending: (SessionRenderModel.PendingSetDisplay) -> Void
    let onRepeat: () -> Void
    let onAddSet: () -> Void
    let onChangeExercise: () -> Void
    let onRemoveExercise: () -> Void
    let exercise: Exercise?
    let onSaveSet: (SetDraft) -> Void
    let onDeleteEditingSet: () -> Void
    let onDeleteSet: (SessionRenderModel.SetDisplay) -> Void
    let onCancelInline: () -> Void
    let onActivity: () -> Void

    @State private var isEditing = false
    @State private var setToDelete: SessionRenderModel.SetDisplay?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            if isExpanded { contextLines }
            if isExpanded && (!context.sets.isEmpty || (isInlineActive && inlineEditingSetID == nil) || context.pendingCount > 0) {
                setColumnHeader
            }

            if isExpanded {
                ForEach(context.sets) { set in
                    completedSetRow(set)
                    Divider()
                }
                ForEach(context.pendingSets.isEmpty ? context.pendingReps.enumerated().map { offset, reps in SessionRenderModel.PendingSetDisplay(performerID: nil, performerName: "Me", setIndex: context.sets.filter { !$0.isWarmup }.count + offset, targetReps: reps, targetWeightKg: nil) } : context.pendingSets) { pending in
                    pendingRow(pending: pending)
                    Divider()
                }

                if !isEditing { actionButtons }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .confirmationDialog("Delete this set?", isPresented: Binding(
            get: { setToDelete != nil },
            set: { if !$0 { setToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let set = setToDelete { onDeleteSet(set) }
                setToDelete = nil
            }
            Button("Cancel", role: .cancel) { setToDelete = nil }
        } message: {
            Text("The set will be removed from this workout.")
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack {
            Button(action: onToggleExpansion) {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(.secondary).frame(width: 14)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(context.name).font(.headline).lineLimit(1)
                            if isCurrent { Image(systemName: "arrow.right.circle.fill").foregroundStyle(.green).font(.caption) }
                        }
                        if !isExpanded { Text(compactSummary).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(isExpanded ? "exercise.expanded" : "exercise.collapsed")
            .accessibilityValue(context.exerciseID.uuidString)
            .accessibilityLabel("\(context.name), \(compactSummary), \(isExpanded ? "expanded" : "collapsed")")
            .accessibilityAddTraits(.isButton)
            Spacer()
            if isExpanded, let exercise {
                NavigationLink {
                    ExerciseDetailView(exercise: exercise)
                } label: {
                    Image(systemName: "info.circle").font(.headline)
                        .foregroundStyle(.secondary).frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("exercise.info.\(context.name)")
                .accessibilityLabel("\(context.name) details")
            }
            if isExpanded { Menu {
                Button { onChangeExercise() } label: {
                    Label("Change exercise", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("exercise.changeExercise.\(context.name)")
                Button(role: .destructive) { onRemoveExercise() } label: {
                    Label("Remove exercise", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").font(.headline)
                    .foregroundStyle(.secondary).frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("exercise.menu.\(context.name)")
            .accessibilityLabel("Exercise options")
            }
            if isExpanded, !isInlineActive {
                Button {
                    withAnimation { isEditing.toggle() }
                } label: {
                    Text(isEditing ? "Done" : "Edit")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("exercise.edit.\(context.name)")
                .accessibilityLabel(isEditing ? "Done editing \(context.name)" : "Edit \(context.name) sets")
            }
        }
    }

    // MARK: - Context lines

    @ViewBuilder
    private var contextLines: some View {
        if !context.performerContexts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                if let rx = prescriptionText {
                    Text(rx).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("session.rx.\(context.name)")
                }
                ForEach(context.performerContexts, id: \.label) { pc in
                    performerContextView(pc)
                }
            }
        }
    }

    @ViewBuilder
    private func performerContextView(_ pc: SessionRenderModel.PerformerContext) -> some View {
        if context.hasPartners {
            VStack(alignment: .leading, spacing: 1) {
                Text(pc.label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if !pc.lastTimeSets.isEmpty {
                    Text("Last time: " + pc.lastTimeSets.map { setDisplayLine($0) }.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("exercise.lastTime.\(pc.label)")
                }
                if let pr = pc.pr {
                    Text("PR: \(Format.weight(pr, unit: unit)) · \(pc.prRuleName)")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("exercise.pr.\(pc.label)")
                }
            }
        } else {
            if !pc.lastTimeSets.isEmpty {
                Text("Last time: " + pc.lastTimeSets.map { setDisplayLine($0) }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("exercise.lastTime")
            }
            if let pr = pc.pr {
                Text("PR: \(Format.weight(pr, unit: unit)) · \(pc.prRuleName)")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("exercise.pr")
            }
        }
    }

    private func setDisplayLine(_ set: SessionRenderModel.SetDisplay) -> String {
        if set.usesBodyweight {
            let added = set.weight > 0 ? " + \(Format.weightValue(set.weight, unit: unit)) \(unit.abbreviation)" : ""
            return "BW\(added) × \(set.reps)"
        }
        return "\(Format.weightValue(set.weight, unit: unit)) \(unit.abbreviation) × \(set.reps)"
    }

    // MARK: - Column header

    private var setColumnHeader: some View {
        HStack(spacing: SetCol.gap) {
            Text(hasPartners ? "WHO" : "Set")
                .frame(width: hasPartners ? 20 : SetCol.num, alignment: .center)
            Text(unit.abbreviation)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Weight in \(unit.abbreviation)")
            Text("Reps")
                .frame(width: SetCol.reps, alignment: .center)
            Text("RPE")
                .frame(width: SetCol.rpe, alignment: .center)
            Color.clear.frame(width: SetCol.check)
        }
        .font(.caption2).textCase(.uppercase).foregroundStyle(.tertiary)
        .lineLimit(1).minimumScaleFactor(0.5)
        .padding(.horizontal, 2)
    }

    // MARK: - Set rows

    @ViewBuilder
    private func completedSetRow(_ set: SessionRenderModel.SetDisplay) -> some View {
        let number = setNumber(set)
        HStack(spacing: SetCol.gap) {
            if isEditing {
                Button {
                    setToDelete = set
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .frame(width: 26, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("set.delete.\(context.name).\(number)")
                .accessibilityLabel(set.isWarmup ? "Delete warm-up set" : "Delete set \(number)")
            } else if hasPartners {
                performerChipView(set.performedBy)
            } else {
                setIndexBadge(number, isWarmup: set.isWarmup)
            }

            Button { if isEditing { onTapSet(set) } } label: {
                if set.usesBodyweight && set.weight <= 0 {
                    Text("BW").monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(Format.weightValueQuarter(set.weight, unit: unit))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("set.editWeight.\(context.name).\(number)")

            Button { if isEditing { onTapSet(set) } } label: {
                Text("\(set.reps)").monospacedDigit().frame(width: SetCol.reps)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("set.editReps.\(context.name).\(number)")

            Button { if isEditing { onTapSet(set) } } label: {
                rpeBadge(set)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("set.editRPE.\(context.name).\(number)")

            if prSetIDs.contains(set.setID) {
                Image(systemName: "trophy.fill").foregroundStyle(.orange)
                    .frame(width: SetCol.check)
                    .accessibilityIdentifier("set.prBadge")
                    .accessibilityLabel("Personal record")
            } else {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
                    .frame(width: SetCol.check)
                    .accessibilityLabel("Set completed")
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu { setRowMenu(set) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("set.row.\(context.name).\(number)")
    }

    @ViewBuilder
    private func rpeBadge(_ set: SessionRenderModel.SetDisplay) -> some View {
        if let rpe = set.rpe, !set.isWarmup {
            Text("\(Int(rpe.rounded()))")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .padding(.horizontal, 3).padding(.vertical, 1)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 3))
                .accessibilityIdentifier("set.rpe.\(context.name).\(setNumber(set))")
                .accessibilityLabel("RPE \(Int(rpe.rounded()))")
        } else {
            Color.clear.frame(width: SetCol.rpe)
        }
    }

    private func setNumber(_ set: SessionRenderModel.SetDisplay) -> String {
        if set.isWarmup { return "" }
        let workingBefore = context.sets.prefix { $0.setID != set.setID }.filter { !$0.isWarmup }
        return String(workingBefore.count + 1)
    }

    // MARK: - Pending rows

    @ViewBuilder
    private func pendingRow(pending: SessionRenderModel.PendingSetDisplay) -> some View {
        Button { onTapPending(pending) } label: {
            HStack(spacing: SetCol.gap) {
                if hasPartners {
                    performerChipView(pending.performerID.flatMap { id in
                        context.performerContexts.first { $0.performerID == id }.map {
                            SessionRenderModel.PerformerRef(personID: id, isMe: $0.isMe, name: $0.label)
                        }
                    })
                } else {
                    setIndexBadge(
                        String(pending.setIndex + 1),
                        isWarmup: false)
                }
                Text("\(pending.targetReps) reps").font(.subheadline).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Color.clear.frame(width: SetCol.reps)
                Color.clear.frame(width: SetCol.rpe)
                Image(systemName: "plus.circle").foregroundStyle(.tint).frame(width: SetCol.check)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("set.pending.\(context.name).\(pending.setIndex + 1)")
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button { onAddSet() } label: {
                Label("Add set", systemImage: "plus").frame(maxWidth: .infinity).lineLimit(1)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("set.add.\(context.name)")

            if !context.sets.isEmpty {
                Button { onRepeat() } label: {
                    Label("Repeat", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).lineLimit(1)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("set.repeat.\(context.name)")
            }
        }
        .controlSize(.regular)
        .padding(.top, 2)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func setRowMenu(_ set: SessionRenderModel.SetDisplay) -> some View {
        Button { onTapSet(set) } label: {
            Label("Edit set", systemImage: "pencil")
        }
        Button {
            // toggle warmup handled by SessionView
            onTapSet(set) // bail out for now — warmup toggle is a session-level action
        } label: {
            Label(set.isWarmup ? "Mark as working set" : "Mark as warm-up",
                  systemImage: set.isWarmup ? "flame" : "flame.fill")
        }
    }

    // MARK: - Shared helpers

    @ViewBuilder
    private func setIndexBadge(_ label: String, isWarmup: Bool) -> some View {
        Group {
            if isWarmup {
                Text("W").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                    .frame(width: 22, height: 22).background(.orange.opacity(0.15), in: Circle())
            } else {
                Text(label).font(.subheadline.weight(.medium)).monospacedDigit()
            }
        }
        .frame(width: SetCol.num, alignment: .leading)
    }

    @ViewBuilder
    private func performerChipView(_ ref: SessionRenderModel.PerformerRef?) -> some View {
        let label = ref?.isMe ?? true ? "M" : String((ref?.name ?? "?").prefix(1)).uppercased()
        let color: Color = {
            guard let r = ref, !r.isMe else { return .accentColor }
            let palette: [Color] = [.purple, .teal, .pink, .indigo, .orange, .mint]
            return palette[abs(r.personID.hashValue) % palette.count]
        }()
        Text(label)
            .font(.caption2.weight(.semibold)).foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color, in: Circle())
            .accessibilityIdentifier("set.performer.\(ref?.isMe ?? true ? "Me" : (ref?.name ?? "?"))")
    }
}
