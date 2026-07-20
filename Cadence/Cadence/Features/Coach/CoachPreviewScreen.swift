import SwiftUI
import CadenceCore

/// The full coach pitch, moved off Home to a dedicated screen (coach-surface-design.md
/// §5). It is the tap target of the introducing card and the ambient `CoachRow`, and
/// is always reachable from the Programs tab. Insights are shown here continuously;
/// the prescription stays locked and the prominent CTA is paced by `CoachUpsellPolicy`.
struct CoachPreviewScreen: View {
    let topInsight: Insight?
    let prescription: Recommendation?
    var onUnlock: () -> Void
    var onCTADisplayed: () -> Void = {}
    var onHide: () -> Void = {}
    var onFixCustomExercises: (() -> Void)? = nil
    var onInsightAction: ((Insight.Action) -> Void)? = nil

    @State private var showCTA: Bool
    @State private var didRecordCTA = false

    init(topInsight: Insight?,
         prescription: Recommendation?,
         showUnlockCTA: Bool,
         onUnlock: @escaping () -> Void,
         onCTADisplayed: @escaping () -> Void = {},
         onHide: @escaping () -> Void = {},
         onFixCustomExercises: (() -> Void)? = nil,
         onInsightAction: ((Insight.Action) -> Void)? = nil) {
        self.topInsight = topInsight
        self.prescription = prescription
        self.onUnlock = onUnlock
        self.onCTADisplayed = onCTADisplayed
        self.onHide = onHide
        self.onFixCustomExercises = onFixCustomExercises
        self.onInsightAction = onInsightAction
        _showCTA = State(initialValue: showUnlockCTA)
    }

    private var citations: [Citation] {
        var seen = Set<String>()
        var result: [Citation] = []
        if let c = topInsight?.citation, seen.insert(c.id).inserted { result.append(c) }
        for c in prescription?.allCitations ?? [] where seen.insert(c.id).inserted { result.append(c) }
        if result.isEmpty { result = Array(CitationRegistry.all.prefix(3)) }
        return Array(result.prefix(3))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let topInsight {
                    section("WHAT THE COACH NOTICED") {
                        InsightContentView(insight: topInsight,
                                           onFixCustomExercises: onFixCustomExercises,
                                           onInsightAction: onInsightAction)
                    }
                    .accessibilityIdentifier("coach.previewScreen.insight")
                }

                capabilitiesSection
                lockedPrescriptionSection

                if !citations.isEmpty {
                    section("THE SCIENCE") {
                        ForEach(citations) { CitationLink(citation: $0) }
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
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }

                Button { onHide() } label: {
                    Text("Hide Coach offers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("coach.previewScreen.hide")
            }
            .padding()
        }
        .background { CadenceGlassBackdrop(tint: .green) }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach.previewScreen")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "figure.mind.and.body")
                .font(.largeTitle).foregroundStyle(.green)
            Text("The Coach builds a plan around your goals, then adjusts every set to what you actually log — and shows the research for each call.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var capabilitiesSection: some View {
        section("WHAT PRO UNLOCKS", trailing: proPill) {
            capabilityRow("slider.horizontal.3", "Today's prescription",
                          "Exact sets, reps, and load for right now")
            capabilityRow("chart.line.uptrend.xyaxis", "Autoregulation",
                          "Adjusts load and volume from your logged RIR")
            capabilityRow("waveform.path.ecg", "Deload & adaptation",
                          "Detects fatigue and plans recovery")
        }
    }

    private var lockedPrescriptionSection: some View {
        Button { onUnlock() } label: {
            section("WHAT THE COACH WOULD DO", trailing: proPill) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.headline).foregroundStyle(.green).frame(width: 26)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(prescriptionTitle).font(.subheadline.weight(.semibold))
                        Text(prescriptionAction)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                            .redacted(reason: .placeholder)
                    }
                    Spacer(minLength: 0)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("What the Coach would do — Pro. \(prescriptionTitle). Unlock to see the exact prescription.")
        .accessibilityIdentifier("coach.previewScreen.lockedPrescription")
    }

    private var proPill: AnyView {
        AnyView(
            Text("PRO")
                .font(.caption2.bold())
                .foregroundStyle(.green)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(.green.opacity(0.14), in: Capsule())
        )
    }

    private func section<Content: View>(_ title: String,
                                        trailing: AnyView? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.caption.bold()).tracking(1.1).foregroundStyle(.secondary)
                Spacer()
                if let trailing { trailing }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func capabilityRow(_ symbol: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline).foregroundStyle(.secondary).frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .opacity(0.85)
    }

    private var prescriptionTitle: String {
        if let t = prescription?.title, !t.isEmpty { return t }
        return "Your next adjustment"
    }

    private var prescriptionAction: String {
        if let a = prescription?.action, !a.isEmpty { return a }
        return "Exact sets, reps, and load for right now."
    }
}
