import SwiftUI
import CadenceCore

/// Live iPhone workout recording (FR-2.2–2.5).
struct RecordCardioView: View {
    /// When set (from the Start Workout picker, field-testing §02), recording
    /// begins immediately for this type, skipping the in-view grid.
    var initialType: CardioType? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    @State private var recorder: CardioRecorder?
    @State private var started = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let types: [CardioType] = [.run, .cycle, .walk, .boxing, .hiit, .rowing]

    var body: some View {
        NavigationStack {
            Group {
                if started, let recorder {
                    liveScreen(recorder)
                } else {
                    activityPicker
                }
            }
            .navigationTitle(started ? "Recording" : "Record Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("record.cancel")
                }
            }
        }
        .onReceive(timer) { _ in recorder?.tick() }
        .interactiveDismissDisabled(started)
        .onAppear { if let t = initialType, !started { startRecorder(t) } }
    }

    private func startRecorder(_ type: CardioType) {
        let r = CardioRecorder(location: model.location, hrm: model.hrm)
        r.start(type: type)
        recorder = r
        started = true
    }

    private var activityPicker: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                ForEach(types) { type in
                    Button {
                        startRecorder(type)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type.symbol).font(.largeTitle)
                            Text(type.displayName).font(.headline)
                            if type.usesGPS {
                                Text("GPS").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 110)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("record.start.\(type.rawValue)")
                }
            }
            .padding()
        }
    }

    private func liveScreen(_ recorder: CardioRecorder) -> some View {
        VStack(spacing: 20) {
            Text(recorder.type.displayName)
                .font(.title3.weight(.semibold))

            Text(Format.duration(TimeInterval(recorder.elapsed)))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityIdentifier("record.elapsed")

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                if recorder.type.usesGPS {
                    metric("Distance", Format.distance(recorder.distanceMeters), id: "record.distance")
                    metric("Pace", CardioMath.formatPace(secPerKm: recorder.pace), id: "record.pace")
                }
                metric("Heart Rate", Format.heartRate(recorder.currentBPM), id: "record.hr")
                metric("Zone", recorder.currentBPM == nil ? "—" : "Z\(recorder.zone) · \(CardioMath.zoneName(recorder.zone))", id: "record.zone")
                metric("Calories", "\(Int(recorder.calories)) kcal", id: "record.calories")
                metric("Avg HR", Format.heartRate(recorder.avgHR), id: "record.avgHr")
            }

            if !recorder.strapConnected {
                Button {
                    recorder.connectStrap()
                } label: { Label("Connect HR Strap", systemImage: "antenna.radiowaves.left.and.right") }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("record.connectStrap")
            } else {
                Label("Strap connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.subheadline)
                    .accessibilityIdentifier("record.strapConnected")
            }

            Spacer()

            HStack(spacing: 16) {
                Button {
                    recorder.isPaused ? recorder.resume() : recorder.pause()
                } label: {
                    Label(recorder.isPaused ? "Resume" : "Pause",
                          systemImage: recorder.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityIdentifier("record.pause")

                Button {
                    Task { await endWorkout(recorder) }
                } label: {
                    Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.red)
                .accessibilityIdentifier("record.end")
            }
        }
        .padding()
    }

    private func metric(_ title: String, _ value: String, id: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func endWorkout(_ recorder: CardioRecorder) async {
        let summary = recorder.end()
        let hkID = await model.health.saveCardioWorkout(summary)
        try? WorkoutRepository.saveRecordedCardio(summary, source: .iphone,
                                                  healthKitWorkoutUUID: hkID, in: context)
        dismiss()
    }
}
