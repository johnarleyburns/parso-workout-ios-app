import SwiftUI
import CadenceCore
import CadenceFeatures

/// Settings entry point for the same current, on-device insight list shown from
/// Home. It computes lazily when opened, so Settings does not add coach work to
/// the Today launch path.
struct SettingsCoachInsightsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.cadenceModelContainer) private var container
    @State private var insights: [Insight] = []
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading coach insights…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if insights.isEmpty {
                ContentUnavailableView("No coach insights", systemImage: "lightbulb",
                                       description: Text("Complete a workout or readiness check-in to give Coach more context."))
            } else {
                CoachInsightsView(insights: insights)
            }
        }
        .navigationTitle("Coach Insights")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.coach.insights.list")
        .task {
            guard let container else {
                isLoading = false
                return
            }
            let snapshot = await HomeCoachModel.snapshotAsync(
                container: container,
                goal: settings.trainingGoal,
                experience: settings.experienceLevel,
                formula: settings.formula,
                schedule: settings.coachSchedulePreferences,
                profile: settings.coachPreferenceProfile,
                userAge: settings.userAge,
                constraintPolicy: settings.isPlanOverrideActive() ? .meetDeficits : .safe)
            guard !Task.isCancelled else { return }
            insights = snapshot.insights
            isLoading = false
        }
    }
}

/// Cardio inputs are explicit and editable. A user-entered maximum outranks an
/// age estimate, while resting HR is read on-device from HealthKit and shown with
/// its source so the app never silently invents a threshold.
struct CardioIntensitySettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var maximumHRText = ""
    @State private var restingHR: Double?

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Current profile") {
                LabeledContent("Resting HR", value: restingHR.map { "\(Int($0.rounded())) bpm" } ?? "Unavailable")
                LabeledContent("Maximum HR", value: currentMaximumText)
                Text("Heart-rate reserve is used when both values are valid. Otherwise the workout is shown as unclassified rather than receiving made-up intensity credit.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Maximum heart rate") {
                TextField("Optional bpm", text: $maximumHRText)
                    .keyboardType(.numberPad)
                    .onChange(of: maximumHRText) { _, value in
                        let number = Double(value.filter { $0.isNumber })
                        settings.cardioMaximumHROverride = number.flatMap { (100...240).contains($0) ? $0 : nil }
                    }
                if settings.cardioMaximumHROverride != nil {
                    Button("Use age estimate instead", role: .destructive) {
                        maximumHRText = ""
                        settings.cardioMaximumHROverride = nil
                    }
                }
                Text("Leave blank to use Tanaka’s age estimate when your age is set. A lab or field-tested value is preferable to an estimate.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("What the numbers mean") {
                NavigationLink {
                    CardioIntensityScienceView()
                } label: {
                    Label("Cardio science & credit", systemImage: "book.closed")
                }
                .accessibilityIdentifier("settings.cardioIntensity.science")
            }
        }
        .navigationTitle("Cardio Intensity")
        .task {
            maximumHRText = settings.cardioMaximumHROverride.map { String(Int($0)) } ?? ""
            let samples = await model.health.passiveReadinessSamples(days: 30)
            let values = samples.compactMap(\.restingHR).filter { $0 > 25 && $0 < 160 }.sorted()
            restingHR = values.isEmpty ? nil : values[values.count / 2]
        }
    }

    private var currentMaximumText: String {
        if let value = settings.cardioMaximumHROverride { return "\(Int(value.rounded())) bpm · entered" }
        if let age = settings.userAge { return "\(Int(HeartRateMaximum.tanaka(age: age).rounded())) bpm · age-estimated" }
        return "Unavailable"
    }
}

struct CardioIntensityScienceView: View {
    var body: some View {
        List {
            Section("Intensity") {
                Text("Cladiron classifies each timestamped heart-rate interval independently. Heart-rate reserve is (heart rate − resting heart rate) ÷ (maximum heart rate − resting heart rate), an estimate of relative effort rather than a whole-workout average.")
                Text("Below 40% reserve is below moderate; 40–<60% is moderate; 60% or more is vigorous for guideline credit. Below-moderate minutes receive zero credit, moderate minutes count once, and vigorous minutes count twice.")
            }
            Section("Separate measurements") {
                Text("Actual exercise minutes, guideline credit, training-zone time, and standardized MET-minutes are separate axes. MET-minutes describe population-level activity dose and do not replace guideline credit.")
            }
            Section("Sources") {
                ForEach(["swainLeutholtz1997HRR", "tanakaMaxHR2001", "piercy2018PhysicalActivityGuidelines", "compendium2024AdultPhysicalActivities"], id: \.self) { id in
                    if let citation = CitationRegistry.citation(forId: id) {
                        CitationLink(citation: citation, compact: true)
                    }
                }
            }
        }
        .navigationTitle("Cardio Science")
    }
}
