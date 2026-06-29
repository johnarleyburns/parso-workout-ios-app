import SwiftUI
import CadenceCore

struct CoachContextSettingsView: View {
    @Environment(AppSettings.self) private var settingsObject
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = settingsObject
        Form {
            Section {
                Picker("Training goal", selection: $settings.trainingGoal) {
                    ForEach(TrainingGoal.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Experience", selection: $settings.experienceLevel) {
                    ForEach(ExperienceLevel.allCases) { Text($0.displayName).tag($0) }
                }
                NavigationLink {
                    CoachSchedulePreferencesView()
                } label: {
                    Label("Schedule preferences", systemImage: "calendar.badge.clock")
                }
            } header: {
                Text("Coach")
            } footer: {
                Text("Your coach uses these to tailor its insights — goal sets the load/effort it looks for, experience scales the weekly volume targets. Coaching only, not medical advice.")
            }

            Section {
                Stepper("Daily step target: \(settings.coachSchedulePreferences.dailyStepTarget)",
                        value: Binding(get: {
                            settings.coachSchedulePreferences.dailyStepTarget
                        }, set: { v in
                            settings.coachSchedulePreferences = settings.coachSchedulePreferences.withDailyStepTarget(v)
                        }), in: 2_000...20_000, step: 500)
                if let citation = CitationRegistry.citation(forId: "saintMauriceSteps2020") {
                    CitationLink(citation: citation, compact: true)
                }
            } header: {
                Text("Steps")
            } footer: {
                Text("Evidence-informed default is 8,000/day. The floor of 4,000/day is fixed based on research. Adjust your personal target — the Coach uses this to assess your step health status.")
            }
        }
        .navigationTitle("Coach Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
