import Foundation

/// The two identities that can write to a trainer/client shared zone.
public enum ClientShareActor: String, Codable, Equatable, Sendable {
    case trainer
    case client
}

/// An invitation is intentionally only a value-level representation of a
/// CloudKit share. The production adapter will replace the opaque IDs with the
/// real CKShare URL and record-zone metadata.
public struct ClientShareInvitation: Codable, Equatable, Sendable {
    public let zoneID: UUID
    public let shareID: UUID
    public let trainerID: String
    public let clientID: String
    public let clientDisplayName: String
    public let createdAt: Date

    public init(zoneID: UUID = UUID(), shareID: UUID = UUID(), trainerID: String,
                clientID: String, clientDisplayName: String, createdAt: Date = Date()) {
        self.zoneID = zoneID
        self.shareID = shareID
        self.trainerID = trainerID
        self.clientID = clientID
        self.clientDisplayName = clientDisplayName
        self.createdAt = createdAt
    }
}

public struct ClientShareConnection: Codable, Equatable, Sendable {
    public let zoneID: UUID
    public let actor: ClientShareActor
    public let actorID: String
    public let deviceID: String

    public init(zoneID: UUID, actor: ClientShareActor, actorID: String,
                deviceID: String) {
        self.zoneID = zoneID
        self.actor = actor
        self.actorID = actorID
        self.deviceID = deviceID
    }
}

/// An opaque, monotonically increasing cursor for one shared zone.
public struct ClientShareChangeToken: Codable, Hashable, Sendable {
    public let sequence: Int

    public init(sequence: Int) {
        self.sequence = sequence
    }
}

/// The plan stored in the shared zone. `calculatedWeight` values inside the
/// plan are already resolved by the send/preflight path and are never changed
/// by later athlete e1RM changes.
public struct ClientSharedPlan: Codable, Equatable, Sendable {
    public let plan: Plan
    public let revision: Int
    public let sentAt: Date
    public let lastEditedAt: Date
    public let lastEditedBy: String

    public init(plan: Plan, revision: Int, sentAt: Date, lastEditedAt: Date,
                lastEditedBy: String) {
        self.plan = plan
        self.revision = revision
        self.sentAt = sentAt
        self.lastEditedAt = lastEditedAt
        self.lastEditedBy = lastEditedBy
    }
}

public struct ClientShareResult: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Equatable, Sendable {
        case set
        case cardio
        case mobility
    }

    public let id: UUID
    public let sessionID: UUID
    public let kind: Kind
    public let recordedAt: Date
    /// The result payload is owned by the result type at the execution layer.
    /// Keeping this boundary as opaque data avoids coupling shared-zone code to
    /// SwiftData or a CloudKit record schema.
    public let payload: Data

    public init(id: UUID = UUID(), sessionID: UUID, kind: Kind,
                recordedAt: Date = Date(), payload: Data = Data()) {
        self.id = id
        self.sessionID = sessionID
        self.kind = kind
        self.recordedAt = recordedAt
        self.payload = payload
    }
}

public enum ClientShareChange: Codable, Equatable, Sendable {
    case plan(ClientSharedPlan)
    case result(ClientShareResult)
}

public struct ClientShareChangePage: Equatable, Sendable {
    public let changes: [ClientShareChange]
    public let nextToken: ClientShareChangeToken

    public init(changes: [ClientShareChange], nextToken: ClientShareChangeToken) {
        self.changes = changes
        self.nextToken = nextToken
    }
}

public enum ClientShareStoreError: Error, Equatable, Sendable {
    case unknownZone
    case notParticipant
    case trainerOnly
    case clientOnly
    case invalidChangeToken
    case conflictingResultID
}

/// Explicit shared-zone boundary. Private SwiftData mirroring remains a
/// separate concern; this protocol is for trainer↔client exchange only.
public protocol ClientShareStore: Sendable {
    func createShare(trainerID: String, clientID: String, clientDisplayName: String,
                     at date: Date) async throws -> ClientShareInvitation
    func trainerConnection(for invitation: ClientShareInvitation,
                           deviceID: String) async throws -> ClientShareConnection
    func accept(_ invitation: ClientShareInvitation,
                as clientID: String, deviceID: String) async throws -> ClientShareConnection
    func writePlan(_ plan: Plan, using connection: ClientShareConnection,
                   sentAt: Date, editedAt: Date) async throws -> ClientShareChangeToken
    func currentPlan(using connection: ClientShareConnection) async throws -> ClientSharedPlan?
    func append(_ result: ClientShareResult,
                using connection: ClientShareConnection) async throws -> Bool
    func changes(using connection: ClientShareConnection,
                 since token: ClientShareChangeToken?) async throws -> ClientShareChangePage
}

