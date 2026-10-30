import Foundation
import SwiftData
import CadenceCore

extension WatchSync.Key {
    /// Property-list rows of `WatchSync.CardioHistoryItem`.
    public static let cardioHistoryItems = "cardioHistory.items"
    public static let cardioHistoryUpdatedAt = "cardioHistory.updatedAt"
}

extension WatchSync {
    /// Property-list-safe cardio history row sent phone → Watch. This is an explicit
    /// projection, never a serialized SwiftData model: it carries no HR samples, routes,
    /// notes, calories, source bundle IDs, device identifiers or HealthKit metadata.
    public struct CardioHistoryItem: Equatable, Sendable {
        public static let currentVersion = 1
        public static let maxTextLength = 120

        public var id: UUID
        public var healthKitUUID: UUID?
        /// Raw `CardioType` value.
        public var type: String
        public var title: String
        public var start: Date
        public var end: Date?
        /// Meters.
        public var distanceMeters: Double?
        /// Raw `CardioRecordOrigin` value.
        public var origin: String
        /// Already-presentable "Imported from …" text; only on imported rows.
        public var importLabel: String?
        public var updatedAt: Date
        /// Tombstone: remove this previously mirrored row on the Watch.
        public var isDeleted: Bool

        public init(id: UUID, healthKitUUID: UUID? = nil, type: String, title: String, start: Date,
                    end: Date? = nil, distanceMeters: Double? = nil, origin: String,
                    importLabel: String? = nil, updatedAt: Date, isDeleted: Bool = false) {
            self.id = id; self.healthKitUUID = healthKitUUID; self.type = type
            self.title = String(title.prefix(Self.maxTextLength)); self.start = start; self.end = end
            self.distanceMeters = distanceMeters; self.origin = origin
            self.importLabel = importLabel.map { String($0.prefix(Self.maxTextLength)) }
            self.updatedAt = updatedAt; self.isDeleted = isDeleted
        }

        public var propertyList: [String: Any] {
            var row: [String: Any] = [
                "v": Self.currentVersion, "id": id.uuidString, "type": type, "title": title,
                "start": start, "origin": origin, "updatedAt": updatedAt, "deleted": isDeleted
            ]
            if let healthKitUUID { row["hk"] = healthKitUUID.uuidString }
            if let end { row["end"] = end }
            if let distanceMeters { row["distance"] = distanceMeters }
            if let importLabel { row["importLabel"] = importLabel }
            return row
        }

        /// Nil for any malformed row (wrong types, newer version, non-finite or negative distance).
        public init?(propertyList row: [String: Any]) {
            guard (row["v"] as? Int).map({ $0 >= 1 && $0 <= Self.currentVersion }) == true,
                  let rawID = row["id"] as? String, let id = UUID(uuidString: rawID),
                  let type = row["type"] as? String, let title = row["title"] as? String,
                  let start = row["start"] as? Date, let origin = row["origin"] as? String,
                  let updatedAt = row["updatedAt"] as? Date, let deleted = row["deleted"] as? Bool
            else { return nil }
            var healthKitUUID: UUID?
            if let raw = row["hk"] {
                guard let string = raw as? String, let uuid = UUID(uuidString: string) else { return nil }
                healthKitUUID = uuid
            }
            var end: Date?
            if let raw = row["end"] {
                guard let date = raw as? Date else { return nil }
                end = date
            }
            var distance: Double?
            if let raw = row["distance"] {
                guard let number = (raw as? NSNumber)?.doubleValue, number.isFinite, number >= 0 else { return nil }
                distance = number
            }
            var label: String?
            if let raw = row["importLabel"] {
                guard let string = raw as? String else { return nil }
                label = string
            }
            self.init(id: id, healthKitUUID: healthKitUUID, type: type, title: title, start: start,
                      end: end, distanceMeters: distance, origin: origin, importLabel: label,
                      updatedAt: updatedAt, isDeleted: deleted)
        }
    }

    /// A bounded, ordered cardio history snapshot. Applying it replaces the Watch's
    /// phone-mirrored rows: rows absent from `items` (and tombstoned rows) are removed.
    public struct CardioHistorySnapshot: Equatable, Sendable {
        public static let maxLiveItems = 60
        public static let maxAgeDays = 90
        /// Upper bound accepted on the Watch, so a hostile or corrupt payload cannot grow the store.
        public static let maxIncomingItems = 240

        public var items: [CardioHistoryItem]
        public var updatedAt: Date

        public init(items: [CardioHistoryItem], updatedAt: Date) {
            self.items = items.sorted(by: Self.order)
            self.updatedAt = updatedAt
        }

        public var liveItems: [CardioHistoryItem] { items.filter { !$0.isDeleted } }
        public var tombstones: [CardioHistoryItem] { items.filter(\.isDeleted) }

        /// Start descending, then UUID, so the payload is deterministic.
        static func order(_ a: CardioHistoryItem, _ b: CardioHistoryItem) -> Bool {
            a.start != b.start ? a.start > b.start : a.id.uuidString < b.id.uuidString
        }

        /// Deterministic content fingerprint (excludes the snapshot `updatedAt` stamp).
        public var fingerprint: String {
            WatchSyncFingerprint.canonicalHash(items.map(\.propertyList))
        }

        public var contextDict: [String: Any] {
            [Key.cardioHistoryItems: items.map(\.propertyList), Key.cardioHistoryUpdatedAt: updatedAt]
        }
    }

    /// Result of parsing the cardio-history keys of a context.
    public enum CardioHistoryPayload: Equatable, Sendable {
        /// Key omitted (older phone): keep the Watch's current cache.
        case absent
        /// A fully valid snapshot; an empty one is an explicit "clear mirrored rows".
        case snapshot(CardioHistorySnapshot)
        /// Present but invalid: reject the whole payload, keep the current cache.
        case malformed

