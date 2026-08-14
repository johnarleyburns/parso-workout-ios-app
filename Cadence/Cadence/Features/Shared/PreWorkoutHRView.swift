import SwiftUI
import SwiftData
import CadenceCore

enum HRSourceChoice { case bluetooth, watch, none }

/// Pre-workout heart-rate connection screen.
/// Shown before cardio/interval/strength workouts so the user can connect a
/// Bluetooth chest strap, see live HR, then press Start when ready.
/// Connecting does NOT start the workout — "Start Workout" is a
/// separate deliberate button so the user can verify their HR data first.
///
/// `onContinue(useHR)` proceeds to the workout — `true` if the user is
/// capturing HR from a strap, `false` to record without HR.
///
struct PreWorkoutHRView: View {
    let workoutType: CardioType?
    let onContinue: (_ source: HRSourceChoice) -> Void

    @Environment(AppModel.self) private var model
    @Query private var savedDevices: [HRMDevice]

    private var hrm: HeartRateMonitor { model.hrm }
    private var defaultDevice: HRMDevice? { savedDevices.first { $0.isDefault } }

    private var strapConnected: Bool {
        if case .connected = hrm.state { return true }
        return false
    }
    private var strapName: String {
        defaultDevice?.name ?? hrm.discovered.first?.name ?? "Chest strap"
    }
    private var strapBPM: Double? {
        strapConnected ? hrm.currentBPM : nil
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "heart.fill").scaledSystemFont(44, relativeTo: .largeTitle).foregroundStyle(.pink)
                Text("Connect Heart Rate")
                    .font(.title.bold())
                    .accessibilityIdentifier("prehr.title")
                Text("Connect a Bluetooth chest strap, then start when you see your live heart rate.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }

            VStack(spacing: 12) {
                strapRow
                if model.watchAvailable {
                    HRSourceCard(icon: "applewatch", title: "Apple Watch", tint: .blue) {
                        Button("Use Watch") { onContinue(.watch) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("prehr.useWatch")
                    }
                }
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    onContinue(.bluetooth)
                } label: {
                    Text("Start").frame(maxWidth: .infinity, minHeight: 52)
                }
                .cadenceGlassButton(prominent: true, tint: .green)
                .accessibilityIdentifier("prehr.start")
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        // The HR gate is part of the workout start sequence — the screen must
        // not auto-lock while the user straps on a monitor (Phase 1c).
        .keepAwake()
        .onAppear {
            hrm.startScanning()
            if let id = defaultDevice?.id { hrm.connect(id) }
        }
        .onDisappear { hrm.stopScanning() }
    }

    // MARK: Rows

    private var strapRow: some View {
        HRSourceCard(
            icon: "antenna.radiowaves.left.and.right",
            title: strapName,
            tint: .pink
        ) {
            if let bpm = strapBPM {
                HRValueLabel(bpm: Int(bpm), note: "live", noteColor: .green)
                    .accessibilityIdentifier("prehr.strapBPM")
            } else if strapConnected {
                ProgressView()
            } else {
                Button("Connect") { connectStrap() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("prehr.connectStrap")
            }
        }
    }

    // MARK: Helpers

    private func connectStrap() {
        hrm.startScanning()
        if let first = hrm.discovered.first {
            hrm.connect(first.id)
            hrm.rememberDevice(first.id)
        }
    }

}

/// A labeled HR source row (icon + title on the left, a value/control on the right).
private struct HRSourceCard<Trailing: View>: View {
    let icon: String
    let title: String
    var tint: Color = .pink
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundStyle(tint).frame(width: 32)
            Text(title).font(.headline)
            Spacer()
            trailing()
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// "♥ 132 bpm · live" style readout.
private struct HRValueLabel: View {
    let bpm: Int
    let note: String
    var noteColor: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Text("\(bpm)").font(.title2.bold().monospacedDigit())
            Text("bpm").font(.caption).foregroundStyle(.secondary)
            Text("· \(note)").font(.caption).foregroundStyle(noteColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(bpm) beats per minute, \(note)")
    }
}
