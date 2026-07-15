import SwiftUI
import CadenceCore

// MARK: - Partner sheets (extracted from SessionView to stay under LOC ceiling)

extension SessionView {

    // MARK: Quick-add partner (recent + list + new name)

    /// Quick-add sheet opened from the + button in the partner bar. Shows the
    /// most recent partner at the top, a scrollable list of all previous partners,
    /// and a text field for entering a custom name.
    var addPartnerSheet: some View {
        NavigationStack {
            List {
                if !recentPartners.isEmpty {
                    Section {
                        ForEach(recentPartners.prefix(3)) { p in
                            Button {
                                togglePartnerScope(p)
                            } label: {
                                HStack {
                                    performerChip(p)
                                    Text(p.name).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle").foregroundStyle(.tint)
                                }
                            }
                            .accessibilityIdentifier("partner.quick.add.\(p.name)")
                            .accessibilityLabel("Add \(p.name) to session")
                        }
                    } header: {
                        Text("Recent")
                    }
                }

                Section {
                    ForEach(allPeople.filter { !$0.isMe }) { p in
                        Button { togglePartnerScope(p) } label: {
                            HStack {
                                Text(p.name).foregroundStyle(.primary)
                                Spacer()
                                if session.activePartnerIDs.contains(p.id.uuidString) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityIdentifier("partner.quick.row.\(p.name)")
                    }
                    HStack {
                        TextField("New partner name", text: $newPartnerName)
                            .accessibilityIdentifier("partner.quick.nameField")
                        Button("Add") { addAndScopePartner() }
                            .disabled(newPartnerName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("partner.quick.add")
                    }
                } header: {
                    Text("Training partners")
                } footer: {
                    Text("Partners are optional. Their sets are recorded separately and kept out of your PRs and Apple Health.")
                }
            }
            .navigationTitle("Add Partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { addPartnerPresented = false }
                        .accessibilityIdentifier("partner.quick.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Manage partners (opt-in roster, field-testing §04 bug fix)

    /// Discoverable partner management: check/uncheck who is in the session and
    /// add new partners. Unchecking the last partner correctly returns to solo
    /// (partners are opt-in — an empty roster never re-shows everyone).
    var managePartnersSheet: some View {
        NavigationStack {
            List {
                if hasPartners {
                    Section {
                        ForEach(Array(roster.enumerated()), id: \.element.id) { index, person in
                            HStack {
                                performerChip(person)
                                Text(person.isMe ? "Me" : person.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Button {
                                    moveRosterMember(from: index, by: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .disabled(index == 0)
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("partner.order.up.\(person.isMe ? "Me" : person.name)")
                                .accessibilityLabel("Move \(person.isMe ? "Me" : person.name) earlier")

                                Button {
                                    moveRosterMember(from: index, by: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .disabled(index >= roster.count - 1)
                                .buttonStyle(.borderless)
                                .accessibilityIdentifier("partner.order.down.\(person.isMe ? "Me" : person.name)")
                                .accessibilityLabel("Move \(person.isMe ? "Me" : person.name) later")
                            }
                        }
                    } header: {
                        Text("Order")
                    } footer: {
                        Text("The logger rotates through this order after each saved set.")
                    }
                }

                Section {
                    ForEach(allPeople.filter { !$0.isMe }) { p in
                        Button { togglePartnerScope(p) } label: {
                            HStack {
                                Text(p.name).foregroundStyle(.primary)
                                Spacer()
                                if session.activePartnerIDs.contains(p.id.uuidString) {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .accessibilityIdentifier("partner.manage.row.\(p.name)")
                    }
                    HStack {
                        TextField("New partner name", text: $newPartnerName)
                            .accessibilityIdentifier("partner.manage.nameField")
                        Button("Add") { addAndScopePartner() }
                            .disabled(newPartnerName.trimmingCharacters(in: .whitespaces).isEmpty)
                            .accessibilityIdentifier("partner.manage.add")
                    }
                } header: {
                    Text("Training partners")
                } footer: {
                    Text("Partners are optional. Their sets are recorded separately and kept out of your PRs and Apple Health.")
                }
            }
            .navigationTitle("Partners")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { managePartnersPresented = false }
                        .accessibilityIdentifier("partner.manage.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
