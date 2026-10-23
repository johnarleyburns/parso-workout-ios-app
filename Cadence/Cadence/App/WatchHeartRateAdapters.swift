import Foundation
import WatchConnectivity
import CadenceFeatures

/// WatchConnectivity adapter for the phone-side receiver.
struct PhoneWCHeartRateTransport: WatchHeartRateTransport {
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    var isActivated: Bool { session?.activationState == .activated }
    var isReachable: Bool { session?.isReachable ?? false }
    func sendImmediate(_ message: WatchHRMessage) {
        session?.sendMessage(message.payload, replyHandler: nil, errorHandler: nil)
    }
    func transferUserInfo(_ message: WatchHRMessage) {
        _ = session?.transferUserInfo(message.payload)
    }
}

/// Receipt journal that survives process recreation, so duplicate user-info
/// and immediate copies stay idempotent.
struct WatchHeartRateReceiptDefaultsStore: WatchHeartRateReceiptStore {
    private func key(_ id: UUID) -> String { "watchHR.receipts.\(id.uuidString)" }
    func load(sessionID: UUID) -> WatchHRReceiptState? {
        UserDefaults.standard.data(forKey: key(sessionID)).flatMap { try? JSONDecoder().decode(WatchHRReceiptState.self, from: $0) }
    }
    func save(_ state: WatchHRReceiptState) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(state), forKey: key(state.phoneWorkoutSessionID))
    }
    func clear(sessionID: UUID) { UserDefaults.standard.removeObject(forKey: key(sessionID)) }
}

/// Finalization watermark that survives process recreation.
struct WatchHeartRateFinalizationDefaultsStore: WatchHeartRateFinalizationStore {
    private func key(_ id: UUID) -> String { "watchHR.finalization.\(id.uuidString)" }
    func load(sessionID: UUID) -> WatchHRFinalizationState? {
        UserDefaults.standard.data(forKey: key(sessionID)).flatMap { try? JSONDecoder().decode(WatchHRFinalizationState.self, from: $0) }
    }
    func save(_ state: WatchHRFinalizationState) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(state), forKey: key(state.sessionID))
    }
    func clear(sessionID: UUID) { UserDefaults.standard.removeObject(forKey: key(sessionID)) }
}

/// Retained phone workout → Watch request pairing (and finalization state),
/// so late batches route to the exact finished session. Bounded to the most
/// recent `limit` workouts.
struct WatchHeartRateRouteStore {
    struct Route: Codable, Equatable {
        var sessionID: UUID; var requestID: UUID; var captureEpoch: UUID; var finalizationRequested = false
    }
    static let key = "watchHR.routes.v1"
    static let limit = 8
    var routes: [Route] {
        get { UserDefaults.standard.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Route].self, from: $0) } ?? [] }
        nonmutating set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.suffix(Self.limit))), forKey: Self.key) }
    }
    func requestID(for sessionID: UUID) -> UUID? { routes.first { $0.sessionID == sessionID }?.requestID }
    func route(for sessionID: UUID) -> WatchHRRoute? {
        routes.first { $0.sessionID == sessionID }.map { WatchHRRoute(requestID: $0.requestID, captureEpoch: $0.captureEpoch) }
    }
    func sessionID(for requestID: UUID) -> UUID? { routes.last { $0.requestID == requestID }?.sessionID }
    func add(sessionID: UUID, requestID: UUID, captureEpoch: UUID) {
        var all = routes.filter { $0.sessionID != sessionID }
        all.append(Route(sessionID: sessionID, requestID: requestID, captureEpoch: captureEpoch))
        routes = all
    }
    func markFinalizationRequested(sessionID: UUID) {
        routes = routes.map { var r = $0; if r.sessionID == sessionID { r.finalizationRequested = true }; return r }
    }
    func remove(sessionID: UUID) { routes = routes.filter { $0.sessionID != sessionID } }
}
