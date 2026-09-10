import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

enum HRSourceChoice { case bluetooth, watch, none }

extension HRSourceChoice {
    init(_ source: PreWorkoutHRContinue) {
        switch source {
        case .watch: self = .watch
        case .bluetooth: self = .bluetooth
        case .none: self = .none
        }
    }
}

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
    let onCancel: () -> Void

    @Environment(AppModel.self) private var model
    @Query private var savedDevices: [HRMDevice]
    @State private var watchSelected = false
    @State private var freshnessTick = Date()

    private var hrm: HeartRateMonitor { model.hrm }
    private var defaultDevice: HRMDevice? { savedDevices.first { $0.isDefault } }

    private var strapConnected: Bool {
        if case .connected = hrm.state, hrm.source == .bluetooth { return true }
        return false
    }
    private var strapName: String {
        defaultDevice?.name ?? hrm.discovered.first?.name ?? "Chest strap"
    }
    private var strapBPM: Double? {
        strapConnected ? hrm.currentBPM : nil
    }
    private var watchBPM: Int? { model.watchHRRelay.freshBPM(at: freshnessTick) }

    /// The pure, headless-tested state the Continue/Check buttons render from
    /// (field test 2026-08-20 issue 6). `watchRequested` is this view's
    /// `watchSelected`; `relayBusy` is the mid-connection relay states.
    private var hrState: PreWorkoutHRState {
        let relay = model.watchHRRelay.state
        var busy = false
        if case .connecting = relay { busy = true }
        if case .waitingForSample = relay { busy = true }
        return PreWorkoutHRState(watchBPM: watchBPM,
                                 strapConnected: strapConnected,
                                 watchRequested: watchSelected,
                                 relayBusy: busy)
    }

    private var watchStatus: String {
        switch model.watchHRRelay.state {
        case .connecting: return "Connecting to Apple Watch…"
        case .waitingForSample: return "Watch connected · waiting for heart rate…"
        case .live: return watchBPM == nil ? "Heart rate is stale · retry on Watch" : "Live from Apple Watch"
        case .timedOut(let message), .failed(let message): return message
        case .actionRequired(let message), .unavailable(let message): return message
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "heart.fill").scaledSystemFont(44, relativeTo: .largeTitle).foregroundStyle(.pink)
                Text("Connect Heart Rate")
                    .font(.title.bold())
                    .accessibilityIdentifier("prehr.title")
                Text("Use a Bluetooth chest strap or Apple Watch, then start when you see live heart rate.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }

            VStack(spacing: 12) {
                strapRow
                if model.watchAvailable {
                    HRSourceCard(icon: "applewatch", title: "Apple Watch", tint: .blue) {
                        Button(watchSelected ? "Check for Live HR" : "Check for Live HR") {
                            watchSelected = true
                            if let workoutType { model.startWatchWorkout(type: workoutType) } else { model.startWatchStrength() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(!PreWorkoutHRPresenter.checkEnabled(hrState))
                            .accessibilityIdentifier("prehr.watch.check")
                    }
                    if watchSelected {
                        Text("Open Cladiron on your Apple Watch and keep it visible.")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("prehr.watch.instructions")
                        if let watchBPM {
                            HRValueLabel(bpm: watchBPM, note: "LIVE · from Apple Watch", noteColor: .green)
                                .accessibilityIdentifier("prehr.watchBPM")
                        } else {
                            Text(watchStatus).font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("prehr.watch.status")
                        }
                    }
                } else {
                    HRSourceCard(icon: "applewatch.slash", title: "Apple Watch unavailable", tint: .secondary) {
                        Text("Install or open Cladiron on Watch")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("prehr.watch.unavailable")
                    }
                }
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    if watchBPM == nil { model.stopWatchWorkout() }
                    onContinue(HRSourceChoice(PreWorkoutHRPresenter.continueAction(hrState)))
                } label: {
                    Text(PreWorkoutHRPresenter.continueLabel(hrState))
                        .font(.headline)
                        .frame(maxWidth: .infinity,
                               minHeight: CGFloat(LayoutMetrics.actionButtonHeight))
                }
                .cadenceGlassButton(prominent: true, tint: .green)
                .disabled(!PreWorkoutHRPresenter.continueEnabled(hrState))
                .accessibilityIdentifier("prehr.start")

                Button {
                    model.stopWatchWorkout()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .font(.headline)
                        .frame(maxWidth: .infinity,
                               minHeight: CGFloat(LayoutMetrics.actionButtonHeight))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("prehr.cancel")
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
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                freshnessTick = Date()
            }
        }
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
                Button("Connect") { model.stopWatchWorkout(); connectStrap() }
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