/// Deterministic contract implementation for headless tests. It models the
/// protocol boundaries and conflict policy without pretending to be CloudKit.
public actor InMemoryClientShareStore: ClientShareStore {
    private struct Zone {
        let invitation: ClientShareInvitation
        var acceptedClientID: String?
        var currentPlan: ClientSharedPlan?
        var events: [ClientShareChange] = []
        var results: [UUID: ClientShareResult] = [:]
    }

    private var zones: [UUID: Zone] = [:]

    public init() {}

    public func createShare(trainerID: String, clientID: String,
                            clientDisplayName: String,
                            at date: Date = Date()) async throws -> ClientShareInvitation {
        let invitation = ClientShareInvitation(
            trainerID: trainerID, clientID: clientID,
            clientDisplayName: clientDisplayName, createdAt: date)
        zones[invitation.zoneID] = Zone(invitation: invitation)
        return invitation
    }

    public func trainerConnection(for invitation: ClientShareInvitation,
                                  deviceID: String) async throws -> ClientShareConnection {
        guard let zone = zones[invitation.zoneID], zone.invitation == invitation else {
            throw ClientShareStoreError.unknownZone
        }
        return ClientShareConnection(zoneID: invitation.zoneID, actor: .trainer,
                                     actorID: invitation.trainerID, deviceID: deviceID)
    }

    public func accept(_ invitation: ClientShareInvitation,
                       as clientID: String,
                       deviceID: String) async throws -> ClientShareConnection {
        guard var zone = zones[invitation.zoneID], zone.invitation == invitation else {
            throw ClientShareStoreError.unknownZone
        }
        guard clientID == invitation.clientID else {
            throw ClientShareStoreError.notParticipant
        }
        zone.acceptedClientID = clientID
        zones[invitation.zoneID] = zone
        return ClientShareConnection(zoneID: invitation.zoneID, actor: .client,
                                     actorID: clientID, deviceID: deviceID)
    }

    public func writePlan(_ plan: Plan, using connection: ClientShareConnection,
                          sentAt: Date, editedAt: Date) async throws -> ClientShareChangeToken {
        var zone = try authorizedZone(for: connection, requires: .trainer)
        let current = zone.currentPlan
        let isNewer = current.map { editedAt > $0.lastEditedAt ||
            (editedAt == $0.lastEditedAt && connection.deviceID > $0.lastEditedBy) } ?? true
        if isNewer {
            let shared = ClientSharedPlan(
                plan: plan,
                revision: (current?.revision ?? 0) + 1,
                sentAt: current?.sentAt ?? sentAt,
                lastEditedAt: editedAt,
                lastEditedBy: connection.deviceID)
            zone.currentPlan = shared
            zone.events.append(.plan(shared))
            zones[connection.zoneID] = zone
        }
        return ClientShareChangeToken(sequence: zone.events.count)
    }

    public func currentPlan(using connection: ClientShareConnection) async throws -> ClientSharedPlan? {
        let zone = try authorizedZone(for: connection)
        return zone.currentPlan
    }

    public func append(_ result: ClientShareResult,
                       using connection: ClientShareConnection) async throws -> Bool {
        var zone = try authorizedZone(for: connection, requires: .client)
        if let existing = zone.results[result.id] {
            guard existing == result else { throw ClientShareStoreError.conflictingResultID }
            return false
        }
        zone.results[result.id] = result
        zone.events.append(.result(result))
        zones[connection.zoneID] = zone
        return true
    }

    public func changes(using connection: ClientShareConnection,
                        since token: ClientShareChangeToken? = nil) async throws -> ClientShareChangePage {
        let zone = try authorizedZone(for: connection)
        let start = token?.sequence ?? 0
        guard start >= 0, start <= zone.events.count else {
            throw ClientShareStoreError.invalidChangeToken
        }
        return ClientShareChangePage(
            changes: Array(zone.events.dropFirst(start)),
            nextToken: ClientShareChangeToken(sequence: zone.events.count))
    }

    private func authorizedZone(for connection: ClientShareConnection,
                                requires actor: ClientShareActor? = nil) throws -> Zone {
        guard let zone = zones[connection.zoneID] else {
            throw ClientShareStoreError.unknownZone
        }
        if let actor, connection.actor != actor {
            throw actor == .trainer ? ClientShareStoreError.trainerOnly : .clientOnly
        }
        switch connection.actor {
        case .trainer:
            guard connection.actorID == zone.invitation.trainerID else {
                throw ClientShareStoreError.notParticipant
            }
        case .client:
            guard zone.acceptedClientID == connection.actorID else {
                throw ClientShareStoreError.notParticipant
            }
        }
        return zone
    }
}
