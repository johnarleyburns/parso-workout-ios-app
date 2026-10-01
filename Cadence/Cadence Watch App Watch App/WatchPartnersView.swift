import SwiftUI
import CadenceCore
import CadenceFeatures

/// Watch redesign §5 C2 — partners as an ordered rotation: who's lifting, who's next; tap to make
/// someone current. Rotation advances automatically after each logged set (D-W3).
struct WatchPartnersView: View {
    let model: WatchStrengthFlowModel
    @Environment(\.dismiss) private var dismiss
    @State private var newPartner = ""

    var body: some View {
        List {
            Section("Rotation") {
                ForEach(model.performerOptions) { option in
                    Button {
                        WatchHaptics.tap()
                        model.selectPerformer(at: option.index)
                        if case .partners = model.stage { model.goBackToHome() } else { dismiss() }
                    } label: {
                        HStack {
                            Text("\(option.index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            Text(option.name).font(.body)
                            Spacer()
                            if option.index == model.currentPerformerIndex {
                                Text("Lifting").font(.caption2).foregroundStyle(WatchTone.accent)
                            } else if option.index == nextPerformerIndex {
                                Text("Next").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(RoundedRectangle(cornerRadius: 12)
                        .fill(option.index == model.currentPerformerIndex ? WatchTone.accentSoft : WatchTone.surface))
                    .accessibilityIdentifier("watchPerformer.\(option.name)")
                }
                .onDelete { offsets in
                    WatchHaptics.delete()
                    // Index 0 is the device owner; partners start at 1.
                    for offset in offsets where offset > 0 { model.removePartner(at: offset - 1) }
                }
            }
            Section {
                TextField("Add partner", text: $newPartner)
                    .onSubmit {
                        let name = newPartner.trimmingCharacters(in: .whitespacesAndNewlines)
                        newPartner = ""
                        guard !name.isEmpty else { return }
                        WatchHaptics.tap()
                        model.addPartner(named: name)
                    }
                    .accessibilityIdentifier("watchPartners.add")
            }
        }
        .navigationTitle("Partners")
    }

    private var nextPerformerIndex: Int {
        guard !model.performerOptions.isEmpty else { return 0 }
        return (model.currentPerformerIndex + 1) % model.performerOptions.count
    }
}
