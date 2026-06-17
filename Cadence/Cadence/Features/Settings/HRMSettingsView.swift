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
    /// True when a scan has completed and found nothing (UC-5 alt 2a).
    @State private var scanTriedEmpty = false

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
                            } else if isReconnecting(device.id) {
                                Text("Reconnecting…").font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            if let bpm = hrm.currentBPM {
                                Text("\(Int(bpm)) bpm").monospacedDigit()
                                    .accessibilityIdentifier("hrm.bpm")
                            }
                        }
                        HStack {
                            if let error = hrm.connectionError {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption).foregroundStyle(.red)
                            } else {
                                Label("Heart Rate Service · 0x180D", systemImage: "heart.fill")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let battery = hrm.battery ?? device.lastBattery {
                                Label("\(battery)%", systemImage: battery <= 10 ? "battery.0" : "battery.75")
                                    .font(.caption)
                                    .foregroundStyle(battery <= 10 ? .red : .secondary)
                                    .accessibilityIdentifier("hrm.battery")
                            }
                        }
                        if hrm.criticalBattery {
                            Label("Battery critically low — charge your strap soon.", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2).foregroundStyle(.red)
                        }
                        if case .reconnectionFailed = hrm.state {
                            Button("Retry Connection") { hrm.connect(device.id) }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                    Button("Forget Device", role: .destructive) {
                        hrm.disconnect()
                        context.delete(device)
                        try? context.save()
                    }
                    .accessibilityIdentifier("hrm.forget")
                }
            }

            Section {
                if hrm.discovered.isEmpty, scanTriedEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No heart rate monitors found", systemImage: "heart.slash")
                            .font(.subheadline.weight(.medium))
                        Text("Make sure your chest strap is worn, the electrodes are damp, and the strap is within range. Some straps require you to wet the electrodes before each use.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
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
                if hrm.battery == nil, hrm.discovered.isEmpty {
                    Text("Make sure the strap is awake and the electrodes are damp. Cadence reconnects to your default device automatically.")
                }
            }

            Section {
                Button("Scan for Devices") {
                    scanTriedEmpty = false
                    hrm.startScanning()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        scanTriedEmpty = true
                    }
                }
                    .accessibilityIdentifier("hrm.scan")
            }
        }
        .navigationTitle("Heart-Rate Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            scanTriedEmpty = false
            hrm.startScanning()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                scanTriedEmpty = true
            }
        }
        .onDisappear { hrm.stopScanning() }
        .onChange(of: hrm.battery) { _, newValue in
            guard let device = defaultDevice, let battery = newValue else { return }
            device.lastBattery = battery
            device.updatedAt = Date()
            try? context.save()
        }
    }

    private func isConnected(_ id: UUID) -> Bool {
        if case .connected(let cid) = hrm.state { return cid == id }
        return false
    }

    private func isReconnecting(_ id: UUID) -> Bool {
        if case .reconnecting(let cid, _) = hrm.state { return cid == id }
        return false
    }

    private func connect(_ device: DiscoveredHRM) {
        hrm.connect(device.id)
        hrm.rememberDevice(device.id)
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
