import SwiftUI
import CadenceCore

struct CoachAboutView: View {
    var body: some View {
        List {
            Section {
                Text("Cladiron's coach is a deterministic, on-device rule engine — not a cloud AI. It reads the workouts and assessments you log and reasons over a curated knowledge base of published strength and hypertrophy science.")
                    .font(.subheadline)
            }

            Section("What it analyzes") {
                row("calendar.badge.clock", "Trailing 7 days",
                    "Working sets per body part, training frequency, intensity distribution, RPE, and per-lift estimated 1RM trends.")
                row("clock.arrow.circlepath", "Prior 7 days",
                    "Compared to the trailing week to detect rising, flat, or declining strength trends (with a 2% noise floor).")
                row("tray.full", "All history",
                    "Best-ever estimated 1RM for each lift, assessment baselines, and days since your last session.")
                row("checklist", "Assessments",
                    "Full longitudinal series for strength, endurance, and cardio tests — baseline to latest, with minimal-detectable-change filtering.")
            }

            Section("When it updates") {
                row("bolt", "Live",
                    "The coach recomputes from scratch every time the Home screen renders. There is no cache — it always reflects the current state of your data.")
                row("square.and.pencil", "Edit a past workout",
                    "The recommendation updates immediately. Changed sets, reps, or weights are picked up on the next Home render.")
                row("flag.checkered", "Finish a workout",
                    "The new session is included right away — the coach may switch from \"add a rep\" to \"add load\" or recommend a deload.")
            }

            Section("How your settings affect it") {
                row("target", "Training goal",
                    "Strength: favors heavy loads (>=80% e1RM). Hypertrophy: targets moderate loads with controlled RIR. Endurance: flags excessive heavy work.")
                row("person.fill", "Experience level",
                    "Scales the weekly volume targets (MEV/MAV/MRV) per body part. Beginners need fewer sets; advanced lifters tolerate more.")
            }

            Section {
                ForEach(CitationRegistry.all) { citation in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(citation.title)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(citation.authors), \(String(citation.year))")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(citation.source)
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Published studies")
            } footer: {
                Text("Every insight and recommendation cites one of these studies. Tap \"The science\" on any coach card to see which one and why.")
            }

            Section {
                Text("Coaching, not medical advice.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("About the Coach")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach.about")
    }

    private func row(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
