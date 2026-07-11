import SwiftUI
import CadenceCore

/// The full ranked list of the Coach's read-only insights (strength-pivot P3),
/// reached from "See all insights" on the Coach card. Each row carries its own
/// why + citation expander (D3).
struct CoachInsightsView: View {
    let insights: [Insight]
    var onFixCustomExercises: (() -> Void)? = nil

    var body: some View {
        List {
            Section {
                ForEach(insights) { insight in
                    InsightContentView(insight: insight, onFixCustomExercises: onFixCustomExercises)
                        .padding(.vertical, 4)
                }
            } footer: {
                Text("Insights are computed on-device from your logged workouts and grounded in published training science. Coaching only — not medical advice.")
            }
        }
        .navigationTitle("Coach insights")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coach.insights.list")
    }
}
