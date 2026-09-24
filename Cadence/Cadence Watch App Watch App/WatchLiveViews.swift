import SwiftUI
import CadenceCore
import CadenceFeatures

// MARK: - Live HR + Settings views

struct LiveHRView: View {
    @Environment(WatchWorkoutManager.self) private var watchManager
    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            if watchManager.isMonitoring || watchManager.isActive {
                Text(bpmText)
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(zoneColor)
                    .padding(.top, 0)
                Text(zoneLabel).font(.caption.bold()).foregroundStyle(zoneColor)
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { z in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(z <= zone ? zoneColor : .gray.opacity(0.25))
                            .frame(width: 28, height: 6)
                    }
                }
                Button("Stop") { watchManager.stopWorkout(save: false) }
                    .buttonStyle(.bordered).padding(.top, 10)
            } else {
                Text("--")
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.top, 0)
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.gray.opacity(0.25))
                            .frame(width: 28, height: 6)
                    }
                }
                Button("Start monitoring") { watchManager.startMonitoringSession() }
                    .buttonStyle(.borderedProminent).tint(.blue).padding(.top, 8)
            }
            Spacer(minLength: 0).frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .background(zoneBackgroundColor)
        .navigationTitle("Live HR")
    }

    private var bpmText: String {
        guard let bpm = watchManager.currentBPM else { return "--" }
        return String(format: "%.0f", bpm)
    }

    private var zone: Int {
        guard let bpm = watchManager.currentBPM else { return 0 }
        let pct = bpm / (220.0 - 30)
        switch pct {
        case ..<0.60: return 1
        case ..<0.70: return 2
        case ..<0.80: return 3
        case ..<0.90: return 4
        default: return 5
        }
    }

    private var zoneLabel: String {
        switch zone {
        case 1: "Z1 / Recovery"
        case 2: "Z2 / Endurance"
        case 3: "Z3 / Tempo"
        case 4: "Z4 / Threshold"
        case 5: "Z5 / Max"
        default: "--"
        }
    }

    private var zoneColor: Color {
        switch zone {
        case 1: .cyan
        case 2: .green
        case 3: .yellow
        case 4: .orange
        case 5: .red
        default: .secondary
        }
    }

    private var zoneBackgroundColor: Color {
        guard watchManager.isMonitoring || watchManager.isActive else { return Color.clear }
        return zoneColor.opacity(0.15)
    }
}

struct HRSettingsView: View {
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
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            if watchManager.hrSource == .bluetooth {
                Section("Chest Strap Status") {
                    HStack {
                        Circle().fill(bleColor).frame(width: 8, height: 8)
                        Text(bleText).font(.caption)
                    }
                    if let b = watchManager.bleBattery {
                        Label("Battery: \(b)%", systemImage: batterySymbol(for: b))
                            .font(.caption)
                    }
                }
            }
            Section {
                Button("Request HealthKit Access") {
                    Task { _ = await watchManager.requestWorkoutAuthorization() }
                }
            }
        }
        .navigationTitle("Settings")
    }

    private func batterySymbol(for level: Int) -> String {
        switch level {
        case ..<20: "battery.0percent"
        case ..<45: "battery.25percent"
        case ..<70: "battery.50percent"
        case ..<90: "battery.75percent"
        default: "battery.100percent"
        }
    }

    private var bleColor: Color {
        guard let state = watchManager.bleState else { return .secondary }
        switch state {
        case .scanning: return .blue
        case .connected: return .green
        case .disconnected: return .orange
        }
    }

    private var bleText: String {
        guard let state = watchManager.bleState else { return "Not active" }
        switch state {
        case .scanning: return "Scanning..."
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        }
    }
}

extension CardioType {
    func toCardioKind() -> WorkoutConfigurationSpec.CardioKind {
        switch self {
        case .run: return .run
        case .walk: return .walk
        case .cycle: return .cycle
        case .swim: return .swim
        case .hiit: return .hiit
        case .boxing: return .boxing
        case .rowing: return .rowing
        case .elliptical, .stairClimber: return .other
        case .other: return .other
        }
    }
}
