import SwiftUI
import SwiftData
import CadenceCore

/// Pre-workout heart-rate connection screen (feedback batch 5, FR-8).
/// Shown before cardio/interval/strength workouts so the user can connect a
/// strap or start the Apple Watch sensor, see live HR, then press Start when
/// ready.  Connecting does NOT start the workout — "Start Workout" is a
/// separate deliberate button so the user can verify their HR data first.
///
/// `onContinue(useHR)` proceeds to the workout — `true` if the user is
/// capturing HR (strap or watch), `false` to record without HR.
///
/// When `workoutType` is nil (defensive, or for strength), the Watch row uses
/// `startWatchStrength()` instead of a cardio type.
struct PreWorkoutHRView: View {
    let workoutType: CardioType?
    let onContinue: (_ useHR: Bool) -> Void

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

    private var watchBPM: Double? {
        model.watchActive ? hrm.currentBPM : nil
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "heart.fill").font(.system(size: 44)).foregroundStyle(.pink)
                Text("Connect Heart Rate")
                    .font(.title.bold())
                    .accessibilityIdentifier("prehr.title")
                Text("Connect a strap or your Apple Watch, then start when you see your live heart rate.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }

            VStack(spacing: 12) {
                strapRow
                if model.watchAvailable {
                    watchRow
                }
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    onContinue(true)
                } label: {
                    Text("Start Workout").frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(.green)
                .accessibilityIdentifier("prehr.start")

                Button {
                    onContinue(false)
                } label: {
                    Text("Continue without HR").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).controlSize(.large)
                .accessibilityIdentifier("prehr.skip")
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
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

    private var watchRow: some View {
        HRSourceCard(
            icon: "applewatch",
            title: "Apple Watch",
            tint: .orange
        ) {
            if let bpm = watchBPM {
                HRValueLabel(bpm: Int(bpm), note: "live", noteColor: .green)
                    .accessibilityIdentifier("prehr.watchBPM")
            } else if model.watchActive {
                ProgressView()
            } else if let error = model.watchError {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(error).font(.caption).foregroundStyle(.red)
                    Button("Try Again") { startWatch() }
                        .buttonStyle(.bordered).tint(.orange)
                        .accessibilityIdentifier("prehr.watchRetry")
                }
            } else {
                Button("Use Watch") { startWatch() }
                    .buttonStyle(.bordered).tint(.orange)
                    .accessibilityIdentifier("prehr.useWatch")
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

    private func startWatch() {
        if let type = workoutType {
            model.startWatchWorkout(type: type)
        } else {
            model.startWatchStrength()
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
