import SwiftUI
import CadenceCore

/// Manual after-the-fact logging for **strength** workouts (feedback batch 7
/// follow-up to the cardio "Log Workout" flow). The user picks when the workout
/// happened (and, optionally, how long it took), then logs exercises and sets on the
/// normal `SessionView` — reused in `isManualLog` mode so the full keypad / PR /
/// partner / bodyweight machinery comes for free. The session is flagged `isLogged`
/// and lands in history with the "Logged" tag, exactly like logged cardio.

// MARK: - Entry (date + optional duration → SessionView)

/// Collects the date + optional duration for one logged strength workout, then
/// pushes the logging screen.
struct LogStrengthEntryView: View {
    /// Dismisses the whole Log-Workout sheet once the user is finished.
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var date = Date()
    @State private var minutes: Int?
    @State private var session: WorkoutSession?

    private let title = "Strength"

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
        let created = try? WorkoutRepository.createSession(
            title: "Workout", date: date, isLogged: true, in: context)
        guard let created else { return }
        // Optional duration drives the summary's workout length; 0 leaves it at the
        // start instant (summary shows no meaningful length).
        created.endedAt = date.addingTimeInterval(secs)
        try? context.save()
        Haptics.selection()
        session = created
    }
}
