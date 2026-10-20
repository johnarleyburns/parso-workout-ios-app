import SwiftUI
import CadenceCore
import CadenceFeatures

/// "Workout sent from your phone": every workout the user sent from the iPhone, each startable
/// here. A workout leaves this list the moment it is started.
struct WatchSentWorkoutsSection: View {
    let onStartCardio: (WatchSync.TodayPlan.Session) -> Void
    private let store = WatchSentWorkoutStore.shared
    @State private var startingStrength: WatchSync.TodayPlan.Session?

    var body: some View {
        Group {
            if !store.pending.isEmpty {
                Text("Workout sent from your phone")
                    .font(.caption2.weight(.bold)).foregroundStyle(WatchTone.accent)
                    .listRowBackground(Color.clear)
                ForEach(store.pending) { session in
                    Button { start(session) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(session)).font(.footnote.weight(.semibold))
                            Text(detail(session)).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    .accessibilityIdentifier("watch.sentWorkout")
                }
            }
        }
        .navigationDestination(isPresented: Binding(get: { startingStrength != nil },
                                                    set: { if !$0 { startingStrength = nil } })) {
            if let session = startingStrength {
                WatchStrengthView(title: title(session),
                                  plannedExerciseNames: session.exerciseNames,
                                  repLadder: session.repLadder,
                                  planPayload: session.planPayload)
            }
        }
    }

    private func title(_ session: WatchSync.TodayPlan.Session) -> String {
        session.label.isEmpty ? (session.isStrength ? String(localized: "Strength") : String(localized: "Cardio")) : session.label
    }

    private func detail(_ session: WatchSync.TodayPlan.Session) -> String {
        if session.isStrength { return session.exerciseNames.prefix(3).joined(separator: " · ") }
        return [session.durationMinutes.map { String(localized: "\($0) min") },
                session.zone.map { String(localized: "Zone \($0)") }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func start(_ session: WatchSync.TodayPlan.Session) {
        store.markStarted(session.id)
        if session.isStrength { startingStrength = session } else { onStartCardio(session) }
    }
}
