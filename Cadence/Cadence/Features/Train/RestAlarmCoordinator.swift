import Foundation

#if canImport(AlarmKit)
import AlarmKit
import AppIntents
import SwiftUI
#endif

/// App-target adapter for the pure `RestAlarmPlanner`. Keeping AlarmKit here
/// means the package remains headless and the same cancellation policy can be
/// used by iPhone and Watch callers.
@MainActor
final class RestAlarmCoordinator {
    static let shared = RestAlarmCoordinator()

    #if canImport(AlarmKit)
    private struct Metadata: AlarmMetadata {
        let title: String
    }

    private var alarmID: UUID?

    func schedule(endsAt: Date) {
        let duration = max(1, endsAt.timeIntervalSinceNow)
        let id = alarmID ?? UUID()
        alarmID = id
        Task { @MainActor in
            do {
                guard try await AlarmManager.shared.requestAuthorization() == .authorized else { return }
                let presentation = AlarmPresentation(
                    alert: .init(title: "Rest complete"),
                    countdown: .init(title: "Rest"))
                let attributes = AlarmAttributes(
                    presentation: presentation,
                    metadata: Metadata(title: "Rest"),
                    tintColor: .green)
                _ = try await AlarmManager.shared.schedule(
                    id: id,
                    configuration: .timer(duration: duration, attributes: attributes))
            } catch {
                // In-app timer and haptic feedback remain the fallback when
                // AlarmKit is unavailable, denied, or temporarily full.
            }
        }
    }

    func cancel() {
        guard let id = alarmID else { return }
        alarmID = nil
        try? AlarmManager.shared.cancel(id: id)
    }
    #else
    func schedule(endsAt: Date) {}
    func cancel() {}
    #endif
}
