import SwiftUI
import CadenceCore

/// Identifiable descriptor so a Coach-launched timer-cardio target can drive
/// `.sheet(item:)` from Home.
struct TimerCardioSetup: Identifiable {
    let id = UUID()
    let type: CardioType
    let suggestedMinutes: Int?
}

/// A compact setup surface for non-GPS timer cardio (rowing, "Other" indoor
/// cardio) reached from a Coach Start. Coach recommendations must always land on
/// a workout's settings before any recording begins (field-testing audio/coach
/// routing plan §D): this screen shows the target type, the Coach's suggested
/// duration (read-only), and the HR-monitoring toggle, and only starts the live
/// recorder after the user taps **Start**.
struct TimerCardioSetupView: View {
    let type: CardioType
    /// Coach's suggested duration, shown as read-only guidance. nil ⇒ hidden.
    var suggestedMinutes: Int? = nil
    /// Forwarded to the live recorder so Home can refresh on save.
    var onSaved: (CardioWorkout) -> Void = { _ in }

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var started = false

    var body: some View {
        if started {
            // The setup is the "settings first" gate; the recorder begins only now.
            RecordCardioView(initialType: type, captureHR: settings.useHRMonitoring, onSaved: onSaved)
        } else {
            setupScreen
        }
    }

    private var setupScreen: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: type.symbol).scaledSystemFont(64, relativeTo: .largeTitle).foregroundStyle(.tint)
                Text(type.displayName).font(.title2.bold())

                if let suggestedMinutes {
                    Label("Coach suggests \(suggestedMinutes) min", systemImage: "clock")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("timerCardio.suggested")
                }

                HStack {
                    @Bindable var settings = settings
                    Toggle("Use HR monitoring", isOn: $settings.useHRMonitoring)
                        .accessibilityIdentifier("timerCardio.hrToggle")
                }

                Button {
                    started = true
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.title3.bold()).frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("timerCardio.start")

                Spacer()
            }
            .padding()
            .navigationTitle("\(type.displayName) setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("timerCardio.cancel")
                }
            }
        }
    }
}
