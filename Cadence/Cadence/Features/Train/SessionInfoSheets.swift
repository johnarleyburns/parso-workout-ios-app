import SwiftUI
import CadenceCore
import CadenceFeatures

// MARK: - Live HR band + weight-accounting help sheets
//
// Extracted from `SessionView` (field test 2026-08-19 #4): the band reads
// `model.hrm`, which changes once a second while a strap or watch is connected.
// Leaving it inline made every heartbeat invalidate the whole session body —
// every exercise card, every sheet closure, the exercise picker included. As its
// own view the observation is scoped to the band alone.

struct SessionLiveHRBand: View {
    @Environment(AppModel.self) private var model

    @ViewBuilder
    var body: some View {
        if let bpm = model.hrm.currentBPM {
            band(bpm)
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
                        Text("Enter the weight of one dumbbell. The app accounts for paired, single, and isolateral dumbbell movements in calculations.\n\nFor standard two-dumbbell exercises (bench press, curls, etc.), your entered weight is doubled automatically.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .singleDumbbell:
                        Text("Dumbbell Weight").font(.headline)
                        Text("Enter the weight of the single dumbbell used. This exercise uses one dumbbell at a time (e.g., goblet squat, skullcrusher).\n\nThe entered weight is used as-is for calculations.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    case .dualKettlebell, .isolateralKettlebell:
                        Text("Kettlebell Weight").font(.headline)
                        Text("Enter the weight of one kettlebell. The app accounts for paired and single kettlebell movements in calculations.\n\nFor standard two-kettlebell exercises (double cleans, double presses, front squats, etc.), your entered weight is doubled automatically.")
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
                    Text("Enter the weight you lifted. For barbell exercises, enter the plate load — the bar weight is added automatically. For dumbbell and kettlebell exercises, enter the weight of one dumbbell or kettlebell.")
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
                Text("For kettlebell exercises, enter the weight of a single kettlebell — the app handles the accounting automatically:\n\n• **Two-kettlebell exercises** like double kettlebell cleans or presses: your entered weight is doubled for calculations (you're lifting two of them).\n\n• **Single-kettlebell exercises** like swings, snatches, or Turkish get-ups: your entered weight is used as-is.\n\nThis way you can always enter what's printed on the kettlebell, and the math works correctly behind the scenes.")
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
                Text("For dumbbell exercises, enter the weight of a single dumbbell — the app handles the accounting automatically:\n\n• **Two-dumbbell exercises** like bench press or curls: your entered weight is doubled for calculations (you're lifting two of them).\n\n• **Single-dumbbell exercises** like goblet squats or skullcrushers: your entered weight is used as-is.\n\n• **Isolateral exercises** like one-arm rows: your entered weight is doubled for comparison against barbell movements.\n\nThis way you can always enter what's printed on the dumbbell, and the math works correctly behind the scenes.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Dumbbell Help").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Got it") { showDumbbellInfo = false } } }
        }
        .presentationDetents([.medium, .large])
    }
}
