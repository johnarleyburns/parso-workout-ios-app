import Foundation
import CoreBluetooth
import CadenceFeatures

/// Direct CoreBluetooth chest-strap heart-rate monitor for watchOS.
///
/// Scans for BLE HR monitors (0x180D service), connects, reads
/// 0x2A37 (Heart Rate Measurement) via notify, and reports battery
/// level via 0x180F/0x2A19. Reuses `HeartRateParser` from CadenceFeatures
/// for payload parsing — same parser used by the phone-side BLE stack.
///
/// The watch runs this independently of the phone; no WCSession relay needed
/// when the user chooses "Chest Strap" as their HR source.
final class WatchHeartRateBLE: NSObject {
    enum Event {
        case scanning
        case connected(battery: Int?)
        case disconnected
        case bpm(Double)
        case batteryUpdated(Int)
    }

    private let onEvent: (Event) -> Void
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var heartRateChar: CBCharacteristic?

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
        super.init()
    }

    func start() {
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func disconnect() {
        if let p = peripheral { central?.cancelPeripheralConnection(p) }
        central?.stopScan()
        peripheral = nil
        heartRateChar = nil
    }

    private let heartRateService = CBUUID(string: "180D")
    private let heartRateMeasurement = CBUUID(string: "2A37")
    private let batteryService = CBUUID(string: "180F")
    private let batteryLevel = CBUUID(string: "2A19")
}

extension WatchHeartRateBLE: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        onEvent(.scanning)
        central.scanForPeripherals(withServices: [heartRateService], options: nil)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard self.peripheral == nil else { return }
        self.peripheral = peripheral
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([heartRateService, batteryService])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        onEvent(.disconnected)
        heartRateChar = nil
    }
}

extension WatchHeartRateBLE: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for svc in services {
            peripheral.discoverCharacteristics(
                svc.uuid == heartRateService ? [heartRateMeasurement] : [batteryLevel],
                for: svc)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            if c.uuid == heartRateMeasurement {
                heartRateChar = c
                peripheral.setNotifyValue(true, for: c)
            } else if c.uuid == batteryLevel {
                peripheral.readValue(for: c)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        if characteristic.uuid == heartRateMeasurement {
            if let bpm = HeartRateParser.parse(data) {
                onEvent(.bpm(bpm))
            }
        } else if characteristic.uuid == batteryLevel {
            let pct = data.withUnsafeBytes { $0.load(as: UInt8.self) }
            onEvent(.batteryUpdated(Int(pct)))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic == heartRateChar {
            onEvent(.connected(battery: nil))
            // Read battery after HR notify is confirmed
            if let batSvc = peripheral.services?.first(where: { $0.uuid == batteryService }),
               let batChar = batSvc.characteristics?.first(where: { $0.uuid == batteryLevel }) {
                peripheral.readValue(for: batChar)
            }
        }
    }
}
