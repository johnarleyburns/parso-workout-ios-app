import SwiftUI
import SwiftData
import CadenceCore

/// Settings-owned training partner roster. Archiving keeps historical set
/// attribution but removes the person from every future partner picker.
struct TrainingPartnersSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Person> { !$0.isMe && !$0.isArchived },
           sort: \Person.name) private var trainingPartners: [Person]

    var body: some View {
        Section {
            if trainingPartners.isEmpty {
                Text("No training partners yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(trainingPartners) { partner in
                    HStack {
                        Label(partner.name, systemImage: "person.fill")
                        Spacer()
                        Button {
                            partner.isArchived = true
                            partner.updatedAt = Date()
                            try? modelContext.save()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete \(partner.name)")
                        .accessibilityIdentifier("settings.partner.delete.\(partner.name)")
                    }
                }
            }
        } header: {
            Text("Training partners")
                .font(.headline)
                .accessibilityIdentifier("settings.section.partners")
        }
    }
}
