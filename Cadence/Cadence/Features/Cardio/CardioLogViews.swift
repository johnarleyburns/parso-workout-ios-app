import SwiftUI
import CadenceCore

/// Small entry for **Other Cardio** before a live recording (feedback batch 6
/// item 3): a free-text description (e.g. "Rowing") and whether to GPS-track it.
/// Presented inside the Start Workout picker's navigation stack; `onStart` hands
/// the choice back to Home, which routes to the GPS or timer recorder.
struct OtherCardioEntryView: View {
    let onStart: (_ description: String, _ gps: Bool) -> Void

    @State private var description = ""
    @State private var gps = false

    var body: some View {
        Form {
            Section("Other Cardio") {
                TextField("Description (e.g. Rowing)", text: $description)
                    .accessibilityIdentifier("otherCardio.desc")
                Toggle("GPS tracked", isOn: $gps)
                    .accessibilityIdentifier("otherCardio.gps")
            }
            Section {
                Button {
                    onStart(description, gps)
                } label: {
                    Label("Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .cadenceGlassButton(prominent: true, tint: .green)
                .accessibilityIdentifier("otherCardio.start")
            } footer: {
                Text("Records like any cardio workout; its description shows in history.")
            }
        }
        .navigationTitle("Other Cardio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// "Log Workout" type chooser (feedback batch 6 item 3, extended batch 7): pick a
/// workout type to record a past session manually — **Strength** (logged as sets
/// on the normal session screen) or a cardio/interval type / Other Cardio. It lands
/// in history identically to a live recording, just flagged "Logged".
struct LogWorkoutPicker: View {
    /// Called after a workout is saved so Home can refresh / dismiss.
    var onSaved: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    private let types: [CardioType] = [.run, .walk, .cycle, .swim, .hiit, .boxing]
    private let columns = [GridItem(.flexible(), spacing: 16),
                           GridItem(.flexible(), spacing: 16)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    // Strength leads the grid — logged as sets on the normal
                    // session screen (feedback batch 7 follow-up).
                    NavigationLink {
                        LogStrengthEntryView(onDone: { dismiss(); onSaved() })
                    } label: { tile("dumbbell", "Strength") }
                        .buttonStyle(.plain)
                        .tapHaptic()
                        .accessibilityIdentifier("logType.strength")
                    ForEach(types) { type in
                        NavigationLink {
                            LogCardioView(type: type) { dismiss(); onSaved() }
                        } label: { tile(type.symbol, type.displayName) }
                            .buttonStyle(.plain)
                            .tapHaptic()
                            .accessibilityIdentifier("logType.\(type.rawValue)")
                    }
                    NavigationLink {
                        LogCardioView(type: .other, isOther: true) { dismiss(); onSaved() }
                    } label: { tile("figure.mixed.cardio", "Other Cardio") }
                        .buttonStyle(.plain)
                        .tapHaptic()
                        .accessibilityIdentifier("logType.other")
                }
                .padding()
                .glassGroup(spacing: 16)
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("logType.cancel")
                }
            }
        }
    }

    private func tile(_ symbol: String, _ name: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.largeTitle)
            Text(name).font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .cadenceGlassBackground(
            in: RoundedRectangle(cornerRadius: 16, style: .continuous),
            interactive: true,
            fallback: AnyShapeStyle(.background.secondary))
    }
}

/// Manual entry for one logged cardio workout (feedback batch 6 item 3): when it
/// happened, how long, optional distance, and — for Other Cardio — a description.
struct LogCardioView: View {
    let type: CardioType
    var isOther: Bool = false
    let onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @State private var date = Date()
    @State private var minutes = 30
    @State private var distanceKm = ""
    @State private var descriptionText = ""

    private var showsDistance: Bool { type.usesGPS || isOther }

    var body: some View {
        Form {
            Section {
                DatePicker("When", selection: $date)
                    .accessibilityIdentifier("log.date")
            }
            if isOther {
                Section("Description") {
                    TextField("e.g. Rowing, Yardwork", text: $descriptionText)
                        .accessibilityIdentifier("log.desc")
                }
            }
            Section("Duration") {
                HStack {
                    Text("Minutes"); Spacer()
                    // Direct entry (feedback batch 7 item 3) — type the value, with
                    // the stepper kept only for quick ± nudges.
                    TextField("30", value: $minutes, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit().font(.headline)
                        .frame(maxWidth: 70)
                        .accessibilityIdentifier("log.minutes")
                    Stepper("Minutes", value: $minutes, in: 1...600, step: 5)
                        .labelsHidden()
                        .accessibilityIdentifier("log.minutesStepper")
                }
            }
            if showsDistance {
                Section("Distance (optional)") {
                    HStack {
                        Text("Kilometers"); Spacer()
                        TextField("0", text: $distanceKm)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                            .accessibilityIdentifier("log.distance")
                    }
                }
            }
            Section {
                Button { save() } label: {
                    Label("Log Workout", systemImage: "square.and.pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                // A positive, green action button like "Start Workout" (item 1).
                .cadenceGlassButton(prominent: true, tint: .green)
                .accessibilityIdentifier("log.save")
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Log \(isOther ? "Other Cardio" : type.displayName)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        let meters = Double(distanceKm.replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)).map { $0 * 1000 }
        _ = try? WorkoutRepository.saveLoggedCardio(
            type: type, start: date, durationSeconds: Double(minutes) * 60,
            distanceMeters: (meters ?? 0) > 0 ? meters : nil,
            customTitle: isOther ? descriptionText : nil, in: context)
        onSaved()
    }
}
