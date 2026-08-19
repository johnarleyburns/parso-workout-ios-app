import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// Training partners and performer order, as a Home-rhythm card
/// (field test 2026-08-18 #5 — the plan editor left `List` behind).
struct WorkoutPlanPartnerSection: View {
    @Binding var partnerIDs: [UUID]
    let isEditing: Bool
    let allPeople: [Person]
    /// Called whenever the roster changes, so the editor can re-resolve every
    /// partner's plan (field test 2026-08-18 #4).
    var onRosterChanged: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @State private var newPartnerName = ""
    /// The full picker is always open in Edit mode; in view mode the user
    /// reveals it with `+`, so a read-only plan is not a wall of controls.
    @State private var pickerRevealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.sectionSpacing)) {
            partnerCard
            if isEditing && !selectedPartnerPeople.isEmpty { orderCard }
        }
    }

    private var partnerCard: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardHeadingSpacing)) {
            heading
            if showsPicker {
                VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                    ForEach(partnerPeople) { person in
                        partnerRow(person)
                    }
                    addPartnerRow
                    Text("Partners are optional — leave everyone unchecked to train solo.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .workoutPlanCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.partners")
    }

    /// `Training partners   Solo  +` / `Training partners   Alex x  +` — the
    /// roster is editable from the plan itself, not only from Edit mode.
    private var heading: some View {
        HStack(spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
            Text("Training partners").font(.headline)
            Spacer(minLength: 0)
            if selectedPartnerPeople.isEmpty {
                Text("Solo").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.partnerChip.solo")
            } else {
                ForEach(selectedPartnerPeople) { person in
                    partnerChip(person)
                }
            }
            if !isEditing {
                Button {
                    Haptics.selection()
                    withAnimation { pickerRevealed.toggle() }
                } label: {
                    Image(systemName: pickerRevealed ? "minus.circle" : "plus.circle")
                        .imageScale(.large)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -8)
                .padding(.vertical, -8)
                .accessibilityIdentifier("editor.showPartnerPicker")
                .accessibilityLabel(pickerRevealed ? "Hide partner picker" : "Add a training partner")
            }
        }
    }

    private func partnerChip(_ person: Person) -> some View {
        HStack(spacing: 4) {
            Text(person.name).font(.subheadline)
            Button {
                Haptics.selection()
                toggle(person)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editor.removePartner.\(person.name)")
            .accessibilityLabel("Remove \(person.name)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.quaternary))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.partnerChip.\(person.name)")
    }

    private var showsPicker: Bool { isEditing || pickerRevealed }

    private func partnerRow(_ person: Person) -> some View {
        HStack {
            Text(person.name)
            Spacer()
            if partnerIDs.contains(person.id) {
                Image(systemName: "checkmark").foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(person) }
        .accessibilityIdentifier("editor.partner.\(person.name)")
    }

    private var addPartnerRow: some View {
        HStack {
            TextField("New partner name", text: $newPartnerName)
                .accessibilityIdentifier("editor.newPartnerName")
            Button("Add") { addPartner() }
                .buttonStyle(.borderless)
                .disabled(newPartnerName.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("editor.addPartner")
        }
    }

    private var orderCard: some View {
        VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardHeadingSpacing)) {
            Text("Performer order").font(.headline)
            VStack(alignment: .leading, spacing: CGFloat(LayoutMetrics.cardRowSpacing)) {
                ForEach(Array(editorRoster.enumerated()), id: \.element.id) { index, person in
                    orderRow(person, at: index)
                }
                Text("The logger rotates through this order after each saved set.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .workoutPlanCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.performerOrder")
    }

    private func orderRow(_ person: Person, at index: Int) -> some View {
        let name = person.isMe ? "Me" : person.name
        return HStack {
            Text(name)
            Spacer()
            Button { moveRosterMember(from: index, by: -1) } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(index == 0)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("editor.partnerOrder.up.\(name)")
            .accessibilityLabel("Move \(name) earlier")
            Button { moveRosterMember(from: index, by: 1) } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(index >= editorRoster.count - 1)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("editor.partnerOrder.down.\(name)")
            .accessibilityLabel("Move \(name) later")
        }
    }

    private func toggle(_ person: Person) {
        if let idx = partnerIDs.firstIndex(of: person.id) {
            partnerIDs.remove(at: idx)
            partnerIDs = normalizedPartnerIDs(partnerIDs)
        } else {
            var ids = explicitPartnerIDs()
            ids.append(person.id)
            partnerIDs = normalizedPartnerIDs(ids)
        }
        onRosterChanged()
    }

    private func addPartner() {
        let name = newPartnerName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty,
           let p = try? WorkoutRepository.findOrCreatePerson(named: name, in: modelContext),
           !partnerIDs.contains(p.id) {
            var ids = explicitPartnerIDs()
            ids.append(p.id)
            partnerIDs = normalizedPartnerIDs(ids)
        }
        newPartnerName = ""
        onRosterChanged()
    }

    private var owner: Person? { allPeople.first(where: \.isMe) }

    private var partnerPeople: [Person] { allPeople.filter { !$0.isMe } }

    private var selectedPartnerPeople: [Person] {
        let ids = Set(partnerIDs)
        return partnerPeople.filter { ids.contains($0.id) }
    }

    private var editorRoster: [Person] {
        guard !selectedPartnerPeople.isEmpty else { return owner.map { [$0] } ?? [] }
        let peopleByID = Dictionary(allPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let selectedIDs = Set(selectedPartnerPeople.map(\.id))
        var seen = Set<UUID>()
        let ordered = partnerIDs.compactMap { id -> Person? in
            guard seen.insert(id).inserted else { return nil }
            return peopleByID[id]
        }
        if ordered.contains(where: \.isMe) {
            return ordered.filter { $0.isMe || selectedIDs.contains($0.id) }
        }
        return (owner.map { [$0] } ?? []) + selectedPartnerPeople
    }

    private func explicitPartnerIDs() -> [UUID] {
        guard !selectedPartnerPeople.isEmpty else {
            return owner.map { [$0.id] } ?? []
        }
        let ids = editorRoster.map(\.id)
        return ids.isEmpty ? partnerIDs : ids
    }

    private func normalizedPartnerIDs(_ ids: [UUID]) -> [UUID] {
        EditablePlan.normalizedPartnerIDs(ids, ownerID: owner?.id)
    }

    private func moveRosterMember(from index: Int, by offset: Int) {
        var ids = explicitPartnerIDs()
        let target = index + offset
        guard ids.indices.contains(index), ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
        partnerIDs = normalizedPartnerIDs(ids)
        onRosterChanged()
    }
}
