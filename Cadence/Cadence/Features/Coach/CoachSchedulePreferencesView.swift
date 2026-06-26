import SwiftUI
import CadenceCore

struct CoachSchedulePreferencesView: View {
    @Environment(AppSettings.self) private var settingsObject

    var body: some View {
        @Bindable var settings = settingsObject
        Form {
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
                if let citation = CitationRegistry.citation(forId: "cdcActivityGuidelines2018") {
                    CitationLink(citation: citation, compact: true)
                }
            } header: {
                Text("Cardio")
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
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
                        HStack(spacing: 6) {
                            ForEach(Weekday.allCases, id: \.self) { wd in
                                Button {
                                    var newDays = days
                                    if newDays.contains(wd) { newDays.remove(wd) }
                                    else { newDays.insert(wd) }
                                    settings.coachSchedulePreferences = settings.coachSchedulePreferences.withRestPreference(.fixed(days: newDays))
                                } label: {
                                    Text(wd.displayName)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(days.contains(wd) ? Color.blue : Color(.systemGray5),
                                                    in: RoundedRectangle(cornerRadius: 8))
                                        .foregroundStyle(days.contains(wd) ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !days.isEmpty {
                            Text("Coach will not schedule workouts on selected days.")
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
        .navigationTitle("Coach preferences")
        .navigationBarTitleDisplayMode(.inline)
    }
}
