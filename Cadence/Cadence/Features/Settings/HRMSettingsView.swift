import SwiftUI
import SwiftData
import CadenceCore

/// Pair and manage a Bluetooth heart-rate monitor (FR-4.4, UC-5).
struct HRMSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query private var savedDevices: [HRMDevice]

    private var hrm: HeartRateMonitor { model.hrm }
    private var defaultDevice: HRMDevice? { savedDevices.first { $0.isDefault } }

    var body: some View {
        List {
            if let device = defaultDevice {
                Section("My Device") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(device.name).font(.headline)
                            if isConnected(device.id) {
                                Text("Connected").font(.caption)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            if let bpm = hrm.currentBPM {
                                Text("\(Int(bpm)) bpm").monospacedDigit()
                                    .accessibilityIdentifier("hrm.bpm")
                            }
                        }
                        HStack {
                            Label("Heart Rate Service · 0x180D", systemImage: "heart.fill")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let battery = hrm.battery ?? device.lastBattery {
                                Label("\(battery)%", systemImage: "battery.75")
                                    .font(.caption).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("hrm.battery")
                            }
                        }
                    }
                    Button("Forget Device", role: .destructive) {
                        hrm.disconnect()
                        context.delete(device)
                        try? context.save()
                    }
                    .accessibilityIdentifier("hrm.forget")
                }
            }

            Section {
                ForEach(hrm.discovered) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("Heart Rate Service · 0x180D")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Connect") { connect(device) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("hrm.connect.\(device.name)")
                    }
                }
            } header: {
                HStack {
                    Text("Discovered Devices")
                    Spacer()
                    if case .scanning = hrm.state { ProgressView() }
                }
            } footer: {
                Text("Make sure the strap is awake and the electrodes are damp. Cladiron reconnects to your default device automatically.")
            }

            Section {
                Button("Scan for Devices") { hrm.startScanning() }
                    .accessibilityIdentifier("hrm.scan")
            }
        }
        .navigationTitle("Heart-Rate Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hrm.startScanning() }
        .onDisappear { hrm.stopScanning() }
    }

    private func isConnected(_ id: UUID) -> Bool {
        if case .connected(let cid) = hrm.state { return cid == id }
        return false
    }

    private func connect(_ device: DiscoveredHRM) {
        hrm.connect(device.id)
        hrm.rememberDevice(device.id)
        // Persist as the default remembered device.
        for d in savedDevices { d.isDefault = false }
        if let existing = savedDevices.first(where: { $0.id == device.id }) {
            existing.isDefault = true
            existing.lastConnectedAt = Date()
        } else {
            context.insert(HRMDevice(id: device.id, name: device.name,
                                     isDefault: true, lastConnectedAt: Date()))
        }
        try? context.save()
    }
}
