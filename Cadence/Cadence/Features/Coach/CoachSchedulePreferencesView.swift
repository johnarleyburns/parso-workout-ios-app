import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures

struct CoachSchedulePreferencesView: View {
    @Environment(AppSettings.self) private var settingsObject

    var body: some View {
        @Bindable var settings = settingsObject
        Form {
            Section {
                Picker("Training goal", selection: $settings.trainingGoal) {
                    ForEach(TrainingGoal.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.coach.goal")

                Picker("Experience", selection: $settings.experienceLevel) {
                    ForEach(ExperienceLevel.allCases) { Text($0.displayName).tag($0) }
                }
                .accessibilityIdentifier("settings.coach.experience")

                Stepper(value: Binding(get: { settings.userAge ?? 40 },
                                       set: { settings.userAge = $0 }),
                        in: 13...100) {
                    HStack {
                        Text("Age")
                        Spacer()
                        Text(settings.userAge.map(String.init) ?? "not set")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .accessibilityIdentifier("settings.coach.age")

            } header: {
                Text("Coach Settings")
            } footer: {
                Text("Your coach uses goal and experience to tailor insights.")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Working sets/exercise").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(settings.coachSchedulePreferences.desiredSetsPerExercise)").font(.subheadline.bold())
                    }
                    Picker("Working sets/exercise", selection: Binding(get: {
                        settings.coachSchedulePreferences.desiredSetsPerExercise
                    }, set: { v in
                        settings.coachSchedulePreferences = settings.coachSchedulePreferences.withDesiredSetsPerExercise(v)
                    })) {
                        Text("3").tag(3)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.coach.desiredSets")
                }
                if let citation = CitationRegistry.citation(forId: "frequencyMeta") {
                    CitationLink(citation: citation, compact: true)
                }
            } header: {
                Text("Strength")
            }

            Section {
                Text("Cardio is tracked as weekly minutes, not days per week.")
                    .font(.footnote).foregroundStyle(.secondary)
                CoachSourcesLink(citationIds: ["leeWeekendWarrior2022", "ekelundActivityMortality2016"])
            } header: {
                Text("Cardio")
            }


        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
    }
}
