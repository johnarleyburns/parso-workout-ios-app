import SwiftUI
import CadenceCore

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

                Stepper("Daily step target: \(settings.coachSchedulePreferences.dailyStepTarget)",
                        value: Binding(get: {
                            settings.coachSchedulePreferences.dailyStepTarget
                        }, set: { value in
                            settings.coachSchedulePreferences = settings.coachSchedulePreferences.withDailyStepTarget(value)
                        }), in: 2_000...20_000, step: 500)
                    .accessibilityIdentifier("settings.coach.stepTarget")

                if let citation = CitationRegistry.citation(forId: "saintMauriceSteps2020") {
                    CitationLink(citation: citation, compact: true)
                }
            } header: {
                Text("Coach Settings")
            } footer: {
                Text("Your coach uses goal and experience to tailor insights. Steps target is 8,000/day by default; the fixed health floor is 4,000/day.")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Strength days/week").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(settings.coachSchedulePreferences.strengthDaysPerWeek)").font(.subheadline.bold())
                    }
                    Picker("Strength days", selection: Binding(get: {
                        settings.coachSchedulePreferences.strengthDaysPerWeek
                    }, set: { v in
                        settings.coachSchedulePreferences = settings.coachSchedulePreferences.withStrengthDays(v)
                    })) {
                        ForEach(2...5, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if let citation = CitationRegistry.citation(forId: "frequencyMeta") {
                    CitationLink(citation: citation, compact: true)
                }
            } header: {
                Text("Strength")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cardio days/week").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("\(settings.coachSchedulePreferences.cardioDaysPerWeek)").font(.subheadline.bold())
                    }
                    Picker("Cardio days", selection: Binding(get: {
                        settings.coachSchedulePreferences.cardioDaysPerWeek
                    }, set: { v in
                        settings.coachSchedulePreferences = settings.coachSchedulePreferences.withCardioDays(v)
                    })) {
                        ForEach(0...6, id: \.self) { n in
                            Text("\(n)").tag(n)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if let citation = CitationRegistry.citation(forId: "ekelundActivityMortality2016") {
                    CitationLink(citation: citation, compact: true)
                }
            } header: {
                Text("Cardio")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Rest pattern").font(.subheadline.weight(.medium))
                    Picker("Rest", selection: Binding(get: {
                        if case .fixed = settings.coachSchedulePreferences.restPreference { return 0 }
                        return 1
                    }, set: { v in
                        var prefs = settings.coachSchedulePreferences
                        if v == 0 {
                            prefs = prefs.withRestPreference(.fixed(days: [.saturday, .sunday]))
                        } else {
                            prefs = prefs.withRestPreference(.rolling(everyNDays: 3))
                        }
                        settings.coachSchedulePreferences = prefs
                    })) {
                        Text("Fixed").tag(0)
                        Text("Rolling").tag(1)
                    }
                    .pickerStyle(.segmented)

                    if case .fixed(let days) = settings.coachSchedulePreferences.restPreference {
                        let fixedCount = max(1, min(2, days.count))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Fixed rest days per week").font(.caption.weight(.medium))
                            Picker("Count", selection: Binding(get: { fixedCount }, set: { newCount in
                                let clamped = max(1, min(2, newCount))
                                var newDays = days
                                while newDays.count > clamped {
                                    if let first = newDays.sorted(by: { $0.rawValue < $1.rawValue }).first {
                                        newDays.remove(first)
                                    }
                                }
                                settings.coachSchedulePreferences = settings.coachSchedulePreferences.withRestPreference(.fixed(days: newDays))
                            })) {
                                Text("1 day").tag(1)
                                Text("2 days").tag(2)
                            }
                            .pickerStyle(.segmented)
                        }

                        HStack(spacing: 6) {
                            ForEach(Weekday.allCases, id: \.self) { wd in
                                let isSelected = days.contains(wd)
                                let isFull = days.count >= fixedCount
                                Button {
                                    var newDays = days
                                    if isSelected {
                                        newDays.remove(wd)
                                    } else if isFull {
                                        if let oldest = newDays.sorted(by: { $0.rawValue < $1.rawValue }).first {
                                            newDays.remove(oldest)
                                        }
                                        newDays.insert(wd)
                                    } else {
                                        newDays.insert(wd)
                                    }
                                    settings.coachSchedulePreferences = settings.coachSchedulePreferences.withRestPreference(.fixed(days: newDays))
                                } label: {
                                    Text(wd.displayName)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(isSelected ? Color.blue : Color(.systemGray5),
                                                    in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(isSelected ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(wd.displayName)
                                .accessibilityAddTraits(isSelected ? .isSelected : [])
                            }
                        }

                        if !days.isEmpty {
                            Text("Coach will not schedule workouts on your fixed rest days.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if case .rolling(let everyN) = settings.coachSchedulePreferences.restPreference {
                        Stepper("Every \(everyN) days", value: Binding(get: { everyN }, set: { n in
                            settings.coachSchedulePreferences = settings.coachSchedulePreferences.withRestPreference(.rolling(everyNDays: max(2, n)))
                        }), in: 2...7)
                    }
                }
                if let recoveryCitation = CitationRegistry.citation(forId: "sawMonitoring2016") {
                    CitationLink(citation: recoveryCitation, compact: true)
                }
            } header: {
                Text("Rest")
            } footer: {
                Text("Fixed rest days are days the Coach will not schedule workouts. You can still start one manually on those days if you want.")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Two-a-days").font(.subheadline.weight(.medium))
                        Text("Allow strength + cardio on the same day").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: {
                        settings.coachSchedulePreferences.allowsTwoADays
                    }, set: { v in
                        settings.coachSchedulePreferences = settings.coachSchedulePreferences.withTwoADays(v)
                    }))
                }
                if settings.coachSchedulePreferences.allowsTwoADays,
                   let concurrentCitation = CitationRegistry.citation(forId: "murlasitsConcurrentSequence2018") {
                    CitationLink(citation: concurrentCitation, compact: true)
                }
            }

            if settings.coachSchedulePreferences.allowsTwoADays {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Cardio timing (same day)").font(.subheadline.weight(.medium))
                        Picker("Timing", selection: Binding(get: {
                            settings.coachSchedulePreferences.sameDayCardioTiming
                        }, set: { v in
                            settings.coachSchedulePreferences = settings.coachSchedulePreferences.withSameDayCardioTiming(v)
                        })) {
                            ForEach(SameDayCardioTiming.allCases, id: \.self) { t in
                                switch t {
                                case .afterStrength: Text("After lifting").tag(t)
                                case .separateLater: Text("Separate later").tag(t)
                                }
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    if let schumann = CitationRegistry.citation(forId: "schumannConcurrent2022") {
                        CitationLink(citation: schumann, compact: true)
                    }
                } header: {
                    Text("Cardio Timing")
                }
            }
        }
        .navigationTitle("Coach & Plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}
