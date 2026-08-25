import SwiftUI
import CadenceCore
import CadenceFeatures

/// A read-only preview of a planned (future) day (issue 7): the day's planned
/// sessions with their rep prescription and a cited rationale. Deliberately has NO
/// Start button — starting a workout happens on Home when the day is today.
struct PlannedDayPreviewView: View {
    let day: WeeklyPlan.DayOutline
    let goal: TrainingGoal
    let desiredSetsPerExercise: Int
    @Environment(AppSettings.self) private var settings

    init(day: WeeklyPlan.DayOutline, goal: TrainingGoal, desiredSetsPerExercise: Int = 3) {
        self.day = day
        self.goal = goal
        self.desiredSetsPerExercise = desiredSetsPerExercise
    }

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
                                if let exercises = session.exercises,
                                   let editable = EditablePlan.from(coach: CoachSession(
                                    id: session.id,
                                    kind: session.kind,
                                    title: session.label,
                                    exercises: exercises,
                                    launchPayload: .strengthPlan("plannedDay"))) {
                                    NavigationLink {
                                        WorkoutPlanEditor(plan: editable, startInEditMode: true,
                                                          allowsStart: false, onStart: { _ in })
                                    } label: {
                                        Label("Edit workout plan", systemImage: "slider.horizontal.3")
                                    }
                                    .accessibilityIdentifier("plannedDay.editWorkout.\(session.id)")
                                }
                            } else {
                                Text(strengthPrescription)
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        if let cardioLine = cardioPrescription(session) {
                            Text(cardioLine)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        if let advice = session.adviceNote {
                            Label(advice, systemImage: "lightbulb")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityIdentifier("plannedDay.advice.\(session.id)")
                        }
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("plannedDay.session.\(session.id)")
                }
            } header: {
                Text(headerLabel)
            } footer: {
                Text(PlannedDayPreviewPresenter.footerText(for: day))
            }

            if day.sessions.contains(where: { $0.kind == .strength }) || hasPlannedCardio {
                Section("The science") {
                    CoachSourcesLink(citationIds: scienceCitationIds,
                                     identifier: "plan.day.science")
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
        if let loadKg = ex.loadKg, loadKg > 0 {
            line += " @ \(Format.weight(loadKg, unit: settings.unit, decimals: 0))"
        }
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

    /// Cited science for the planned day. A split (focused) strength day also cites
    /// the frequency, split-routine, and lift-specific recovery evidence that justify
    /// consecutive different-muscle strength days (HARD RULE — Fix 7). A planned
    /// cardio prescription cites the intensity-distribution and dose evidence.
    private var scienceCitationIds: [String] {
        var ids: [String] = []
        if day.sessions.contains(where: { $0.kind == .strength }) {
            ids.append("schoenfeld2021")
            let isSplit = day.sessions.contains { s in
                s.kind == .strength && (s.focus == .upper || s.focus == .lower)
            }
            if isSplit {
                ids += ["frequencyMeta", "ramosCampoSplit2024", "parejaBlancoRecovery2020"]
            }
        }
        if hasPlannedCardio {
            ids += ["seilerPolarized2010", "ekelundActivityMortality2016"]
        }
        return ids
    }

    private var hasPlannedCardio: Bool {
        day.sessions.contains { $0.cardioDurationMinutes != nil || $0.cardioZone != nil }
    }

    /// "~30 min · Zone 2 (Easy/aerobic base)" for a planned cardio session.
    private func cardioPrescription(_ session: PlannedSession) -> String? {
        var parts: [String] = []
        if let minutes = session.cardioDurationMinutes { parts.append("~\(minutes) min") }
        if let zone = session.cardioZone {
            parts.append("Zone \(zone) (\(CardioMath.zoneName(zone)))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The goal's descending rep ladder rendered compactly, e.g. "12-10-8 reps".
    private var strengthPrescription: String {
        PlannedDayPreviewPresenter.strengthPrescription(
            goal: goal,
            sets: desiredSetsPerExercise
        )
    }

    private var headerLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f.string(from: day.date)
    }
}
