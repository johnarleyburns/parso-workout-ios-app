import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

// MARK: - Live HR band + weight-accounting help sheets
//
// Extracted from `SessionView` (field test 2026-08-19 #4): the band reads
// `model.hrm`, which changes once a second while a strap or watch is connected.
// Leaving it inline made every heartbeat invalidate the whole session body —
// every exercise card, every sheet closure, the exercise picker included. As its
// own view the observation is scoped to the band alone.

/// Compact right-aligned live heart rate for the elapsed-time line. The full
/// Watch status/reconnect controls live behind the adjacent info button rather
/// than occupying rows on the workout page.
struct SessionLiveHRInline: View {
    @Environment(AppModel.self) private var model
    @State private var showingInfo = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            HStack(spacing: 5) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(bpmText(now: context.date))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                Button { showingInfo = true } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("session.hr.info")
                .accessibilityLabel("Heart rate status and reconnect")
            }
        }
        .alert("Receiving live HR", isPresented: $showingInfo) {
            Button("Reconnect Apple Watch HR") { model.reconnectWatchHR() }
                .accessibilityIdentifier("session.watch.reconnect")
            Button("Done", role: .cancel) {}
        } message: {
            Text(model.watchHRStatusText)
        }
    }

    private func bpmText(now: Date) -> String {
        if model.hrm.source == .appleWatch,
           !model.watchHRConnection.isSampleFresh(now: now) {
            return "—"
        }
        guard let bpm = model.hrm.currentBPM else { return "—" }
        return "\(Int(bpm)) bpm"
    }
}


struct SessionLiveHRBand: View {
    @Environment(AppModel.self) private var model
    var sessionID: UUID? = nil
    /// Guided warm-up/cool-down shows an explicit state before any fresh sample.
    var showsEmptyState = false

    @ViewBuilder
    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 5)) { context in
                // Never show a frozen injected Watch value.
                if model.hrm.source == .appleWatch,
                   !model.watchHRConnection.isSampleFresh(now: context.date) {
                    noReading
                } else if let bpm = model.hrm.currentBPM {
                    band(bpm)
                } else {
                    noReading
                }
            }
            if model.watchHRConnection.identity != nil { watchRow }
            if let sessionID, let text = model.watchHRFinalizationStatusText(sessionID: sessionID) {
                Label(text, systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .accessibilityIdentifier("session.watch.hrFinalization")
            }
        }
    }

    @ViewBuilder
    private var noReading: some View {
        if showsEmptyState {
            Label("No heart rate yet", systemImage: "heart.slash")
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 4)
                .accessibilityIdentifier("session.hr.none")
        }
    }

    /// Truthful Watch link status, real reading age, and the repair action,
    /// available in the live workout (not only the preflight screen).
    private var watchRow: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            HStack(spacing: 8) {
                Image(systemName: "applewatch").font(.caption)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.watchHRStatusText).font(.caption.weight(.semibold))
                    if let end = model.watchLastSampleEnd {
                        Text("Last reading \(max(0, Int(context.date.timeIntervalSince(end)))) s ago")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Reconnect Apple Watch HR") { model.reconnectWatchHR() }
                    .font(.caption).buttonStyle(.bordered)
                    .accessibilityHint("Asks your Apple Watch which workout it is running and repairs the connection without starting a second workout")
                    .accessibilityIdentifier("session.watch.reconnect")
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .accessibilityElement(children: .contain)
        }
    }

    private func band(_ bpm: Double) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").font(.caption).foregroundStyle(.red)
            Text("\(Int(bpm)) bpm").font(.caption.weight(.medium)).monospacedDigit()
            if let battery = model.hrm.battery {
                Image(systemName: battery <= 10 ? "battery.0" : "battery.75")
                    .font(.caption2).foregroundStyle(battery <= 10 ? .red : .secondary)
                Text("\(battery)%").font(.caption2).foregroundStyle(.secondary)
            }
            if model.hrm.criticalBattery {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 4)
        .cadenceGlass(in: Rectangle(), fallback: .ultraThinMaterial)
    }
}

extension SessionView {
    var weightInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let ex = inlineExercise {
                    switch ex.resolvedLoadAccountingMode {
                    case .barbell:
                        Text("Barbell Weight").font(.headline)
                        Text("Enter the added plate load only. The bar weight (\(Format.weight(ex.effectiveDefaultBarWeightKg, unit: settings.unit))) is added automatically for calculations.\n\nEnter 0 when using only the bar or bodyweight. Bar weight is added separately for barbell calculations.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .bodyweight:
                        Text("Bodyweight Exercise").font(.headline)
                        Text("Enter 0 when using only your bodyweight. Enter a positive value for added weight (e.g., weighted vest, dip belt).\n\nThe app tracks added load; bodyweight is yours alone.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .dualDumbbell, .isolateralDumbbell:
                        Text("Dumbbell Weight").font(.headline)
                        Text("Enter the total weight lifted across both dumbbells. For a one-arm or single-dumbbell movement, enter only the weight used. The app uses this total as entered and never doubles it.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .singleDumbbell:
                        Text("Dumbbell Weight").font(.headline)
                        Text("Enter the weight of the single dumbbell used. This exercise uses one dumbbell at a time (e.g., goblet squat, skullcrusher).\n\nThe entered weight is used as-is for calculations.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .dualKettlebell, .isolateralKettlebell:
                        Text("Kettlebell Weight").font(.headline)
                        Text("Enter the total weight lifted across both kettlebells. For a one-arm or single-kettlebell movement, enter only the weight used. The app uses this total as entered and never doubles it.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .singleKettlebell:
                        Text("Kettlebell Weight").font(.headline)
                        Text("Enter the weight of the single kettlebell used. This exercise uses one kettlebell at a time (e.g., swing, snatch, Turkish get-up).\n\nThe entered weight is used as-is for calculations.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case nil:
                        Text("Weight Entry").font(.headline)
                        Text("Enter the weight as you would normally. This exercise uses standard weight accounting — what you enter is what's used for PRs, volume, and trends.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Weight Entry").font(.headline)
                    Text("Enter the total weight you lifted. For barbell exercises, enter the plate load — the bar weight is added automatically. For dumbbell and kettlebell exercises, enter the total across the weights used; the app never doubles it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding()
            .navigationTitle("Weight Help").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showWeightInfo = false } } }
        }
        .presentationDetents([.medium])
    }
    var kettlebellInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Kettlebell Weight Entry").font(.headline)
                Text("Enter the total weight lifted. With two kettlebells, add their weights together. With one kettlebell, enter its weight. The app uses the total as entered for volume, records and trends; it never doubles the weight.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Kettlebell Help").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got it") { showKettlebellInfo = false } } }
        }
        .presentationDetents([.medium, .large])
    }
    var dumbbellInfoSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Dumbbell Weight Entry").font(.headline)
                Text("Enter the total weight lifted. With two dumbbells, add their weights together. With one dumbbell or a one-arm movement, enter the weight used. Isolateral and isometric movements also use the entered total without doubling for comparisons. This total is used for volume, records and trends.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Dumbbell Help").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got it") { showDumbbellInfo = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
