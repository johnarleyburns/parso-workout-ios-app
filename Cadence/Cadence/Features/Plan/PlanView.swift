import SwiftUI

/// Placeholder for the **Plan** tab (strength-pivot P3 ships the tab; content lands
/// in a later phase). Future home for goals, a training calendar, and favorited
/// exercises.
struct PlanView: View {
    var body: some View {
        NavigationStack {
            ComingSoonPlaceholder(
                systemImage: "calendar",
                title: "Plan",
                message: "Your goals, training calendar, and favorite exercises will live here.",
                identifier: "plan.placeholder")
            .navigationTitle("Plan")
        }
    }
}

/// Shared "coming soon" scaffold for the not-yet-built tabs.
struct ComingSoonPlaceholder: View {
    let systemImage: String
    let title: String
    let message: String
    let identifier: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
        .accessibilityIdentifier(identifier)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(message)")
    }
}
