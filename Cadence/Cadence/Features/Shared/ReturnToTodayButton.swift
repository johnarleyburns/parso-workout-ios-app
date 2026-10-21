import SwiftUI
import CadenceFeatures

/// Explicit, accessible minimize control shown only while a cardio workout is
/// paused. Dismissing minimizes — it never ends or discards the workout.
struct ReturnToTodayButton: View {
    let idPrefix: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(CardioPresentation.returnToTodayLabel, systemImage: "chevron.down.circle")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("\(idPrefix).returnToToday")
        .accessibilityLabel(CardioPresentation.returnToTodayLabel)
        .accessibilityHint(CardioPresentation.minimizeHint)
    }
}

/// Announces the paused state and the Return to Today action to VoiceOver.
func announceCardioPaused(_ paused: Bool) {
    guard paused else { return }
    AccessibilityNotification.Announcement(CardioPresentation.pausedAnnouncement).post()
}
