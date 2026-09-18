import SwiftUI

struct ScheduleWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (Date) async throws -> Void
    @State private var date: Date
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(title: String, initialDate: Date = ScheduleWorkoutSheet.defaultDate(),
         onSave: @escaping (Date) async throws -> Void) {
        self.title = title
        self.onSave = onSave
        self._date = State(initialValue: initialDate)
    }

    private static func defaultDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let start = calendar.date(bySetting: .second, value: 0, of: now) ?? now
        let minute = calendar.component(.minute, from: start)
        let roundedMinute = ((minute / 15) + 1) * 15
        if roundedMinute >= 60 {
            return calendar.date(byAdding: .hour, value: 1, to: calendar.date(bySetting: .minute, value: 0, of: start) ?? start) ?? start
        }
        return calendar.date(bySetting: .minute, value: roundedMinute, of: start) ?? start
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title.isEmpty ? "Workout" : title)
                        .font(.headline)
                        .accessibilityIdentifier("scheduleWorkout.title")
                    DatePicker("Date", selection: $date,
                               in: Calendar.current.startOfDay(for: Date())...,
                               displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("scheduleWorkout.date")
                } header: {
                    Text("Schedule this Workout")
                } footer: {
                    Text("This saves one copy of the workout for the selected local date and time. You can reschedule or delete it from Home.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Schedule Workout")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: date) { oldDate, newDate in
                let calendar = Calendar.current
                guard !calendar.isDate(oldDate, inSameDayAs: newDate) else { return }
                let today = calendar.startOfDay(for: Date())
                let selectedDay = calendar.startOfDay(for: newDate)
                if selectedDay > today {
                    // A future-day choice should not inherit an accidental
                    // late-night time from the current day. The user can still
                    // edit the time immediately in the same DatePicker.
                    date = calendar.date(bySettingHour: 9, minute: 0, second: 0,
                                         of: selectedDay) ?? newDate
                } else {
                    date = Self.defaultDate()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(isSaving)
                        .accessibilityIdentifier("scheduleWorkout.save")
                }
            }
            .overlay {
                if isSaving {
                    ProgressView("Saving workout…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await onSave(date)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
