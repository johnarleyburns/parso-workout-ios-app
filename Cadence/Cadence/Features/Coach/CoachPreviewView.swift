import SwiftUI
import CadenceCore

/// The free-tier Coach surface shown in place of the live coaching card. It shows
/// the *structure* of what the Coach would do — the weekly program skeleton and a
/// couple of real, tappable citations — with the day-to-day coaching locked. This
/// preview *is* the paywall funnel (monetization plan §4.5); treat it as a
/// first-class screen, not an ad.
struct CoachPreviewView: View {
    let plan: WeeklyPlan
    var onUnlock: () -> Void

    /// A few real citations so the science is visible (and tappable) even in free.
    private var sampleCitations: [Citation] {
        Array(CitationRegistry.all.prefix(3))
    }

    private var previewDays: [WeeklyPlan.DayOutline] {
        let upcoming = plan.remainingCalendarWeekDays.filter { !$0.sessions.isEmpty }
        if !upcoming.isEmpty { return Array(upcoming.prefix(4)) }
        return Array(plan.nextWeekDays.filter { !$0.sessions.isEmpty }.prefix(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Text("The Coach builds a plan around your goals, then adjusts every set to what you actually log — and shows the research for each call.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !previewDays.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("YOUR PROGRAM")
                        .font(.caption.bold()).tracking(1.1)
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(previewDays.enumerated()), id: \.element.id) { index, day in
                            if index > 0 { Divider().padding(.leading, 38) }
                            CoachPlanDayRow(day: day)
                        }
                    }
                }
            }

            lockedRows

            if !sampleCitations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("THE SCIENCE")
                        .font(.caption.bold()).tracking(1.1)
                        .foregroundStyle(.secondary)
                    ForEach(sampleCitations) { citation in
                        CitationLink(citation: citation, compact: true)
                    }
                }
            }

            Button { onUnlock() } label: {
                Label("Unlock the Coach", systemImage: "lock.open.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .cadenceGlassButton(prominent: true, tint: .green)
            .accessibilityIdentifier("coach.preview.unlock")

            Text("Everything else in Cladiron is free forever.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cadenceGlassCard(in: RoundedRectangle(cornerRadius: 20, style: .continuous), tint: .green)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.preview")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.mind.and.body").font(.caption)
            Text("COACH · PREVIEW").font(.caption.bold()).tracking(1.2)
            Spacer()
            Image(systemName: "lock.fill").font(.caption)
        }
        .foregroundStyle(.green)
    }

    private var lockedRows: some View {
        VStack(spacing: 8) {
            lockedRow("slider.horizontal.3", "Today's prescription",
                      "Exact sets, reps, and load for right now")
            lockedRow("chart.line.uptrend.xyaxis", "Autoregulation",
                      "Adjusts load and volume from your logged RIR")
            lockedRow("waveform.path.ecg", "Deload & adaptation",
                      "Detects fatigue and plans recovery")
        }
    }

    private func lockedRow(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
