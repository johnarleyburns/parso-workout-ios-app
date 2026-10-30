import Foundation
import SwiftData

/// Watch-only read model of one cardio workout mirrored from the iPhone over
/// WatchConnectivity. It is deliberately not a `CardioWorkout` or `WorkoutSession`:
/// the phone owns the real record, and this projection carries no heart-rate
/// samples, routes, notes, calories, source bundle identifiers or device identifiers.
///
/// It belongs to `CadenceStore.watchSchema` only, never to `schema`, `localSchema`
/// or the phone's CloudKit `syncSchema`.
@Model
public final class WatchCardioHistoryRecord {
    /// The phone's stable row UUID.
    public var id: UUID = UUID()
    public var healthKitUUID: UUID?
    /// Raw `CardioType` value as sent by the phone.
    public var typeRaw: String = CardioType.other.rawValue
    public var title: String = ""
    public var start: Date = Date()
    public var end: Date?
    /// Meters.
    public var distanceMeters: Double?
    /// Raw `CardioRecordOrigin` value.
    public var originRaw: String = CardioRecordOrigin.cladironRecorded.rawValue
    /// Already-presentable "Imported from …" text; nil for rows the user recorded.
    public var importLabel: String?
    public var updatedAt: Date = Date()

    public init(id: UUID = UUID(), healthKitUUID: UUID? = nil, typeRaw: String = CardioType.other.rawValue,
                title: String = "", start: Date = Date(), end: Date? = nil, distanceMeters: Double? = nil,
                originRaw: String = CardioRecordOrigin.cladironRecorded.rawValue,
                importLabel: String? = nil, updatedAt: Date = Date()) {
        self.id = id; self.healthKitUUID = healthKitUUID; self.typeRaw = typeRaw
        self.title = title; self.start = start; self.end = end
        self.distanceMeters = distanceMeters; self.originRaw = originRaw
        self.importLabel = importLabel; self.updatedAt = updatedAt
    }
}