        public init(context: [String: Any]) {
            guard let raw = context[Key.cardioHistoryItems] else { self = .absent; return }
            guard let rows = raw as? [[String: Any]], rows.count <= CardioHistorySnapshot.maxIncomingItems else {
                self = .malformed; return
            }
            let items = rows.compactMap(CardioHistoryItem.init(propertyList:))
            guard items.count == rows.count, Set(items.map(\.id)).count == items.count else {
                self = .malformed; return
            }
            self = .snapshot(CardioHistorySnapshot(
                items: items, updatedAt: (context[Key.cardioHistoryUpdatedAt] as? Date) ?? Date()))
        }
    }
}

/// Pure phone-side projection of `CardioWorkout` rows into the bounded Watch snapshot.
public enum WatchCardioHistoryProjection {
    /// - Parameter previousLiveIDs: ids published in the previous snapshot; those no longer
    ///   live become tombstones so an offline-then-reconnected Watch removes them.
    public static func snapshot(from rows: [CardioWorkout], previousLiveIDs: Set<UUID> = [],
                                now: Date, calendar: Calendar = .current) -> WatchSync.CardioHistorySnapshot {
        let cutoff = calendar.date(byAdding: .day, value: -WatchSync.CardioHistorySnapshot.maxAgeDays, to: now)
            ?? now.addingTimeInterval(-90 * 86_400)
        // One identity per source workout: the newest row wins a repeated HealthKit UUID.
        var byIdentity: [String: CardioWorkout] = [:]
        for row in rows where row.deletedAt == nil && row.end != nil && row.start >= cutoff {
            let key = row.healthKitWorkoutUUID?.uuidString ?? "row-\(row.id.uuidString)"
            if let existing = byIdentity[key], !isPreferred(row, over: existing) { continue }
            byIdentity[key] = row
        }
        let live = byIdentity.values.map(item(for:)).sorted(by: WatchSync.CardioHistorySnapshot.order)
            .prefix(WatchSync.CardioHistorySnapshot.maxLiveItems)
        let liveIDs = Set(live.map(\.id))
        let known = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let tombstones = previousLiveIDs.subtracting(liveIDs).map { id -> WatchSync.CardioHistoryItem in
            let row = known[id]
            return WatchSync.CardioHistoryItem(
                id: id, type: row?.type ?? CardioType.other.rawValue, title: "",
                start: row?.start ?? Date(timeIntervalSince1970: 0),
                origin: CardioRecordOrigin.unrecognized.rawValue,
                updatedAt: row?.updatedAt ?? Date(timeIntervalSince1970: 0), isDeleted: true)
        }
        return WatchSync.CardioHistorySnapshot(items: Array(live) + tombstones, updatedAt: now)
    }

    private static func isPreferred(_ a: CardioWorkout, over b: CardioWorkout) -> Bool {
        a.updatedAt != b.updatedAt ? a.updatedAt > b.updatedAt : a.id.uuidString < b.id.uuidString
    }

    static func item(for row: CardioWorkout) -> WatchSync.CardioHistoryItem {
        let origin = row.originValue
        let label = origin == .healthKitImported
            ? HealthKitWorkoutOriginPresenter.label(for: row.healthKitProvenance).primary : nil
        return WatchSync.CardioHistoryItem(
            id: row.id, healthKitUUID: row.healthKitWorkoutUUID, type: row.type, title: row.displayTitle,
            start: row.start, end: row.end, distanceMeters: row.distance.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil },
            origin: origin.rawValue, importLabel: label, updatedAt: row.updatedAt)
    }
}

/// Atomic Watch persistence of the phone-mirrored cardio projection.
public enum WatchCardioHistoryStore {
    /// Replaces the mirrored rows with `snapshot`. Saves once; on a failed save the context is
    /// rolled back and the error rethrown, so the previous projection stays intact.
    @discardableResult
    public static func apply(_ snapshot: WatchSync.CardioHistorySnapshot, in context: ModelContext,
                             save: (ModelContext) throws -> Void = { try $0.save() }) throws -> Int {
        let existing = try context.fetch(FetchDescriptor<WatchCardioHistoryRecord>())
        var byID: [UUID: WatchCardioHistoryRecord] = [:]
        var changed = 0
        for record in existing {
            if byID[record.id] != nil { context.delete(record); changed += 1 } else { byID[record.id] = record }
        }
        let live = snapshot.liveItems
        let liveIDs = Set(live.map(\.id))
        for record in byID.values where !liveIDs.contains(record.id) { context.delete(record); changed += 1 }
        for item in live {
            let record = byID[item.id] ?? WatchCardioHistoryRecord(id: item.id)
            if byID[item.id] == nil { context.insert(record) } else if !differs(record, item) { continue }
            record.healthKitUUID = item.healthKitUUID; record.typeRaw = item.type; record.title = item.title
            record.start = item.start; record.end = item.end; record.distanceMeters = item.distanceMeters
            record.originRaw = item.origin; record.importLabel = item.importLabel; record.updatedAt = item.updatedAt
            changed += 1
        }
        guard changed > 0 else { return 0 }
        do { try save(context) } catch {
            context.rollback()
            throw error
        }
        return changed
    }

    private static func differs(_ r: WatchCardioHistoryRecord, _ i: WatchSync.CardioHistoryItem) -> Bool {
        r.healthKitUUID != i.healthKitUUID || r.typeRaw != i.type || r.title != i.title || r.start != i.start
            || r.end != i.end || r.distanceMeters != i.distanceMeters || r.originRaw != i.origin
            || r.importLabel != i.importLabel || r.updatedAt != i.updatedAt
    }
}
