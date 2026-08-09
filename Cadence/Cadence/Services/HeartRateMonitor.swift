import Foundation
import Observation
import CadenceCore
import CadenceFeatures
import CoreBluetooth

/// Observable heart-rate monitor for the iPhone (FR-2.3, FR-4.4). Connects to a
/// BLE strap exposing the standard Heart Rate Service (0x180D / char 0x2A37),
/// reconnects with exponential backoff, surfaces battery + signal state, and
/// buffers the last known BPM during short signal drops.
///
/// Has a `simulated` mode used by previews and UI tests (the simulator has no
/// Bluetooth), where scanning yields fake devices and connecting emits a
/// deterministic BPM stream.
@Observable
final class HeartRateMonitor: NSObject, HeartRateMonitoring, @unchecked Sendable {

    // CBUUID is not Sendable in the iOS 26 SDK. Keep these as computed values
    // so Swift 6 does not treat shared CBUUID instances as mutable global state.
    static var heartRateService: CBUUID { CBUUID(string: "180D") }
    static var heartRateMeasurement: CBUUID { CBUUID(string: "2A37") }
    static var batteryService: CBUUID { CBUUID(string: "180F") }
    static var batteryLevel: CBUUID { CBUUID(string: "2A19") }

    /// Maximum reconnection attempts before giving up (FR-4.4).
    private var maxReconnectAttempts: Int = 5
    /// How long to hold the last known BPM after a disconnect (FR-2.3, UC-4 alt 3a).
    private let bufferWindow: TimeInterval = 10
    /// Battery refresh interval (FR-4.4, UC-4 alt 4a).
    private let batteryRefreshInterval: TimeInterval = 60
    /// Battery threshold for the low-battery warning (FR-4.4, UC-4 alt 4a).
    private let criticalBatteryThreshold: Int = 10

    private(set) var state: HRMConnectionState = .idle
    /// Live BPM, falling back to the last-known value during brief signal drops
    /// (buffered for up to `bufferWindow` seconds — FR-2.3, UC-4 alt 3a).
    private(set) var currentBPM: Double? {
        get { _bpm ?? (bufferExpiryTime != nil ? lastKnownBPM : nil) }
        set { _bpm = newValue; if newValue != nil { lastKnownBPM = nil; bufferExpiryTime = nil } }
    }
    private var _bpm: Double?
    private(set) var battery: Int?
    private(set) var discovered: [DiscoveredHRM] = []
    private(set) var connectionError: String?
    private(set) var criticalBattery: Bool = false

    private let simulated: Bool
    private var simulationTick = 0
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var rememberedID: UUID?
    private var simTimer: Timer?

    // Reconnection backoff (FR-4.4).
    private var reconnectAttempts: Int = 0
    private var reconnectTimer: Timer?

    // HR buffering during signal drops (FR-2.3, UC-4 alt 3a).
    private var lastKnownBPM: Double?
    private var bufferExpiryTime: Date?
    private var bufferTimer: Timer?

    // Battery refresh (FR-4.4).
    private var batteryReadTimer: Timer?

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

    /// Restores the default device from persistent storage so connection
    /// happens automatically at next BLE power-on (FR-4.4 cold-launch).
    func restoreDefaultDevice(_ id: UUID) {
        rememberedID = id
        if let central, central.state == .poweredOn, state != .connected(id) {
            connect(id)
        }
    }

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
        cancelAllScheduledWork()
        reconnectAttempts = 0
        connectionError = nil
        rememberedID = id
        if simulated {
            state = .connecting(id)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
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
        cancelAllScheduledWork()
        if simulated {
            simTimer?.invalidate(); simTimer = nil
            currentBPM = nil; lastKnownBPM = nil; bufferExpiryTime = nil
            state = .idle
            return
        }
        if let peripheral { central?.cancelPeripheralConnection(peripheral) }
        currentBPM = nil; lastKnownBPM = nil; bufferExpiryTime = nil
        state = .idle
    }

    // MARK: External injection (FR-8 — Watch HR relay)

    /// Feeds a live BPM value from an external source (e.g. the Apple Watch via
    /// WCSession) into the same pipeline used by the BLE chest strap.  Clears
    /// any active buffer, sets state to `.external` so consumers can
    /// distinguish the source, and marks battery as nil (watch battery is
    /// separate).
    func injectExternalBPM(_ bpm: Double) {
        _bpm = bpm
        lastKnownBPM = nil
        bufferExpiryTime = nil
        bufferTimer?.invalidate(); bufferTimer = nil
        battery = nil
        if case .connected = state { return }
        state = .connected(UUID()) // external source placeholder
    }

