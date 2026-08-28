import Foundation
import WatchConnectivity
import CadenceCore

extension WatchWorkoutManager {
    private static let pendingCardioKey = "watch.pendingCardioCompletions"

    static func loadPendingCardioCompletions() -> [WatchCardioCompletion] {
        guard let data = UserDefaults.standard.data(forKey: pendingCardioKey),
              let values = try? JSONDecoder().decode([WatchCardioCompletion].self, from: data) else { return [] }
        return values
    }

    func enqueueCardioCompletion(type: CardioType, title: String? = nil,
                                 summary: SavedWorkoutSummary) {
        let completion = WatchCardioCompletion(
            type: type, title: title, start: sessionStart ?? Date().addingTimeInterval(-summary.duration),
            end: Date(), distanceMeters: summary.distanceMeters,
            avgHeartRate: summary.avgHR, maxHeartRate: summary.maxHR,
            gpsEnabled: isOutdoorSession)
        guard !pendingCardioCompletions.contains(where: { $0.id == completion.id }) else { return }
        pendingCardioCompletions.append(completion)
        persistPendingCardioCompletions()
        flushPendingCardioCompletions()
    }

    private func persistPendingCardioCompletions() {
        if let data = try? JSONEncoder().encode(pendingCardioCompletions) {
            UserDefaults.standard.set(data, forKey: Self.pendingCardioKey)
        }
    }

    func flushPendingCardioCompletions() {
        guard let session = wcSession, session.activationState == .activated else { return }
        for completion in pendingCardioCompletions {
            guard let data = try? completion.encoded() else { continue }
            session.transferUserInfo(["action": "cardio_completion", "payload": data])
        }
        if !pendingCardioCompletions.isEmpty { phoneSyncState = .syncing(Date()) }
    }

    func acknowledgeCardioCompletion(_ id: UUID) {
        pendingCardioCompletions.removeAll { $0.id == id }
        persistPendingCardioCompletions()
        lastPhoneSyncError = nil
        lastPhoneSyncAt = Date()
        UserDefaults.standard.set(lastPhoneSyncAt, forKey: "watch.lastPhoneSyncAt")
        phoneSyncState = .synced(lastPhoneSyncAt!)
    }
}
