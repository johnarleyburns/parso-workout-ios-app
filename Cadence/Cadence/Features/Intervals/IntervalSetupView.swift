import SwiftUI
import CadenceCore
import CadenceFeatures

struct IntervalSetupView: View {
    let type: WorkoutType
    let onSelect: (IntervalPlan) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @State private var selectedID: String = ""
    @State private var infoPreset: Preset?

    // Custom builder params.
    @State private var rounds: Int
    @State private var workSec: Int
    @State private var restSec: Int
    @State private var warmupMin = 5
    @State private var cooldownMin = 5

    // Settings from lastIntervalSettings
    @State private var preWorkoutCountdown: Int
    @State private var intervalColorBlind: Bool
    @State private var spokenCues: Bool
    @State private var useHR: Bool

    init(type: WorkoutType, onSelect: @escaping (IntervalPlan) -> Void) {
        self.type = type
        self.onSelect = onSelect
        if type == .boxing {
            _rounds = State(initialValue: 8)
            _workSec = State(initialValue: 180)
            _restSec = State(initialValue: 60)
        } else {
            _rounds = State(initialValue: 8)
            _workSec = State(initialValue: 30)
            _restSec = State(initialValue: 30)
        }
        let ws = WorkoutSettings.default
        _preWorkoutCountdown = State(initialValue: ws.preWorkoutCountdown)
        _intervalColorBlind = State(initialValue: ws.intervalColorBlind)
        _spokenCues = State(initialValue: ws.spokenCues)
        _useHR = State(initialValue: ws.useHRMonitoring)
    }

    private struct Preset: Identifiable { let id: String; let title: String; let subtitle: String; let description: String; let citationIds: [String]; let make: () -> IntervalPlan }

    private var presets: [Preset] {
        if type == .boxing { return [] }
        return [
            Preset(id: "tabata", title: "Tabata", subtitle: "8 × 20s / 10s",
                   description: "Developed by Prof. Izumi Tabata for Olympic speed skaters. 20 s of all-out work alternates with 10 s of rest across 8 rounds — just 4 minutes of high-intensity intervals that improve both anaerobic capacity and VO₂max.",
                   citationIds: ["tabata1996"]) { .tabata() },
            Preset(id: "norwegian", title: "Norwegian 4×4", subtitle: "4 × 4min / 3min",
                   description: "Four 4-minute work intervals at ~90–95 % HRmax separated by 3-minute active recovery periods. This protocol is one of the best-researched methods for improving VO₂max in healthy adults.",
                   citationIds: ["hiitVo2max"]) { .norwegian4x4() },
            Preset(id: "gibala", title: "Gibala", subtitle: "8 × 60s / 60s · ~20 min",
                   description: "Named after Martin Gibala's sprint-interval research. 60 s of hard work alternates with 60 s of recovery for 8 rounds, totalling ~20 min. Produces metabolic adaptations comparable to much longer moderate-intensity training.",
                   citationIds: ["gibala2006"]) { .gibala() },
            Preset(id: "sit", title: "SIT (Wingate)", subtitle: "4 × 30s all-out / 4 min",
                   description: "Four 30 s all-out Wingate sprints with 4-minute passive recovery per round. Sprint-interval training (SIT) is a potent but demanding protocol — best reserved for experienced exercisers comfortable with maximal effort.",
                   citationIds: ["wingateTest", "slothSIT2013"]) { .sit() },
            Preset(id: "ten", title: "10-20-30", subtitle: "5 × (30/20/10), 3 sets",
                   description: "30 s low / 20 s moderate / 10 s sprint — 5 cycles per set across 3 sets with recovery between. This stepping pattern reduced training volume by ~50 % while improving 5 km race performance and cardiovascular health markers.",
                   citationIds: ["gunnarsson1020302012"]) { .tenTwentyThirty() },
            Preset(id: "rehit", title: "REHIT", subtitle: "2 × 20s sprint / 3 min",
                   description: "Reduced-Exertion HIIT — just 2 all-out 20 s sprints in a single 10-minute session. One of the lowest time-commitment protocols shown to improve insulin sensitivity and VO₂max in previously inactive adults.",
                   citationIds: ["metcalfeREHIT2012"]) { .rehit() },
        ]
    }

