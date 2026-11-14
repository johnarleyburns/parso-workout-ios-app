import SwiftUI
import CadenceCore
import CadenceFeatures

/// RPE choices presented from More; `onSelect(nil)` clears the rating.
struct WatchRPEPickerSheet: View {
    let onSelect: (Int?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button("None") { onSelect(nil) }.accessibilityIdentifier("watchEffort.none")
                ForEach(WatchRPESelection.options, id: \.self) { value in
                    Button("RPE \(value)") { onSelect(value) }
                        .accessibilityIdentifier("watchEffort.\(value)")
                }
            }
            .navigationTitle("RPE")
        }
    }
}

/// "Set details" section of More: the RPE row plus the coach guidance moved off the set card.
struct WatchSetDetailsSection: View {
    let model: WatchStrengthFlowModel
    @Binding var showingRPEPicker: Bool

    var body: some View {
        Section("Set details") {
            Button { showingRPEPicker = true } label: {
                HStack {
                    Text("RPE")
                    Spacer()
                    Text(WatchRPESelection.rowText(mode: model.effortMode, value: model.effortValue))
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("watchEffort.value")
            if let line = WatchRPESelection.coachGuidance(from: model.setCardState?.planLine) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coach guidance").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    WatchCoachLineView(line: line)
                }
                .accessibilityElement(children: .contain)
            }
        }
    }
}
