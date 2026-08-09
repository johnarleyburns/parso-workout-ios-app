import Foundation
@preconcurrency import UserNotifications

/// Schedules the single, quiet trial value-receipt reminder — one local
/// notification 3 days before the trial ends, summarizing that the Coach has been
/// adapting the plan. No other trial nagging (monetization plan §4.4).
///
/// Uses *provisional* authorization so it's delivered quietly to Notification
/// Center without a permission prompt — consistent with the no-nag, privacy-first
/// stance. All local; nothing leaves the device.
enum TrialNotifier {
    static let reminderID = "cladiron.pro.trialEndingReminder"

    static func scheduleReminder(trialEnd: Date) {
        let fireDate = trialEnd.addingTimeInterval(-3 * 24 * 60 * 60)
        guard fireDate > Date() else { return }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.provisional, .alert, .sound]) { granted, _ in
            guard granted else { return }

            let content = UNMutableNotificationContent()
            content.title = "Your Coach trial ends in 3 days"
            content.body = "See what the Coach adjusted for you this week — keep it if it's working for you."
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger)

            center.removePendingNotificationRequests(withIdentifiers: [reminderID])
            center.add(request)
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderID])
    }
}
