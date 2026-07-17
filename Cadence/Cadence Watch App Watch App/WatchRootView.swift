import SwiftUI
import CadenceCore

/// Root launcher for the Cladiron Watch App. Presents a glanceable list of
/// workout options and live HR monitoring so the user can start a session or
/// check their heart rate without the phone.
///
/// Phase 1: live HR view + HR source picker replaces HR settings placeholder.
/// Phase 2: real interval timer replaces HIIT/Boxing placeholders.
/// Phase 3: real strength logging replaces Lift/Resume placeholders.
struct WatchRootView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { LiveHRView() }
                        label: { Label("Live HR", systemImage: "heart.fill") }

                    NavigationLink { WatchStrengthView() }
                        label: { Label("Start Lift", systemImage: "dumbbell.fill") }

                    NavigationLink { WatchIntervalView(plan: .hiitDefault(), kind: "HIIT") }
                        label: { Label("HIIT", systemImage: "flame.fill") }

                    NavigationLink { WatchIntervalView(plan: .boxingDefault(), kind: "Boxing") }
                        label: { Label("Boxing", systemImage: "figure.boxing") }

                    NavigationLink { ResumePlaceholderView() }
                        label: { Label("Resume", systemImage: "arrow.counterclockwise") }
                }

                Section {
                    NavigationLink { HRSettingsView() }
                        label: { Label("Settings", systemImage: "gearshape.fill") }
                }
            }
            .navigationTitle("Cladiron")
        }
    }
}

// MARK: - Live HR + Zone View (Phase 1)

private struct LiveHRView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager

    var body: some View {
        VStack(spacing: 8) {
            Spacer()

            Text(zoneLabel)
                .font(.caption.bold())
                .foregroundStyle(zoneColor)

            Text(bpmText)
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .foregroundStyle(zoneColor)

            HStack(spacing: 3) {
                ForEach(1...5, id: \.self) { z in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(zoneFillColor(for: z))
                        .frame(width: 28, height: 6)
                }
            }

            if !watchManager.isActive {
                Text("Start a workout to unlock\ncontinuous HR monitoring")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .navigationTitle("Live HR")
        .onChange(of: watchManager.currentBPM) { _, _ in update() }
        .onAppear { update() }
    }

    private func update() {
        // trigger SwiftUI update via @Observable
    }

    private var bpmText: String {
        guard let bpm = watchManager.currentBPM else { return "--" }
        return String(format: "%.0f", bpm)
    }

    private var zone: Int {
        guard let bpm = watchManager.currentBPM else { return 0 }
        return hrZone(bpm: bpm)
    }

    private var zoneLabel: String {
        switch zone {
        case 1: return "Recovery"
        case 2: return "Endurance"
        case 3: return "Tempo"
        case 4: return "Threshold"
        case 5: return "Max"
        default: return "--"
        }
    }

    private var zoneColor: Color {
        switch zone {
        case 1: return .cyan
        case 2: return .green
        case 3: return .yellow
        case 4: return .orange
        case 5: return .red
        default: return .secondary
        }
    }

    private func zoneFillColor(for z: Int) -> Color {
        z <= zone ? zoneColor : .gray.opacity(0.25)
    }

    private func hrZone(bpm bpmVal: Double) -> Int {
        let maxHR = 220.0 - 30 // simple default; replaced by real CardioMath later
        let pct = bpmVal / maxHR
        switch pct {
        case ..<0.60: return 1
        case 0.60..<0.70: return 2
        case 0.70..<0.80: return 3
        case 0.80..<0.90: return 4
        default: return 5
        }
    }
}

// MARK: - HR Settings / Source Picker (Phase 1)

private struct HRSettingsView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager

    var body: some View {
        List {
            Section("Heart Rate Source") {
                ForEach(HRSource.allCases, id: \.self) { source in
                    Button {
                        watchManager.hrSource = source
                        watchManager.switchToSource(source)
                    } label: {
                        HStack {
                            Label(source.displayName, systemImage: source.symbol)
                            Spacer()
                            if watchManager.hrSource == source {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if watchManager.hrSource == .bluetooth {
                Section("Chest Strap Status") {
                    HStack {
                        Circle()
                            .fill(bleStatusColor)
                            .frame(width: 8, height: 8)
                        Text(bleStatusText)
                            .font(.caption)
                    }
                    if let battery = watchManager.bleBattery {
                        Label("Battery: \(battery)%", systemImage: batteryIcon(pct: battery))
                            .font(.caption)
                    }
                }
            }

            Section {
                Button("Request HealthKit Access") {
                    Task { _ = await watchManager.requestHRAuthorization() }
                }
                if !watchManager.hrAuthorized {
                    Text("HealthKit access needed for heart rate")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var bleStatusColor: Color {
        guard let state = watchManager.bleState else { return .secondary }
        switch state {
        case .scanning: return .blue
        case .connected: return .green
        case .disconnected: return .orange
        }
    }

    private var bleStatusText: String {
        guard let state = watchManager.bleState else { return "Not active" }
        switch state {
        case .scanning: return "Scanning..."
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        }
    }

    private func batteryIcon(pct: Int) -> String {
        switch pct {
        case 0..<20: return "battery.0percent"
        case 20..<45: return "battery.25percent"
        case 45..<70: return "battery.50percent"
        case 70..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Placeholder (replaced in later phase)

private struct ResumePlaceholderView: View {
    var body: some View {
        Text("Resume ships in Phase 3")
            .foregroundStyle(.secondary)
            .navigationTitle("Resume")
    }
}

#Preview {
    WatchRootView()
        .environment(WatchWorkoutManager())
}
