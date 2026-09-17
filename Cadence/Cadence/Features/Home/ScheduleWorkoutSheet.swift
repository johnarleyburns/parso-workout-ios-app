import SwiftUI

struct ScheduleWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let onSave: (Date) async throws -> Void
    @State private var date = Date()
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(title.isEmpty ? "Workout" : title)
                        .font(.headline)
                        .accessibilityIdentifier("scheduleWorkout.title")
                    DatePicker("Date", selection: $date,
                               in: Calendar.current.startOfDay(for: Date())...,
                               displayedComponents: .date)
                        .accessibilityIdentifier("scheduleWorkout.date")
                } header: {
                    Text("Schedule this Workout")
                } footer: {
                    Text("This saves one copy of the workout for the selected day. You can reschedule or delete it from Home.")
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
                try await onSave(Calendar.current.startOfDay(for: date))
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
