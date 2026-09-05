#if canImport(CloudKit)
import CloudKit
import Foundation

/// CloudKit implementation of the explicit trainer↔client share boundary.
/// The Watch never constructs this type; the phone owns the shared-zone path.
public final class CloudKitClientShareStore: ClientShareStore, @unchecked Sendable {
    public static let planRecordType = "ClientPlan"
    public static let resultRecordType = "ClientShareResult"
    private static let rootRecordType = "ClientShareRoot"

    private let container: CKContainer

    public init(containerIdentifier: String = CadenceStore.cloudKitContainerID) {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    public func createShare(trainerID: String, clientID: String,
                            clientDisplayName: String,
                            at date: Date = Date()) async throws -> ClientShareInvitation {
        let zoneUUID = UUID()
        let database = container.privateCloudDatabase
        let zone = CKRecordZone(zoneID: Self.recordZoneID(for: zoneUUID))
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])

        let root = CKRecord(recordType: Self.rootRecordType,
                            recordID: CKRecord.ID(recordName: "root", zoneID: zone.zoneID))
        root["clientID"] = clientID as CKRecordValue
        root["clientDisplayName"] = clientDisplayName as CKRecordValue
        root["createdAt"] = date as CKRecordValue
        let share = CKShare(rootRecord: root)
        share.publicPermission = .none
        let result = try await database.modifyRecords(saving: [root, share], deleting: [])
        guard let savedShare = try Self.savedRecord(share.recordID, from: result.saveResults) as? CKShare,
              let shareURL = savedShare.url else {
            throw ClientShareStoreError.missingShareURL
        }
        return ClientShareInvitation(
            zoneID: zoneUUID,
            // The root record is deliberately named "root"; the zone UUID is
            // the stable value-level identity for this share invitation.
            shareID: zoneUUID,
            trainerID: trainerID, clientID: clientID,
            clientDisplayName: clientDisplayName, createdAt: date, shareURL: shareURL)
    }

    public func trainerConnection(for invitation: ClientShareInvitation,
                                  deviceID: String) async throws -> ClientShareConnection {
        guard invitation.shareURL != nil else { throw ClientShareStoreError.missingShareURL }
        return ClientShareConnection(zoneID: invitation.zoneID, actor: .trainer,
                                     actorID: invitation.trainerID, deviceID: deviceID)
    }

    public func accept(_ invitation: ClientShareInvitation,
                       as clientID: String,
                       deviceID: String) async throws -> ClientShareConnection {
        guard clientID == invitation.clientID else { throw ClientShareStoreError.notParticipant }
        guard let shareURL = invitation.shareURL else { throw ClientShareStoreError.missingShareURL }
        let metadataResult = try await container.shareMetadatas(for: [shareURL])
        guard let metadata = try metadataResult[shareURL]?.get() else {
            throw ClientShareStoreError.unknownZone
        }
        _ = try await container.accept([metadata])
        return ClientShareConnection(zoneID: invitation.zoneID, actor: .client,
                                     actorID: clientID, deviceID: deviceID)
    }

    public func writePlan(_ plan: Plan, using connection: ClientShareConnection,
                          sentAt: Date, editedAt: Date) async throws -> ClientShareChangeToken {
        guard connection.actor == .trainer else { throw ClientShareStoreError.trainerOnly }
        let database = database(for: connection)
        let recordID = CKRecord.ID(recordName: "latest",
                                   zoneID: Self.recordZoneID(for: connection.zoneID))
        let existingRecord = try await database.records(for: [recordID])[recordID].flatMap {
            try? $0.get()
        }
        if let existingRecord,
           let existingPlan = try? Self.decodePlan(existingRecord) {
            let losesTie = editedAt == existingPlan.lastEditedAt &&
                connection.deviceID <= existingPlan.lastEditedBy
            guard editedAt > existingPlan.lastEditedAt || !losesTie else {
                return ClientShareChangeToken(sequence: existingPlan.revision)
            }
        }

        let record = existingRecord ?? CKRecord(recordType: Self.planRecordType, recordID: recordID)
        record["payloadVersion"] = Int64(UnifiedPlanStore.currentPayloadVersion) as CKRecordValue
        record["planData"] = try UnifiedPlanStore.encode(plan) as CKRecordValue
        record["sentAt"] = sentAt as CKRecordValue
        record["updatedAt"] = editedAt as CKRecordValue
        record["lastEditedBy"] = connection.deviceID as CKRecordValue
        let previousRevision = (record["revision"] as? Int64).map(Int.init) ?? 0
        record["revision"] = Int64(previousRevision + 1) as CKRecordValue
        let result = try await database.modifyRecords(
            saving: [record], deleting: [], savePolicy: .changedKeys, atomically: true)
        _ = try Self.savedRecord(recordID, from: result.saveResults)
        return ClientShareChangeToken(sequence: previousRevision + 1)
    }

    public func currentPlan(using connection: ClientShareConnection) async throws -> ClientSharedPlan? {
        let recordID = CKRecord.ID(recordName: "latest", zoneID: Self.recordZoneID(for: connection.zoneID))
        let database = database(for: connection)
        let result = try await database.records(for: [recordID])
        guard let recordResult = result[recordID] else { return nil }
        guard let record = try? recordResult.get() else { return nil }
        return try Self.decodePlan(record)
    }

    public func append(_ result: ClientShareResult,
                       using connection: ClientShareConnection) async throws -> Bool {
        guard connection.actor == .client else { throw ClientShareStoreError.clientOnly }
        let database = database(for: connection)
        let recordID = CKRecord.ID(recordName: result.id.uuidString,
                                   zoneID: Self.recordZoneID(for: connection.zoneID))
        let existingResults = try await database.records(for: [recordID])
        if let existingResult = existingResults[recordID],
           let existing = try? existingResult.get() {
            guard try Self.decodeResult(existing) == result else {
                throw ClientShareStoreError.conflictingResultID
            }
            return false
        }
        let record = CKRecord(recordType: Self.resultRecordType, recordID: recordID)
        record["sessionID"] = result.sessionID.uuidString as CKRecordValue
        record["kind"] = result.kind.rawValue as CKRecordValue
        record["recordedAt"] = result.recordedAt as CKRecordValue
        record["payload"] = result.payload as CKRecordValue
        _ = try await database.modifyRecords(saving: [record], deleting: [],
                                              savePolicy: .ifServerRecordUnchanged,
                                              atomically: true)
        return true
    }

    public func changes(using connection: ClientShareConnection,
                        since token: ClientShareChangeToken? = nil) async throws -> ClientShareChangePage {
        let database = database(for: connection)
        let serverToken = Self.unarchiveToken(token?.serverTokenData)
        let result = try await database.recordZoneChanges(
            inZoneWith: Self.recordZoneID(for: connection.zoneID), since: serverToken)
        var changes: [ClientShareChange] = []
        for modificationResult in result.modificationResultsByID.values {
            guard let modification = try? modificationResult.get() else { continue }
            let record = modification.record
            if record.recordType == Self.planRecordType {
                changes.append(.plan(try Self.decodePlan(record)))
            } else if record.recordType == Self.resultRecordType {
                changes.append(.result(try Self.decodeResult(record)))
            }
        }
        let nextData = try NSKeyedArchiver.archivedData(
            withRootObject: result.changeToken, requiringSecureCoding: true)
        return ClientShareChangePage(
            changes: changes,
            nextToken: ClientShareChangeToken(
                sequence: (token?.sequence ?? 0) + changes.count,
                serverTokenData: nextData))
    }

    private func database(for connection: ClientShareConnection) -> CKDatabase {
        connection.actor == .trainer ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    private static func recordZoneID(for zoneUUID: UUID) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: "client-\(zoneUUID.uuidString)",
                        ownerName: CKCurrentUserDefaultName)
    }

    private static func savedRecord(_ id: CKRecord.ID,
                                    from results: [CKRecord.ID: Result<CKRecord, Error>]) throws -> CKRecord {
        guard let result = results[id] else { throw ClientShareStoreError.unknownZone }
        return try result.get()
    }

    private static func decodePlan(_ record: CKRecord) throws -> ClientSharedPlan {
        guard let data = record["planData"] as? Data,
              let sentAt = record["sentAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date,
              let lastEditedBy = record["lastEditedBy"] as? String else {
            throw ClientShareStoreError.invalidPayload
        }
        let version = (record["payloadVersion"] as? Int64).map(Int.init) ?? 1
        let plan = try UnifiedPlanStore.decode(data, version: version)
        let revision = (record["revision"] as? Int64).map(Int.init) ?? 1
        return ClientSharedPlan(plan: plan, revision: revision, sentAt: sentAt,
                                lastEditedAt: updatedAt, lastEditedBy: lastEditedBy)
    }

    private static func decodeResult(_ record: CKRecord) throws -> ClientShareResult {
        guard let sessionString = record["sessionID"] as? String,
              let sessionID = UUID(uuidString: sessionString),
              let kindString = record["kind"] as? String,
              let kind = ClientShareResult.Kind(rawValue: kindString),
              let recordedAt = record["recordedAt"] as? Date,
              let payload = record["payload"] as? Data else {
            throw ClientShareStoreError.invalidPayload
        }
        return ClientShareResult(id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
                                 sessionID: sessionID, kind: kind,
                                 recordedAt: recordedAt, payload: payload)
    }

    private static func unarchiveToken(_ data: Data?) -> CKServerChangeToken? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self,
                                                       from: data)
    }
}
#endif
