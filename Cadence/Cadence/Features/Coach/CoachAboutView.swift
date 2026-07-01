import SwiftUI
import CadenceCore

struct CoachAboutView: View {
    var body: some View {
        List {
            Section {
                Text("Cladiron's coach is a recovery-aware, on-device rule engine, not a cloud service or black box. It reads your workouts, cardio (including Apple Watch cardio), and optional readiness check-ins, then chooses an eligible session that fits your balanced weekly plan.")
                    .font(.subheadline)
            }

            Section("What it analyzes") {
                row("calendar.badge.clock", "Rolling 72 hours",
                    "Exact recovery windows per exercise, movement pattern, and body part — unlike calendar-week snapshots, these don't shift at midnight Monday.")
                row("clock.arrow.circlepath", "Rolling 7 days",
                    "Weekly dose: strength days, pattern coverage, moderate-equivalent aerobic minutes vs the 150 min public-health floor.")
                row("tray.full", "Rolling 28 days",
                    "Multi-week trends for volume, per-lift performance, and VO₂max (same protocol only — cross-protocol values are not combined).")
                row("heart.text.square", "Recovery + readiness",
                    "Optional daily readiness check-in (soreness, energy, sleep, stress). Missing readiness keeps conservative default time gates.")
            }

            Section("How it decides") {
                row("shield.checkered", "Hard eligibility gates",
                    "Before scoring, Coach checks: same lift in 24h? Same pattern in 48h? High fatigue? Lower-body collision with hard cardio? Pain concern? Ineligible sessions are deferred with a cited reason.")
                row("scalemass", "Balanced weekly scoring",
                    "Coach closes the largest fitness gap first: strength below the 2-day floor vs aerobic below the 150-minute floor. Hard/easy rhythm and recovery are preserved.")
                row("book.pages", "Conservative defaults",
                    "Recovery times are coach policy (\"Coach's conservative recovery window\"), not claims that every muscle recovers in exactly 48 hours.")
            }

            Section("When it updates") {
                row("bolt", "Live",
                    "The coach recomputes from scratch every time the Home screen renders. There is no cache — it always reflects the current state of your data.")
                row("flag.checkered", "Finish a workout",
                    "The new session is included right away. Coach may switch from strength to easy aerobic if recovery gates apply.")
            }

            Section("How your settings affect it") {
                row("target", "Training goal",
                    "Strength: favors heavy loads (>=80% e1RM). Hypertrophy: targets moderate loads with controlled RIR. Endurance: flags excessive heavy work.")
                row("person.fill", "Experience level",
                    "Scales weekly starting volume ranges per body part. Beginners usually need fewer sets; advanced lifters often tolerate more.")
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
