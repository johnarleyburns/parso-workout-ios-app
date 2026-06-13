import SwiftUI
import SwiftData
import CadenceCore

/// Pre-workout heart-rate connection screen (feedback batch 5). Shown before a
/// HIIT/boxing interval so the user can get HR flowing — or knowingly skip it.
///
/// Source: the **chest strap (BLE)** — real-time `currentBPM` from
/// `HeartRateMonitor`, the supported live path (no watch app). The Apple Watch is
/// intentionally not shown here: the iPhone can't stream the Watch's *live* HR
/// without a watchOS app, and its last Health sample is too stale to be useful
/// in a workout, so we don't pretend otherwise.
///
/// `onContinue(useHR)` proceeds to the workout — `true` if the user wants HR
/// captured (strap), `false` to record without HR.
struct PreWorkoutHRView: View {
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

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "heart.fill").font(.system(size: 44)).foregroundStyle(.pink)
                Text("Connect Heart Rate")
                    .font(.title.bold())
                    .accessibilityIdentifier("prehr.title")
                Text("Heart rate makes interval training count. Connect a strap, or continue without.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }

            strapRow
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    onContinue(true)
                } label: {
                    Text("Use this HR").frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).tint(.pink)
                .disabled(!strapConnected)
                .accessibilityIdentifier("prehr.useHR")

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
            // Reconnect the remembered default device automatically.
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
            if strapConnected, let bpm = hrm.currentBPM {
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
