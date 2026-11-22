import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

/// Watch redesign §5 C2 — partners as an ordered rotation: who's lifting, who's next; tap to make
/// someone current. Rotation advances automatically after each logged set (D-W3).
struct WatchPartnersView: View {
    let model: WatchStrengthFlowModel
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Person> { !$0.isMe }, sort: \Person.name) private var people: [Person]
    @State private var newPartner = ""

    var body: some View {
        List {
            Section("Partners") {
                if model.performerOptions.isEmpty {
                    Text("No partner")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("watchPartners.empty")
                } else {
                    ForEach(model.performerOptions) { option in
                        Button {
                            WatchHaptics.tap()
                            model.selectPerformer(at: option.index)
                            close()
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
            }
            Section {
                TextField("Add partner", text: $newPartner)
                    .onSubmit {
                        addPartner(newPartner)
                    }
                    .accessibilityIdentifier("watchPartners.add")

                // Everyone the user has trained with before, immediately
                // available without typing. Already-active partners are omitted.
                ForEach(addablePartnerNames, id: \.self) { name in
                    Button {
                        addPartner(name)
                    } label: {
                        Label(name, systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("watchPartners.previous.\(name)")
                }
            } header: {
                Text("Add partner")
            }
        }
        .navigationTitle("Partners")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    WatchHaptics.tap()
                    close()
                }
                .accessibilityIdentifier("watchPartners.done")
            }
        }
    }

    private var addablePartnerNames: [String] {
        WatchPartnerDirectory.addable(allNames: people.map(\.name),
                                      currentNames: model.performerOptions.map(\.name))
    }

    private var nextPerformerIndex: Int {
        guard !model.performerOptions.isEmpty else { return 0 }
        return (model.currentPerformerIndex + 1) % model.performerOptions.count
    }

    private func addPartner(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        newPartner = ""
        guard !name.isEmpty else { return }
        WatchHaptics.tap()
        model.addPartner(named: name)
    }

    private func close() {
        // The workout pager can also route here via model.stage; leave through
        // the flow in that case so the user lands back on the plan, never stuck.
        if case .partners = model.stage {
            model.goBackToHome()
        } else {
            dismiss()
        }
    }
}
