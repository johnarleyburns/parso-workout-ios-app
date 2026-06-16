import SwiftUI

/// The About screen (reached from Settings): what Cladiron stands for — its
/// privacy principles and the transparent, science-based coaching methodology —
/// plus open-source, copyright, and a link to the online privacy policy.
/// "Cladiron" is the public product name; the internal target is still "Cadence".
struct AboutView: View {
    private let privacyURL = URL(string: "https://parso.guru/cladiron_privacy.html")!
    private let sourceURL = URL(string: "https://github.com/johnarleyburns/parso-workout-ios-app")!
    private let siteURL = URL(string: "https://www.parso.guru")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                appHeader
                    .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 28)
                Divider()
                principles
                    .padding(.horizontal, 20).padding(.vertical, 24)
                Divider()
                methodology
                    .padding(.horizontal, 20).padding(.vertical, 24)
                Divider()
                openSource
                    .padding(.horizontal, 20).padding(.vertical, 24)
                Divider()
                privacy
                    .padding(.horizontal, 20).padding(.vertical, 24)
                Divider()
                disclaimer
                    .padding(.horizontal, 20).padding(.vertical, 24)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: App header

    private var appHeader: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [.green, .teal],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Cladiron")
                    .font(.title2.bold())
                    .accessibilityIdentifier("about.title")
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                    Text("Version \(version) (\(build))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Link("© 2026 Parso Consulting", destination: siteURL)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Principles

    private var principles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Our Principles").font(.title3.bold())
            Text("Cladiron is your private, science-based strength coach. It's built on a few commitments we don't compromise on:")
                .font(.body).foregroundStyle(.secondary)
            principle("lock.shield", "Private by design",
                      "Everything runs on your device. There's no account, no server, and nothing about your training is ever sent to us.")
            principle("book.closed", "Science-based & transparent",
                      "Every recommendation comes from published exercise-science research and shows the principle and citation behind it. No black box.")
            principle("dollarsign.circle", "Free & open source",
                      "No subscriptions, no ads, no upsells. The complete source is public, so anyone can verify exactly what it does.")
            principle("icloud", "Your data, your iCloud",
                      "Optional backup and sync go through your own private iCloud — never our servers — and you can export or delete everything at any time.")
        }
    }

    private func principle(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3).foregroundStyle(.tint).frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Methodology

    private var methodology: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How the Coach Works").font(.title3.bold())
            Text("Cladiron's coach is a deterministic, on-device expert engine — \"1980s rule-based AI on modern hardware\" — not a cloud model. It reads the workouts and assessments you log and reasons over a curated, citable knowledge base of strength and hypertrophy science.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("From that it derives concrete next steps — weekly volume versus evidence-based landmarks, estimated-1RM trends, double-progression load and rep targets, deloads, and periodic strength assessments to track progress like a study's pre/post. Because the rules are open and cited, you can always see why it suggests what it does.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Open source

    private var openSource: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Open Source").font(.title3.bold())
            Text("Cladiron is released under the MIT license. The whole app — the logging, the coaching engine, and its knowledge base — is on GitHub for anyone to inspect, learn from, or build on. Issues and contributions are welcome.")
                .font(.body).foregroundStyle(.secondary)
            Link("View source on GitHub", destination: sourceURL)
                .font(.body).accessibilityIdentifier("about.sourceLink")
            Text("Made by Parso Consulting — an independent software studio.")
                .font(.body).foregroundStyle(.secondary).padding(.top, 6)
            Link("parso.guru", destination: siteURL).font(.body)
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Privacy").font(.title3.bold())
                Spacer()
                Link("View Online", destination: privacyURL)
                    .font(.subheadline).accessibilityIdentifier("about.privacyLink")
            }
            Text("We don't collect, transmit, or sell your data — there's nothing to collect, because Cladiron runs entirely on your device. Apple Health, Bluetooth heart-rate, and location data all stay on your device or in your own iCloud, and only with your permission.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: privacyURL) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.raised")
                    Text("Read the full Privacy Policy")
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
                .font(.body)
            }
        }
    }

    // MARK: Disclaimer

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coaching, not medical advice").font(.subheadline.weight(.semibold))
            Text("Cladiron's assessments and recommendations are general training guidance, not medical advice, diagnosis, or treatment. Consult a qualified professional before starting or changing an exercise program.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack { AboutView() }
}
