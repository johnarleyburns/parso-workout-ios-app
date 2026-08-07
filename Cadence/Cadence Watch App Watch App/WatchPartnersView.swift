import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchPartnersView: View {
    let model: WatchStrengthFlowModel

    var body: some View {
        List {
            Section("Lifter") {
                ForEach(model.performerOptions) { option in
                    HStack {
                        Circle()
                            .fill(option.isMe ? Color.green : Color.blue)
                            .frame(width: 20, height: 20)
                            .overlay(Text(String(option.name.prefix(1))).font(.caption2.bold()).foregroundStyle(.white))
                        Text(option.name)
                        Spacer()
                        if option.index == model.currentPerformerIndex {
                            Text("Lifting").font(.caption2).foregroundStyle(.green)
                        } else if option.index == nextPerformerIndex {
                            Text("Up next").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        WatchHaptics.tap()
                        model.selectPerformer(at: option.index)
                    }
                    .accessibilityIdentifier("watchPartners.performer.\(option.name)")
                }
            }

            Section("Partners") {
                ForEach(Array(model.partners.enumerated()), id: \.element.persistentModelID) { idx, partner in
                    HStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 20, height: 20)
                            .overlay(Text(String(partner.name.prefix(1))).font(.caption2.bold()).foregroundStyle(.white))
                        Text(partner.name)
                        Spacer()
                    }
                }
                .onDelete { idxs in
                    WatchHaptics.delete()
                    for i in idxs { model.removePartner(at: i) }
                }
            }

            Section {
                Button {
                    WatchHaptics.tap()
                    model.addPartner(named: "New Partner")
                } label: {
                    Label("Add partner...", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Partners")
    }

    private var nextPerformerIndex: Int {
        guard !model.performerOptions.isEmpty else { return 0 }
        return (model.currentPerformerIndex + 1) % model.performerOptions.count
    }
}