    // MARK: Internal helpers

    private func startSimFeed() {
        simTimer?.invalidate()
        simulationTick = 0
        currentBPM = 132
        simTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.simulationTick += 1
            let t = Double(self.simulationTick)
            self.currentBPM = 130 + 25 * (0.5 + 0.5 * sin(t / 8))
        }
    }

    /// Cancel all pending timers (reconnect schedule, buffer expiry, battery refresh).
    private func cancelAllScheduledWork() {
        reconnectTimer?.invalidate(); reconnectTimer = nil
        bufferTimer?.invalidate(); bufferTimer = nil
        batteryReadTimer?.invalidate(); batteryReadTimer = nil
    }

    /// Starts the buffer that holds the last known BPM for `bufferWindow` seconds.
    private func startBuffer() {
        guard let bpm = currentBPM else { return }
        lastKnownBPM = bpm
        bufferExpiryTime = Date().addingTimeInterval(bufferWindow)
        scheduleBufferExpiry()
    }

    private func scheduleBufferExpiry() {
        bufferTimer?.invalidate()
        bufferTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let expiry = self.bufferExpiryTime, Date() >= expiry else { return }
            self.lastKnownBPM = nil
            self.bufferExpiryTime = nil
            self.currentBPM = nil
            self.bufferTimer?.invalidate(); self.bufferTimer = nil
        }
    }

    /// Schedules a reconnection attempt with exponential backoff (1, 2, 4, 8, 16 s).
    private func scheduleReconnect() {
        let delay = pow(2.0, Double(reconnectAttempts))
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, let peripheral = self.peripheral else { return }
            self.reconnectAttempts += 1
            if self.reconnectAttempts >= self.maxReconnectAttempts {
                self.state = .reconnectionFailed(peripheral.identifier, error: "Reconnection failed after \(self.maxReconnectAttempts) attempts")
                self.connectionError = "Reconnection failed after \(self.maxReconnectAttempts) attempts"
                self.lastKnownBPM = nil; self.bufferExpiryTime = nil
                self.currentBPM = nil
                self.bufferTimer?.invalidate(); self.bufferTimer = nil
                return
            }
            self.state = .reconnecting(peripheral.identifier, attempts: self.reconnectAttempts)
            self.central?.connect(peripheral)
        }
    }

    /// Starts periodic battery level reads (FR-4.4).
    private func startBatteryRefresh() {
        batteryReadTimer?.invalidate()
        batteryReadTimer = Timer.scheduledTimer(withTimeInterval: batteryRefreshInterval, repeats: true) { [weak self] _ in
            guard let self, let peripheral = self.peripheral else { return }
            for s in peripheral.services ?? [] where s.uuid == Self.batteryService {
                for c in s.characteristics ?? [] where c.uuid == Self.batteryLevel {
                    peripheral.readValue(for: c)
                    return
                }
            }
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
            if let id = rememberedID, state != .connected(id) { connect(id) }
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
        reconnectAttempts = 0
        peripheral.delegate = self
        peripheral.discoverServices([Self.heartRateService, Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // Buffer the last known BPM for a grace window (FR-2.3, UC-4 alt 3a).
        startBuffer()
        _bpm = nil

        // Exponential backoff reconnection (FR-4.4).
        if reconnectAttempts < maxReconnectAttempts {
            state = .reconnecting(peripheral.identifier, attempts: reconnectAttempts)
            scheduleReconnect()
        } else {
            state = .reconnectionFailed(peripheral.identifier, error: "Reconnection failed after \(maxReconnectAttempts) attempts")
            connectionError = "Reconnection failed after \(maxReconnectAttempts) attempts"
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let msg = error?.localizedDescription ?? "Connection failed"
        connectionError = msg
        state = .reconnectionFailed(peripheral.identifier, error: msg)
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
            else if c.uuid == Self.batteryLevel {
                peripheral.readValue(for: c)
                // Start periodic battery refresh after initial read (FR-4.4).
                startBatteryRefresh()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        if characteristic.uuid == Self.heartRateMeasurement {
            currentBPM = HeartRateParser.parse(data) // setter clears any active buffer
        } else if characteristic.uuid == Self.batteryLevel, let first = data.first {
            battery = Int(first)
            criticalBattery = Int(first) <= criticalBatteryThreshold
        }
    }
}
