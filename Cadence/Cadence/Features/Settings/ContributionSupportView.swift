import SwiftUI
import StoreKit

/// One-time contribution tips. If the user has ever contributed, the view shows a
/// thank-you and invites another tip. If no products load (App Store Connect not
/// configured yet) it shows a gentle placeholder. Reached from Settings and from
/// the Home contribution toast.
struct ContributionSupportView: View {
    /// `@Observable` store — reading its properties here tracks changes for updates.
    let store: ContributionStore
    @Environment(\.dismiss) private var dismiss
    var showsDoneButton = false

    var body: some View {
        List {
            Section {
                if store.isSupporter {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Thank you for your support!", systemImage: "heart.fill")
                            .foregroundStyle(.pink)
                            .font(.headline)
                        Text("Cladiron stays independent, privacy-first, and ad-free because of people like you. Want to chip in again?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Cladiron is proprietary, privacy-first, and ad-free. An optional contribution supports continued development — it's never required, and it unlocks nothing you don't already have.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if !store.products.isEmpty {
                Section("Tips") {
                    ForEach(store.products, id: \.id) { purchaseRow($0) }
                }
            } else {
                Section {
                    Text("Support options aren't available yet. Please check back soon.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Restore Purchases") { Task { await store.restore() } }
                    .accessibilityIdentifier("contribution.restore")
            } footer: {
                Text("Tips are one-time purchases. By contributing you agree to the Terms and Privacy Policy (see About).")
            }
        }
        .navigationTitle("Support Cladiron")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("contribution.support")
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    @ViewBuilder
    private func purchaseRow(_ product: Product) -> some View {
        Button {
            Task { await store.purchase(product) }
        } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(.body).foregroundStyle(.primary)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 12)
                if store.purchasingID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice).fontWeight(.semibold)
                }
            }
        }
        .disabled(store.purchasingID != nil)
        .accessibilityIdentifier("contribution.buy.\(product.id)")
        .accessibilityLabel("Contribute \(product.displayName) for \(product.displayPrice)")
        .accessibilityHint(product.description)
    }
}
