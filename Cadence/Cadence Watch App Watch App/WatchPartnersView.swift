import SwiftUI
import CadenceCore
import CadenceFeatures

struct WatchPartnersView: View {
    let model: WatchStrengthFlowModel

    var body: some View {
        List {
            ForEach(Array(model.partners.enumerated()), id: \.element.persistentModelID) { idx, partner in
                HStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 20, height: 20)
                        .overlay(Text(String(partner.name.prefix(1))).font(.caption2.bold()).foregroundStyle(.white))
                    Text(partner.name)
                    Spacer()
                    if idx == model.currentPerformerIndex {
                        Text("Lifting").font(.caption2).foregroundStyle(.green)
                    } else if idx == (model.currentPerformerIndex + 1) % (model.partners.count + 1) {
                        Text("Up next").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.selectPerformer(at: idx) }
            }
            .onDelete { idxs in
                for i in idxs { model.removePartner(at: i) }
            }

            Section {
                Button {
                    model.addPartner(named: "New Partner")
                } label: {
                    Label("Add partner...", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Partners")
    }
}
