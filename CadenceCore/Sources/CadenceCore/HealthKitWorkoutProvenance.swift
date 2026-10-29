import Foundation

/// Who created a `CardioWorkout` row. Distinct from `CardioSource`, which only
/// says which Cladiron surface/sensor recorded a workout. This is the ownership
/// boundary for Health backups: only `.cladironRecorded` rows are ever written
/// back to HealthKit.
public enum CardioRecordOrigin: String, Codable, Sendable {
    case cladironRecorded
    case healthKitImported
    case manuallyLogged
    /// A raw value written by a newer build. Treated conservatively (never backed up).
    case unrecognized
}

/// Truthful HealthKit source/device facts for an imported workout. Raw values are
/// kept for diagnostics; ordinary UI shows only the presenter's display labels.
public struct HealthKitWorkoutProvenance: Codable, Equatable, Sendable {
    public let sourceName: String
    public let sourceBundleIdentifier: String
    public let sourceVersion: String?
    public let productType: String?
    public let deviceName: String?
    public let deviceManufacturer: String?
    public let deviceModel: String?
    public let deviceHardwareVersion: String?
    public let deviceSoftwareVersion: String?
    public let workoutBrandName: String?
    public let isAppleFitnessPlus: Bool

    public init(sourceName: String, sourceBundleIdentifier: String,
                sourceVersion: String? = nil, productType: String? = nil,
                deviceName: String? = nil, deviceManufacturer: String? = nil,
                deviceModel: String? = nil, deviceHardwareVersion: String? = nil,
                deviceSoftwareVersion: String? = nil, workoutBrandName: String? = nil,
                isAppleFitnessPlus: Bool = false) {
        self.sourceName = sourceName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceVersion = sourceVersion
        self.productType = productType
        self.deviceName = deviceName
        self.deviceManufacturer = deviceManufacturer
        self.deviceModel = deviceModel
        self.deviceHardwareVersion = deviceHardwareVersion
        self.deviceSoftwareVersion = deviceSoftwareVersion
        self.workoutBrandName = workoutBrandName
        self.isAppleFitnessPlus = isAppleFitnessPlus
    }

    /// Versioned on-disk envelope so the shape can evolve additively.
    private struct Envelope: Codable {
        var version: Int
        var provenance: HealthKitWorkoutProvenance
    }

    public static let currentEncodingVersion = 1

    public func encodedString() -> String {
        let envelope = Envelope(version: Self.currentEncodingVersion, provenance: self)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    /// nil for empty, malformed, or newer-than-understood payloads.
    public static func decode(_ string: String) -> HealthKitWorkoutProvenance? {
        guard !string.isEmpty, let data = string.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version <= currentEncodingVersion else { return nil }
        return envelope.provenance
    }
}

extension CardioWorkout {
    /// Effective origin. A missing raw value is a legacy row: recorded by
    /// Cladiron unless it carries an imported-kind marker. Reading never mutates.
    public var originValue: CardioRecordOrigin {
        get {
            guard let raw = recordOriginRaw else {
                return importedWorkoutKindRaw != nil ? .healthKitImported
                    : (isLogged ? .manuallyLogged : .cladironRecorded)
            }
            return CardioRecordOrigin(rawValue: raw) ?? .unrecognized
        }
        set { recordOriginRaw = newValue.rawValue }
    }

    public var healthKitProvenance: HealthKitWorkoutProvenance? {
        get { HealthKitWorkoutProvenance.decode(healthKitProvenanceData) }
        set { healthKitProvenanceData = newValue?.encodedString() ?? "" }
    }

    /// The single authority for whether this row may be emitted as a Cladiron
    /// Health backup. Imported, manually logged and unrecognized rows never are,
    /// regardless of `sourceValue`.
    public var isCladironHealthBackupEligible: Bool {
        originValue == .cladironRecorded && !isLogged
    }
}

extension HealthBackupEncoder {
    /// Backup summary for a row, or nil when the row is not Cladiron-owned.
    public static func cardioBackupSummary(for cardio: CardioWorkout) -> CardioWorkoutSummary? {
        cardio.isCladironHealthBackupEligible ? cardioSummary(for: cardio) : nil
    }
}
