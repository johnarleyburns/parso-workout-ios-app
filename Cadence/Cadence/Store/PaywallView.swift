import SwiftUI
import StoreKit
import CadenceCore

/// The Cladiron Pro paywall. Presented from the Coach preview and the onboarding
/// funnel. Everything else in the app is free forever — this unlocks only the
/// coaching layer (monetization plan §4.4).
struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Context copy shown at the top (e.g. "Your program is ready").
    var headline: String = "Unlock your Coach"
    var subheadline: String = "Your program adapts to every set you log — and cites the research behind it."

    @State private var selection: ProProductID.Selection = .annual
    @State private var working = false
    @State private var pendingMessage: String?
    @State private var errorMessage: String?

    private let privacyURL = URL(string: "https://parso.guru/cladiron/privacy")!
    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    valueProps
                    planOptions
                    purchaseButton
                    freeForeverNote
                    legalRow
                }
                .padding()
            }
            .background { CadenceGlassBackdrop(tint: .green) }
            .navigationTitle("Cladiron Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { dismiss() }
                        .accessibilityIdentifier("paywall.dismiss")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Restore") { Task { await restore() } }
                        .accessibilityIdentifier("paywall.restore")
                }
            }
            .alert("Purchase pending", isPresented: Binding(get: { pendingMessage != nil }, set: { if !$0 { pendingMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(pendingMessage ?? "") }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        .accessibilityIdentifier("paywall")
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "figure.mind.and.body")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text(headline)
                .font(.title.bold())
                .accessibilityIdentifier("paywall.headline")
            Text(subheadline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: 12) {
            prop("wand.and.stars", "Builds your program",
                 "A structured plan matched to your goals, equipment, and schedule.")
            prop("slider.horizontal.3", "Adjusts every set",
                 "Autoregulates load and volume from your logged performance and recovery.")
            prop("book.closed", "Cites the science",
                 "Every recommendation links to the published research behind it.")
            prop("arrow.triangle.2.circlepath", "Quarterly research updates",
                 "New meta-analyses and protocols ship as free updates while you're Pro.")
        }
    }

    private func prop(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.green)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var planOptions: some View {
        VStack(spacing: 10) {
            if let annual = store.annual {
                planRow(.annual, product: annual,
                        title: "Annual", badge: trialBadge,
                        subtitle: "Best value")
            }
            if let lifetime = store.lifetime {
                planRow(.lifetime, product: lifetime,
                        title: "Lifetime", badge: foundingBadge(lifetime),
                        subtitle: "Pay once, keep forever")
            }
            if let monthly = store.monthly {
                planRow(.monthly, product: monthly,
                        title: "Monthly", badge: nil,
                        subtitle: "Flexible, cancel anytime")
            }
            if store.products.isEmpty {
                Text("Products are loading…")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
        }
    }

    private func planRow(_ option: ProProductID.Selection, product: Product,
                         title: String, badge: String?, subtitle: String) -> some View {
        let selected = selection == option
        return Button {
            selection = option
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.green, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(product.displayPrice).font(.headline)
                    Text(periodSuffix(option)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding()
            .cadenceGlassCard(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                tint: selected ? .green : .gray)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall.plan.\(option.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var purchaseButton: some View {
        VStack(spacing: 6) {
            Button {
                Task { await purchase() }
            } label: {
                Group {
                    if working {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaTitle).font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .cadenceGlassButton(prominent: true, tint: .green)
            .disabled(working || selectedProduct == nil)
            .accessibilityIdentifier("paywall.purchase")

            Text(renewalTerms)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var freeForeverNote: some View {
        Text("Everything else in Cladiron is free forever. No ads. No account. No tracking. Open source.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }

    private var legalRow: some View {
        HStack(spacing: 16) {
            Link("Privacy Policy", destination: privacyURL)
            Link("Terms of Use", destination: termsURL)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Derived copy

    private var selectedProduct: Product? {
        switch selection {
        case .annual: return store.annual
        case .monthly: return store.monthly
        case .lifetime: return store.lifetime
        }
    }

    private var trialBadge: String? {
        store.annualIntroOffer != nil ? "30 days free" : nil
    }

    private func foundingBadge(_ lifetime: Product) -> String? {
        lifetime.price < Decimal(69.99) ? "Founding price" : nil
    }

    private func periodSuffix(_ option: ProProductID.Selection) -> String {
        switch option {
        case .annual: return "per year"
        case .monthly: return "per month"
        case .lifetime: return "one time"
        }
    }

    private var ctaTitle: String {
        switch selection {
        case .annual: return store.annualIntroOffer != nil ? "Start 30-day free trial" : "Subscribe"
        case .monthly: return "Subscribe"
        case .lifetime: return "Unlock Lifetime"
        }
    }

    private var renewalTerms: String {
        switch selection {
        case .annual:
            let price = store.annual?.displayPrice ?? ""
            return store.annualIntroOffer != nil
                ? "1 month free, then \(price)/year. Renews automatically until cancelled in Settings."
                : "\(price)/year. Renews automatically until cancelled in Settings."
        case .monthly:
            let price = store.monthly?.displayPrice ?? ""
            return "\(price)/month. Renews automatically until cancelled in Settings."
        case .lifetime:
            return "One-time purchase. No subscription."
        }
    }

    // MARK: - Actions

    private func purchase() async {
        guard let product = selectedProduct else { return }
        working = true
        defer { working = false }
        switch await store.purchase(product) {
        case .success(let entitlement):
            if entitlement.isPro { dismiss() }
        case .pending:
            pendingMessage = "Your purchase needs approval before the Coach unlocks. It'll activate once approved."
        case .userCancelled:
            break
        case .failed(let message):
            errorMessage = message
        }
    }

    private func restore() async {
        working = true
        defer { working = false }
        await store.restore()
        if store.isPro { dismiss() }
    }
}

extension ProProductID {
    /// The three selectable plans on the paywall.
    enum Selection: String, CaseIterable {
        case annual, monthly, lifetime
    }
}
