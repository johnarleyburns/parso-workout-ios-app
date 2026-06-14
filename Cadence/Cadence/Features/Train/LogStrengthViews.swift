import SwiftUI
import CadenceCore

/// Manual after-the-fact logging for **strength** and **CrossFit** (feedback batch 7
/// follow-up to the cardio "Log Workout" flow). The user picks when the workout
/// happened (and, optionally, how long it took), then logs exercises and sets on the
/// normal `SessionView` — reused in `isManualLog` mode so the full keypad / PR /
/// partner / bodyweight machinery comes for free. The session is flagged `isLogged`
/// and lands in history with the "Logged" tag, exactly like logged cardio.

// MARK: - Entry (date + optional duration → SessionView)

/// Collects the date + optional duration for one logged strength/CrossFit workout,
/// then pushes the logging screen. A non-nil `plan` pre-loads a CrossFit benchmark's
/// movements; `isCrossFit` titles an ad-hoc session "CrossFit" so history shows the
/// functional glyph.
struct LogStrengthEntryView: View {
    var plan: WorkoutPlan? = nil
    var isCrossFit: Bool = false
    /// Dismisses the whole Log-Workout sheet once the user is finished.
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var date = Date()
    @State private var minutes: Int?
    @State private var session: WorkoutSession?

    private var title: String {
        if let plan { return plan.displayTitle }
        return isCrossFit ? "CrossFit" : "Strength"
    }

    var body: some View {
        Form {
            Section {
                DatePicker("When", selection: $date)
                    .accessibilityIdentifier("log.date")
            }
            Section("Duration (optional)") {
                HStack {
                    Text("Minutes"); Spacer()
                    TextField("—", value: $minutes, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit().font(.headline)
                        .frame(maxWidth: 70)
                        .accessibilityIdentifier("log.minutes")
                }
            }
            Section {
                Button { start() } label: {
                    Label("Add Exercises", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .accessibilityIdentifier("log.addExercises")
            } footer: {
                Text("Log your sets next; it saves to history tagged \u{201C}Logged.\u{201D}")
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Log \(title)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $session) { s in
            SessionView(session: s, isManualLog: true, onDone: onDone)
        }
    }

    private func start() {
        let secs = Double(max(0, minutes ?? 0)) * 60
        let created: WorkoutSession?
        if let plan {
            created = try? WorkoutRepository.startSession(from: plan, date: date,
                                                          isLogged: true, in: context)
        } else {
            created = try? WorkoutRepository.createSession(
                title: isCrossFit ? "CrossFit" : "Workout", date: date,
                isLogged: true, in: context)
        }
        guard let created else { return }
        // Optional duration drives the summary's workout length; 0 leaves it at the
        // start instant (summary shows no meaningful length).
        created.endedAt = date.addingTimeInterval(secs)
        try? context.save()
        Haptics.selection()
        session = created
    }
}

// MARK: - CrossFit chooser for the log flow

/// Benchmark picker for logging a CrossFit workout: reuses `CrossFitPickerView`
/// (the live Start screen) and adds a "Custom CrossFit" escape hatch. Both paths
/// route to `LogStrengthEntryView`.
struct LogCrossFitPicker: View {
    let onDone: () -> Void

    @State private var target: LogStrengthTarget?

    var body: some View {
        CrossFitPickerView(
            onStart: { plan in target = LogStrengthTarget(plan: plan, isCrossFit: true) },
            onCustom: { target = LogStrengthTarget(plan: nil, isCrossFit: true) })
        .navigationDestination(item: $target) { t in
            LogStrengthEntryView(plan: t.plan, isCrossFit: t.isCrossFit, onDone: onDone)
        }
    }
}

/// A chosen logging target (benchmark plan or ad-hoc), driving a navigation push.
struct LogStrengthTarget: Hashable {
    let plan: WorkoutPlan?
    let isCrossFit: Bool

    static func == (lhs: LogStrengthTarget, rhs: LogStrengthTarget) -> Bool {
        lhs.plan?.id == rhs.plan?.id && lhs.isCrossFit == rhs.isCrossFit
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(plan?.id); hasher.combine(isCrossFit)
    }
}
