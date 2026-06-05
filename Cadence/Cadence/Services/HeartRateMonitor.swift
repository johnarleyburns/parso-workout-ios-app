import Foundation
import Observation
import CadenceCore
import CoreBluetooth

/// Observable heart-rate monitor for the iPhone (FR-2.3, FR-4.4). Connects to a
/// BLE strap exposing the standard Heart Rate Service (0x180D / char 0x2A37),
/// reconnects automatically, and surfaces battery + signal state.
///
/// Has a `simulated` mode used by previews and UI tests (the simulator has no
/// Bluetooth), where scanning yields fake devices and connecting emits a
/// deterministic BPM stream.
@Observable
final class HeartRateMonitor: NSObject, HeartRateMonitoring {

    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")

    private(set) var state: HRMConnectionState = .idle
    private(set) var currentBPM: Double?
    private(set) var battery: Int?
    private(set) var discovered: [DiscoveredHRM] = []

    private let simulated: Bool
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var rememberedID: UUID?
    private var simTimer: Timer?

    init(simulated: Bool) {
        self.simulated = simulated
        super.init()
        if !simulated {
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            state = .idle
        }
    }

    func rememberDevice(_ id: UUID?) { rememberedID = id }

    // MARK: Public control

    func startScanning() {
        if simulated {
            state = .scanning
            discovered = [
                DiscoveredHRM(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!, name: "Garmin HRM-Pro", rssi: -52),
                DiscoveredHRM(id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!, name: "Wahoo TICKR", rssi: -61)
            ]
            return
        }
        guard let central, central.state == .poweredOn else { return }
        state = .scanning
        central.scanForPeripherals(withServices: [Self.heartRateService])
    }

    func stopScanning() {
        if simulated { if case .scanning = state { state = .idle }; return }
        central?.stopScan()
        if case .scanning = state { state = .idle }
    }

    func connect(_ id: UUID) {
        rememberedID = id
        if simulated {
            state = .connecting(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self else { return }
                self.state = .connected(id)
                self.battery = 88
                self.startSimFeed()
            }
            return
        }
        guard let central else { return }
        if let p = central.retrievePeripherals(withIdentifiers: [id]).first {
            peripheral = p
            p.delegate = self
            state = .connecting(id)
            central.connect(p)
        } else {
            startScanning() // discover then connect
        }
    }

    func disconnect() {
        if simulated {
            simTimer?.invalidate(); simTimer = nil
            currentBPM = nil
            state = .idle
            return
        }
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        currentBPM = nil
        state = .idle
    }

    private func startSimFeed() {
        simTimer?.invalidate()
        var t = 0.0
        currentBPM = 132
        simTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            t += 1
            self?.currentBPM = 130 + 25 * (0.5 + 0.5 * sin(t / 8))
        }
    }
}

// MARK: - CoreBluetooth (real device path)

extension HeartRateMonitor: CBCentralManagerDelegate, CBPeripheralDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOff: state = .poweredOff
        case .unauthorized: state = .unauthorized
        case .poweredOn:
            if let rememberedID { connect(rememberedID) }
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Heart-Rate Monitor"
        let device = DiscoveredHRM(id: peripheral.identifier, name: name, rssi: RSSI.intValue)
        if !discovered.contains(where: { $0.id == device.id }) { discovered.append(device) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected(peripheral.identifier)
        peripheral.delegate = self
        peripheral.discoverServices([Self.heartRateService, Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Auto-reconnect (FR-4.4).
        state = .reconnecting(peripheral.identifier)
        central.connect(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            if service.uuid == Self.heartRateService {
                peripheral.discoverCharacteristics([Self.heartRateMeasurement], for: service)
            } else if service.uuid == Self.batteryService {
                peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == Self.heartRateMeasurement { peripheral.setNotifyValue(true, for: c) }
            else if c.uuid == Self.batteryLevel { peripheral.readValue(for: c) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        if characteristic.uuid == Self.heartRateMeasurement {
            currentBPM = Self.parseHeartRate(data)
        } else if characteristic.uuid == Self.batteryLevel, let first = data.first {
            battery = Int(first)
        }
    }

    /// Parses a 0x2A37 Heart Rate Measurement payload (8- or 16-bit format).
    static func parseHeartRate(_ data: Data) -> Double? {
        guard let flags = data.first else { return nil }
        let is16Bit = (flags & 0x01) != 0
        if is16Bit {
            guard data.count >= 3 else { return nil }
            let value = UInt16(data[1]) | (UInt16(data[2]) << 8)
            return Double(value)
        } else {
            guard data.count >= 2 else { return nil }
            return Double(data[1])
        }
    }
}
