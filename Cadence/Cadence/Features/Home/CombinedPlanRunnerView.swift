import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

/// The first authored-plan runner for cardio and mobility. Strength stays on
/// the existing SessionView path; this surface owns only the combined-plan
/// lease it was handed by PlanningView.
struct CombinedPlanRunnerView: View {
    let session: Session
    let lease: LiveWorkoutLease
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(ActiveWorkoutModel.self) private var active

    @State private var runner: CombinedPlanRunner
    @State private var recorder: CardioRecorder?
    @State private var cardioSummaries: [CardioWorkoutSummary] = []
    @State private var didReleaseLease = false
    @State private var isPersisting = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: Session, lease: LiveWorkoutLease, onFinished: @escaping () -> Void) {
        self.session = session
        self.lease = lease
        self.onFinished = onFinished
        let plan = try! CombinedExecutionPlan(session: session)
        self._runner = State(initialValue: CombinedPlanRunner(plan: plan))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text(session.title)
                    .font(.title2.bold())

                if let step = runner.currentStep {
                    stepView(step)
                } else {
                    ContentUnavailableView("Session complete", systemImage: "checkmark.circle")
                }

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        togglePause()
                    } label: {
                        Label(runner.state == .paused ? "Resume" : "Pause",
                              systemImage: runner.state == .paused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .disabled(runner.state != .running && runner.state != .paused)
                    .accessibilityIdentifier("combined.pause")

                    Button {
                        finish()
                    } label: {
                        Label("Finish", systemImage: "checkmark")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isPersisting || runner.state == .idle || runner.state == .finished || runner.state == .cancelled)
                    .accessibilityIdentifier("combined.finish")
                }
            }
            .padding()
            .navigationTitle("Plan session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { cancel() }
                        .disabled(isPersisting)
                        .accessibilityIdentifier("combined.cancel")
                }
            }
        }
        .onAppear { startIfNeeded() }
        .onReceive(timer) { _ in tick() }
        .interactiveDismissDisabled(runner.state == .running || runner.state == .paused || isPersisting)
        .keepAwake(runner.state == .running || runner.state == .paused)
        .onDisappear {
            _ = recorder?.end()
            releaseLease()
        }
    }

    @ViewBuilder
    private func stepView(_ step: CombinedExecutionPlan.Step) -> some View {
        VStack(spacing: 14) {
            Label(step.title, systemImage: step.isCardio ? "figure.run" : "figure flexibility")
                .font(.title3.weight(.semibold))

            Text(Format.duration(TimeInterval(runner.currentStepElapsedSeconds)))
                .scaledSystemFont(56, relativeTo: .largeTitle, weight: .bold, design: .rounded)
                .monospacedDigit()
                .accessibilityIdentifier("combined.elapsed")

            if let duration = step.timedDurationSeconds, duration > 0 {
                ProgressView(value: Double(runner.currentStepElapsedSeconds), total: Double(duration))
                    .tint(.green)
                    .accessibilityIdentifier("combined.progress")
            }

            switch step {
            case let .cardio(item):
                Text(cardioDetail(item))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case let .mobility(item):
                Text(item.rounds.map { "\($0) round\($0 == 1 ? "" : "s") · Move with control" }
                     ?? "Move with control")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !step.isCardio || step.timedDurationSeconds == nil {
                Button {
                    advance()
                } label: {
                    Label("Complete step", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(runner.state != .running)
                .accessibilityIdentifier("combined.completeStep")
            }
        }
    }

    private func startIfNeeded() {
        guard runner.state == .idle else { return }
        runner.start()
        beginCurrentCardioIfNeeded()
    }

    private func tick() {
        guard runner.state == .running else { return }
        let priorStepID = runner.currentStep?.id
        recorder?.tick()
        runner.tick()
        guard runner.currentStep?.id != priorStepID else { return }
        stopCurrentCardio()
        if runner.state == .finished {
            persistAndClose()
        } else {
            beginCurrentCardioIfNeeded()
        }
    }

    private func togglePause() {
        if runner.state == .paused {
            runner.resume()
            recorder?.resume()
        } else {
            runner.pause()
            recorder?.pause()
        }
    }

    private func advance() {
        stopCurrentCardio()
        runner.completeCurrentStep()
        if runner.state == .finished {
            persistAndClose()
        } else {
            beginCurrentCardioIfNeeded()
        }
    }

    private func beginCurrentCardioIfNeeded() {
        guard case let .cardio(item) = runner.currentStep else {
            recorder = nil
            return
        }
        let recorder = CardioRecorder(location: model.location, hrm: model.hrm)
        recorder.start(type: cardioType(for: item.kind))
        self.recorder = recorder
    }

    private func stopCurrentCardio() {
        guard let recorder else { return }
        var summary = recorder.end()
        summary.customTitle = session.title
        cardioSummaries.append(summary)
        self.recorder = nil
    }

    private func finish() {
        stopCurrentCardio()
        guard runner.finish() else { return }
        persistAndClose()
    }

    private func cancel() {
        _ = runner.cancel()
        _ = recorder?.end()
        recorder = nil
        releaseLease()
        dismiss()
    }

    private func persistAndClose() {
        guard !isPersisting else { return }
        isPersisting = true
        Task { @MainActor in
            for summary in cardioSummaries {
                let healthKitID = await model.health.saveCardioWorkout(summary)
                _ = try? WorkoutRepository.saveRecordedCardio(
                    summary,
                    source: .iphone,
                    healthKitWorkoutUUID: healthKitID,
                    in: context)
            }
            releaseLease()
            onFinished()
            dismiss()
        }
    }

    private func releaseLease() {
        guard !didReleaseLease else { return }
        didReleaseLease = true
        _ = active.liveWorkout.release(lease)
    }

    private func cardioDetail(_ item: CardioItemSnapshot) -> String {
        var details = [item.kind.capitalized]
        if let duration = item.durationSeconds { details.append(Format.duration(TimeInterval(duration))) }
        if let distance = item.distanceMeters { details.append(Format.distance(distance)) }
        if let zone = item.targetZone { details.append("Zone \(zone)") }
        return details.joined(separator: " · ")
    }

    private func cardioType(for kind: String) -> CardioType {
        CardioType(rawValue: kind.lowercased()) ?? .other
    }
}
