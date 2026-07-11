import SwiftUI
import CadenceCore

/// The free-tier Coach surface shown in place of the live coaching card.
///
/// Design (coach-surface-design.md, 2026-07-03 amendment): the coach's *insight* —
/// its live observation about the user's actual training — is shown here
/// **continuously**, exactly like the Pro coach, and updates every day / after
/// every workout. What stays locked is the *prescription*: the exact sets, reps,
/// and load the coach would prescribe, plus the adapting plan. The prominent
/// "Unlock the Coach" CTA is paced by `CoachUpsellPolicy` (passed in as
/// `showUnlockCTA`) so free Home never reads like a running ad; a discreet tap on
/// the locked prescription still lets a motivated user convert at any time.
struct CoachPreviewView: View {
    let plan: WeeklyPlan
    /// The continuously-updated observation. Always shown when present.
    let topInsight: Insight?
    /// What the coach *would do* — locked for free users.
    let prescription: Recommendation?
    var onUnlock: () -> Void
    /// Called once when the prominent CTA is actually displayed, so its cadence
    /// can be recorded. No-op when the CTA is suppressed.
    var onCTADisplayed: () -> Void = {}
    var onFixCustomExercises: (() -> Void)? = nil

    /// Captured once at creation from the rate-limit policy so recording the
    /// impression (which flips the policy) can't make the CTA blink out from under
    /// the user mid-view.
    @State private var showCTA: Bool
    @State private var didRecordCTA = false

    init(plan: WeeklyPlan,
         topInsight: Insight?,
         prescription: Recommendation?,
         showUnlockCTA: Bool,
         onUnlock: @escaping () -> Void,
         onCTADisplayed: @escaping () -> Void = {},
         onFixCustomExercises: (() -> Void)? = nil) {
        self.plan = plan
        self.topInsight = topInsight
        self.prescription = prescription
        self.onUnlock = onUnlock
        self.onCTADisplayed = onCTADisplayed
        self.onFixCustomExercises = onFixCustomExercises
        _showCTA = State(initialValue: showUnlockCTA)
    }

    /// Real citation titles behind today's observation + prescription. Free to
    /// read — the science is marketing; the *application* of it is Pro.
    private var citations: [Citation] {
        var seen = Set<String>()
        var result: [Citation] = []
        if let c = topInsight?.citation, seen.insert(c.id).inserted { result.append(c) }
        for c in prescription?.allCitations ?? [] where seen.insert(c.id).inserted {
            result.append(c)
        }
        if result.isEmpty { result = Array(CitationRegistry.all.prefix(3)) }
        return Array(result.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            observationSection
            lockedPrescriptionSection

            if !citations.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("THE SCIENCE")
                        .font(.caption.bold()).tracking(1.1)
                        .foregroundStyle(.secondary)
                    ForEach(citations) { citation in
                        CitationLink(citation: citation)
                    }
                }
            }

            if showCTA {
                Button { onUnlock() } label: {
                    Label("Unlock the Coach", systemImage: "lock.open.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .cadenceGlassButton(prominent: true, tint: .green)
                .accessibilityIdentifier("coach.preview.unlock")
                .onAppear {
                    guard !didRecordCTA else { return }
                    didRecordCTA = true
                    onCTADisplayed()
                }

                Text("Everything else in Cladiron is free forever.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
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
            Text("COACH").font(.caption.bold()).tracking(1.2)
            Spacer()
        }
        .foregroundStyle(.green)
    }

    // MARK: - Observation (free, continuous)

    @ViewBuilder
    private var observationSection: some View {
        if let topInsight {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT THE COACH NOTICED")
                    .font(.caption.bold()).tracking(1.1)
                    .foregroundStyle(.secondary)
                InsightContentView(insight: topInsight, onFixCustomExercises: onFixCustomExercises)
            }
            .accessibilityIdentifier("coach.preview.insight")
        } else {
            Text("Log a few workouts and the Coach starts noticing patterns in your training — the observations update here every day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Prescription (locked)

    private var lockedPrescriptionSection: some View {
        Button { onUnlock() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("WHAT THE COACH WOULD DO")
                        .font(.caption.bold()).tracking(1.1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("PRO")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.green.opacity(0.14), in: Capsule())
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(prescriptionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(prescriptionAction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .redacted(reason: .placeholder)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What the Coach would do — Pro. \(prescriptionTitle). Unlock to see the exact prescription.")
        .accessibilityIdentifier("coach.preview.lockedPrescription")
    }

    private var prescriptionTitle: String {
        if let t = prescription?.title, !t.isEmpty { return t }
        return "Your next adjustment"
    }

    /// The exact prescription copy, shown redacted so the free user sees there is a
    /// concrete, cited call waiting behind the paywall.
    private var prescriptionAction: String {
        if let a = prescription?.action, !a.isEmpty { return a }
        return "Exact sets, reps, and load for right now."
    }
}
