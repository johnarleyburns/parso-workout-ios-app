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
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(session.isHard ? Color.green : session.kind == .recovery || session.kind == .rest ? Color.gray.opacity(0.3) : Color.teal)
                                .frame(width: 8, height: 8)
                            Text(session.label).font(.headline)
                        }
                        if session.kind == .strength {
                            if let exercises = session.exercises, !exercises.isEmpty {
                                // Full concrete prescription (issue 6): one row per
                                // movement with sets × rep-ladder + RIR.
                                ForEach(Array(exercises.enumerated()), id: \.offset) { _, ex in
                                    exerciseRow(ex)
                                }
                            } else {
                                Text(strengthPrescription)
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if let note = session.timingNote {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("plannedDay.session.\(session.id)")
                }
            } header: {
                Text(headerLabel)
            } footer: {
                Text("This is a planned day. Start it from the Workout tab when it's today.")
            }

            if day.sessions.contains(where: { $0.kind == .strength }) {
                Section("The science") {
                    ForEach(scienceCitationIds, id: \.self) { id in
                        if let citation = CitationRegistry.citation(forId: id) {
                            CitationLink(citation: citation)
                        }
                    }
                }
            }
        }
        .navigationTitle(headerLabel)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("plannedDay.preview")
    }

    /// One exercise row: "Bench Press · 3×12-10-8 · ~1 RIR".
    private func exerciseRow(_ ex: CoachSession.RecommendedExercise) -> some View {
        let sets = ex.sets ?? ex.repLadder?.count ?? 3
        let repsText: String
        if let ladder = ex.repLadder, !ladder.isEmpty {
            repsText = ladder.map(String.init).joined(separator: "-")
        } else if let low = ex.repsLow, let high = ex.repsHigh {
            repsText = low == high ? "\(low)" : "\(low)-\(high)"
        } else {
            repsText = "—"
        }
        var line = "\(sets)×\(repsText)"
        if let rir = ex.rir { line += " · ~\(rir) RIR" }
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(ex.name).font(.subheadline)
            Spacer()
            Text(line)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Cited science for the planned strength day. A split (focused) day also cites
    /// the frequency, split-routine, and lift-specific recovery evidence that justify
    /// consecutive different-muscle strength days (HARD RULE — Fix 7).
    private var scienceCitationIds: [String] {
        var ids = ["schoenfeld2021"]
        let isSplit = day.sessions.contains { s in
            s.kind == .strength && (s.focus == .upper || s.focus == .lower)
        }
        if isSplit {
            ids += ["frequencyMeta", "ramosCampoSplit2024", "parejaBlancoRecovery2020"]
        }
        return ids
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
