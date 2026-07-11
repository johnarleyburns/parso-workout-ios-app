import SwiftUI
import CadenceCore

/// A read-only preview of a planned (future) day (issue 7): the day's planned
/// sessions with their rep prescription and a cited rationale. Deliberately has NO
/// Start button — starting a workout happens on Home when the day is today.
struct PlannedDayPreviewView: View {
    let day: WeeklyPlan.DayOutline
    let goal: TrainingGoal

    var body: some View {
        List {
            Section {
                ForEach(day.sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(session.isHard ? Color.green : session.kind == .recovery || session.kind == .rest ? Color.gray.opacity(0.3) : Color.teal)
                                .frame(width: 8, height: 8)
                            Text(session.label).font(.headline)
                        }
                        if session.kind == .strength {
                            Text(strengthPrescription)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let note = session.timingNote {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(headerLabel)
            } footer: {
                Text("This is a planned day. Start it from the Workout tab when it's today.")
            }

            if day.sessions.contains(where: { $0.kind == .strength }) {
                Section("The science") {
                    if let citation = CitationRegistry.citation(forId: "schoenfeld2021") {
                        CitationLink(citation: citation)
                    }
                }
            }
        }
        .navigationTitle(headerLabel)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("plannedDay.preview")
    }

    /// The goal's descending rep ladder rendered compactly, e.g. "12-10-8 reps".
    private var strengthPrescription: String {
        let ladder = RepLadder.ladder(for: goal, sets: 3)
        let reps = ladder.map(String.init).joined(separator: "-")
        return "3 sets · \(reps) reps · ~\(goal.targetRIR) RIR"
    }

    private var headerLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: day.date)
    }
}
