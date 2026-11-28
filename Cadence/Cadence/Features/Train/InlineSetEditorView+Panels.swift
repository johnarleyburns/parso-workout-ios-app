import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// History, partner entry and effort moved out of the set-entry body into the
/// header overflow menu; these are the sheet contents.
extension InlineSetEditorView {
    var selectedDefault: InlineEditorConfig.PerformerDefault? {
        config.performerDefaults.first { $0.performerID == performerID }
    }

    /// Per-selected-performer history: prior-session sets on this movement
    /// ("Last time") and the most recent set logged today ("Last set today").
    /// Decision D8: an explicit "No previous history for <name>" line satisfies
    /// "always show (if any)" and is assertable in the smoke test.
    var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("History").font(.headline)
                Spacer()
                Button(showHistory ? "Hide History" : "Show History") {
                    withAnimation(.snappy(duration: 0.2)) { showHistory.toggle() }
                    Haptics.selection()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityIdentifier("setEditor.history.toggle")
            }
            if showHistory {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("setEditor.history")
    }

    var selectedPerformerName: String {
        guard let performerID else { return "Me" }
        return config.roster.first(where: { $0.personID == performerID })?.name ?? String(localized: "Partner")
    }

    var historyLastTimeText: String? {
        if let text = selectedDefault?.lastTimeText { return text }
        // The owner's card history is the page's source of truth. Use it when
        // the per-performer default is missing rather than showing a false
        // "No previous history".
        return performerID == nil ? config.lastTimeText : nil
    }

    var performerSection: some View {
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
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
    var effortSection: some View {
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
    func adjustEffort(by delta: Double) {
        draft.adjustEffort(by: delta)
        Haptics.selection()
    }
}