    private func customPlan() -> IntervalPlan {
        .custom(name: type == .boxing ? "Boxing" : "HIIT",
                warmup: TimeInterval(warmupMin * 60), rounds: rounds,
                work: TimeInterval(workSec), rest: TimeInterval(restSec),
                cooldown: TimeInterval(cooldownMin * 60))
    }
    private func selectedPlan() -> IntervalPlan {
        if type == .boxing { return customPlan() }
        if selectedID == "custom" { return customPlan() }
        return (presets.first { $0.id == selectedID } ?? presets[0]).make()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if type == .hiit {
                        Section("Presets") {
                            ForEach(presets) { p in
                                row(p.id, p.title, p.subtitle)
                            }
                        }
                    }
                    Section(sectionTitle) {
                        Stepper("Warm-up: \(warmupMin) min", value: $warmupMin, in: 0...20)
                        Stepper("Rounds: \(rounds)", value: $rounds, in: 1...30)
                            .accessibilityIdentifier("interval.custom.rounds")
                        Stepper("Fighting: \(formatMinSec(workSec))", value: $workSec, in: 10...600, step: stepSize)
                        Stepper("Rest: \(restSec) sec", value: $restSec, in: 0...300, step: stepSize)
                        Stepper("Cool-down: \(cooldownMin) min", value: $cooldownMin, in: 0...20)
                        if type == .hiit {
                            rowLabel("custom", "Custom", "your settings")
                        }
                    }

                    Section {
                        Stepper("Get-ready countdown: \(preWorkoutCountdown > 0 ? "\(preWorkoutCountdown)s" : "off")",
                                value: $preWorkoutCountdown, in: 0...60, step: 5)
                            .accessibilityIdentifier("interval.countdown")
                    }

                    Section {
                        Toggle("Color-blind palette", isOn: $intervalColorBlind)
                            .accessibilityIdentifier("interval.colorBlind")
                        Toggle("Spoken announcements", isOn: $spokenCues)
                            .accessibilityIdentifier("interval.spokenCues")
                    } header: {
                        Text("Display & Audio")
                    }

                    Section {
                        Toggle("Use HR monitoring", isOn: $useHR)
                            .accessibilityIdentifier("interval.hrToggle")
                    } footer: {
                        Text("Connect a Bluetooth chest strap before the workout starts.")
                    }
                }

                Button {
                    saveAndStart()
                } label: {
                    Label("START", systemImage: "play.fill")
                        .font(.title3.weight(.bold))
                        .frame(maxWidth: .infinity)
                }
                .cadenceGlassButton(prominent: true, tint: .green)
                .padding()
                .accessibilityIdentifier("interval.start")
            }
            .navigationTitle(type.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $infoPreset) { preset in
                presetInfoView(preset)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("interval.cancel")
                }
            }
            .onAppear {
                loadSettings()
                if selectedID.isEmpty, !presets.isEmpty { selectedID = presets[0].id }
            }
        }
    }

    private func loadSettings() {
        let ws = settings.lastIntervalSettings
        preWorkoutCountdown = ws.preWorkoutCountdown
        intervalColorBlind = ws.intervalColorBlind
        spokenCues = ws.spokenCues
        useHR = ws.useHRMonitoring
    }

    private func saveAndStart() {
        let ws = WorkoutSettings(
            restSeconds: settings.lastIntervalSettings.restSeconds,
            autoStartRest: settings.lastIntervalSettings.autoStartRest,
            preWorkoutCountdown: preWorkoutCountdown,
            autoEndOnIdle: settings.lastIntervalSettings.autoEndOnIdle,
            idleTimeoutMinutes: settings.lastIntervalSettings.idleTimeoutMinutes,
            plateRounding: settings.lastIntervalSettings.plateRounding,
            gpsHighAccuracy: settings.lastIntervalSettings.gpsHighAccuracy,
            autoPause: settings.lastIntervalSettings.autoPause,
            intervalColorBlind: intervalColorBlind,
            spokenCues: spokenCues,
            weeklyCardioMinutesGoal: settings.lastIntervalSettings.weeklyCardioMinutesGoal,
            warmupMinutes: warmupMin,
            cooldownMinutes: cooldownMin,
            useHRMonitoring: useHR
        )
        settings.lastIntervalSettings = ws
        settings.preWorkoutCountdown = preWorkoutCountdown
        settings.intervalColorBlind = intervalColorBlind
        settings.spokenCues = spokenCues
        settings.useHRMonitoring = useHR

        onSelect(selectedPlan())
        dismiss()
    }

    private var sectionTitle: String { type == .boxing ? "Details" : "Custom" }
    private var stepSize: Int { type == .boxing ? 30 : 5 }

    private func formatMinSec(_ totalSec: Int) -> String {
        "\(totalSec / 60):\(String(format: "%02d", totalSec % 60))"
    }

    private func row(_ id: String, _ title: String, _ subtitle: String) -> some View {
        Button { selectedID = id } label: { rowContent(id, title, subtitle) }
            .foregroundStyle(.primary)
            .accessibilityIdentifier("interval.preset.\(id)")
    }

    private func rowContent(_ id: String, _ title: String, _ subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let preset = presets.first(where: { $0.id == id }) {
                Button {
                    infoPreset = preset
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About \(preset.title)")
            }
            Image(systemName: selectedID == id ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selectedID == id ? Color.accentColor : Color.secondary)
        }
    }

    @ViewBuilder
    private func presetInfoView(_ preset: Preset) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(preset.title)
                        .font(.largeTitle.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(preset.subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text(preset.description)
                        .font(.body)

                    if !preset.citationIds.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("The science")
                                .font(.headline)
                                .padding(.top, 8)

                            ForEach(preset.citationIds.compactMap { CitationRegistry.citation(forId: $0) }) { citation in
                                CitationLink(
                                    citation: citation,
                                    context: CitationRegistry.usageReason(forId: citation.id),
                                    compact: false
                                )
                            }
                        }
                    }

                    Spacer()
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { infoPreset = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func rowLabel(_ id: String, _ title: String, _ subtitle: String) -> some View {
        Button { selectedID = id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selectedID == id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedID == id ? Color.accentColor : Color.secondary)
            }
        }
        .foregroundStyle(.primary)
        .accessibilityIdentifier("interval.preset.\(id)")
    }
}

struct IntervalLaunch: Identifiable {
    let id = UUID()
    let plan: IntervalPlan
    let saveType: CardioType
    var captureHR: Bool = false
}
