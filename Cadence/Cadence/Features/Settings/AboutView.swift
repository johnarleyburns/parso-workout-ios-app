import SwiftUI

/// The About screen (reached from Settings): what Cladiron stands for — its
/// privacy principles and the transparent, science-based coaching methodology —
/// plus the app/open-data licensing boundary, copyright, and a link to the
/// online privacy policy.
/// "Cladiron" is the public product name; the internal target is still "Cadence".
struct AboutView: View {
    private let privacyURL = URL(string: "https://parso.guru/cladiron_privacy")!
    private let siteURL = URL(string: "https://www.parso.guru")!
    private let sourceURL = URL(string: "https://github.com/johnarleyburns/parso-workout-ios-app/blob/main/LICENSE")!
    private let exerciseDBURL = URL(string: "https://github.com/yuhonas/free-exercise-db")!
    private let exerciseAnnotationURL = URL(string: "https://github.com/johnarleyburns/free-exercise-db-plusplus")!
    private let enginePackageURL = URL(string: "https://github.com/johnarleyburns/free-exercise-db-plusplus")!
    private let enginePackageVersion = "1.16.0"

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
                licensing
                    .padding(.horizontal, 20).padding(.vertical, 24)
                Divider()
                exerciseLibrary
                    .padding(.horizontal, 20).padding(.vertical, 24)
                Divider()
                privacy
                    .padding(.horizontal, 20).padding(.vertical, 24)
                Divider()
                medicalDisclaimer
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
                    .scaledSystemFont(32, relativeTo: .largeTitle, weight: .medium)
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
            principle("lock.open", "Open source & privacy-first",
                      "Cladiron is free and open-source software. Its privacy commitments are auditable in the public source and reinforced by an on-device, serverless design, clear permissions, data export, and a published privacy policy.")
            principle("square.and.arrow.up", "Your data, fully portable",
                      "Your history lives on your devices and syncs through your private iCloud, never a Cladiron server. You can export a complete backup and import it into a fresh install, so your data is never locked in.")
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
            Text("Cladiron's coach is a deterministic, on-device expert system, not a cloud service or black box. It reads the workouts and assessments you log and reasons over a curated, citable knowledge base of strength and hypertrophy science.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("From that it derives concrete next steps — weekly volume versus evidence-based landmarks, estimated-1RM trends, double-progression load and rep targets, deloads, and periodic strength assessments to track progress like a study's pre/post. The app shows its reasoning and citations so you can always see why it suggests what it does.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Licensing

    private var licensing: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Licensing").font(.title3.bold())
            Text("Cladiron is free and open-source software, Copyright © 2026 Parso Consulting / John Arley Burns, released under the GNU GPLv3-or-later with the Cladiron App Store Exception.")
                .font(.body).foregroundStyle(.secondary)
            Text("The application source is public so anyone can inspect, modify, and redistribute it under those terms. Cladiron's name, icon, logo, screenshots, and other brand assets remain protected; see TRADEMARKS.md. Cladiron is built on the open free-exercise-db-plusplus project, whose database, annotations, and related tooling remain available under their own license.")
                .font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link("View the GPLv3 license and App Store Exception", destination: sourceURL)
                .font(.body).accessibilityIdentifier("about.licenseLink")
            Link("View the open free-exercise-db-plusplus project", destination: exerciseAnnotationURL)
                .font(.body).accessibilityIdentifier("about.dbppLink")
            Text("Made by Parso Consulting — an independent software studio.")
                .font(.body).foregroundStyle(.secondary).padding(.top, 6)
            Link("parso.guru", destination: siteURL).font(.body)
        }
    }

    // MARK: Exercise Library

    private var exerciseLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Exercise Library").font(.title3.bold())
            Text("Exercise source data and imagery come from free-exercise-db; free-exercise-db-plusplus adds evidence-audited annotations, a 20-muscle ontology, movement classifications, and the on-device training engine. Everything is bundled on-device.")
                .font(.body).foregroundStyle(.secondary)
            Link(destination: exerciseDBURL) {
                HStack(spacing: 6) {
                    Text("View on GitHub")
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
                .font(.body)
            }
            Link(destination: exerciseAnnotationURL) {
                HStack(spacing: 6) {
                    Text("View free-exercise-db++ annotations on GitHub")
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
                .font(.body)
            }
            Text("The open free-exercise-db-plusplus package is pinned at version \(enginePackageVersion). Cladiron's interface, app-specific coaching composition, persistence, HealthKit integration, and Apple-platform experiences are covered by the GPLv3-or-later terms and App Store Exception above.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: enginePackageURL) {
                HStack(spacing: 6) {
                    Text("View DB++ Swift package")
                    Image(systemName: "arrow.up.right").font(.caption2)
                }
                .font(.body)
            }
            Text("License: Unlicense (public domain)")
                .font(.footnote).foregroundStyle(.secondary)
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
            Text("We don't collect, transmit, or sell your data. Cladiron runs on your devices; your training log can sync through your private iCloud but is never stored on or visible to a Cladiron server. Apple Health, Bluetooth heart-rate, and location data stay within your Apple devices and services, and are used only with your permission.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Location is used only while you're recording an outdoor run, walk, or ride. It keeps mapping your route in the background — shown by the blue status-bar indicator — and stops the moment you end the workout. Cladiron never tracks your location at any other time.")
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

    // MARK: Medical disclaimer

    private var medicalDisclaimer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "stethoscope")
                    .font(.title3).foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Coaching, Not Medical Advice").font(.title3.bold())
            }
            Text("Cladiron's fitness tests, scores, and training recommendations are general educational guidance, not medical advice, diagnosis, or treatment. It is not a medical device. Always consult a qualified healthcare professional before starting or changing an exercise program, and stop and seek care if you feel pain, dizziness, or other warning signs.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("about.medicalDisclaimer")
    }

    // MARK: Disclaimer

    private var disclaimer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Image Credits").font(.title3.bold())
            Text("Splash image: \"Fitness exercise\" by Robertgombos, licensed under CC BY-SA 4.0.")
                .font(.footnote).foregroundStyle(.secondary)
            Link("View on Wikimedia Commons",
                 destination: URL(string: "https://commons.wikimedia.org/wiki/File:Fitness_exercise.jpg")!)
                .font(.footnote)
            Text("Coach illustrations: VideoPlasty, licensed under CC BY-SA 4.0. Used unchanged from Wikimedia Commons.")
                .font(.footnote).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Link("Lifting dumbbells", destination: URL(string: "https://commons.wikimedia.org/wiki/File:Coach_Lifting_Dumbbells_Cartoon.svg")!)
                Link("Using a stopwatch", destination: URL(string: "https://commons.wikimedia.org/wiki/File:Coach_Using_a_Stopwatch_Cartoon.svg")!)
                Link("Using a whistle", destination: URL(string: "https://commons.wikimedia.org/wiki/File:Coach_Using_a_Whistle_Cartoon.svg")!)
                Link("Yelling", destination: URL(string: "https://commons.wikimedia.org/wiki/File:Coach_Yelling_Cartoon.svg")!)
                Link("CC BY-SA 4.0 license", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
            }
            .font(.footnote)
        }
    }
}

#Preview {
    NavigationStack { AboutView() }
}
