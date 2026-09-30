import SwiftUI
import Combine
import AVFoundation
import Speech
import CadenceCore
import CadenceFeatures

@_silgen_name("CadenceInstallAudioTap")
private func cadenceInstallAudioTap(_ inputNode: AVAudioInputNode,
                                   _ bufferSize: AVAudioFrameCount,
                                   _ format: AVAudioFormat?,
                                   _ block: @escaping AVAudioNodeTapBlock)

@MainActor
final class VoiceCaptureController: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    @Published private(set) var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func clear() {
        transcript = ""
        errorMessage = nil
    }

    private func start() {
        errorMessage = nil
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is unavailable right now."
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let allowed = await requestPermissions()
            guard allowed else {
                errorMessage = "Microphone and speech access are needed for voice logging."
                return
            }
            beginRecognition(with: recognizer)
        }
    }

    private func requestPermissions() async -> Bool {
        let speech: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        let microphone: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission {
                continuation.resume(returning: $0)
            }
        }
        return speech == .authorized && microphone
    }

    private func beginRecognition(with recognizer: SFSpeechRecognizer) {
        stop()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        cadenceInstallAudioTap(input, 1_024, format) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
            let level = buffer.floatChannelData?.pointee
            _ = level // Keep the tap allocation-free; the transcript is the useful feedback.
            _ = self
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement,
                                    options: [.mixWithOthers, .allowBluetoothHFP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result { transcript = result.bestTranscription.formattedString }
                    if error != nil { stop() }
                }
            }
        } catch {
            errorMessage = "Could not start the microphone."
            stop()
        }
    }

    func stop() {
        guard isRecording || request != nil else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

}

struct VoiceLoggingSheet: View {
    let currentExercise: String?
    let exercises: [String]
    let performers: [String]
    let activePerformer: String?
    let unit: MeasurementUnitPreference
    let bodyweight: Bool
    let onAction: (VoiceResolvedAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var capture = VoiceCaptureController()
    @State private var phrase = ""
    @State private var resolution: VoiceResolutionResult?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Say what you did, such as “Audrey did 20 reps at 57 pounds” or “same again”.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("Transcript", text: $phrase, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("voice.transcript")
                    HStack(spacing: 12) {
                        Button {
                            capture.toggle()
                        } label: {
                            Label(capture.isRecording ? "Stop listening" : "Listen",
                                  systemImage: capture.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(capture.isRecording ? .red : CadenceTheme.accent)
                        .accessibilityIdentifier("voice.listen")
                        Button("Clear") {
                            phrase = ""
                            resolution = nil
                            capture.clear()
                        }
                        .buttonStyle(.bordered)
                    }
                    if capture.isRecording {
                        Label("Listening…", systemImage: "waveform")
                            .foregroundStyle(CadenceTheme.accent)
                    }
                    if let error = capture.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text("Quick Talk")
                }

                if !phrase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Button("Review command") {
                            review()
                        }
                        .accessibilityIdentifier("voice.review")
                    }
                }

                if let resolution {
                    Section("Review") {
                        if let action = resolution.action {
                            Text(actionSummary(action)).font(.headline)
                            Button("Apply") {
                                onAction(action)
                                dismiss()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(CadenceTheme.accent)
                            .accessibilityIdentifier("voice.apply")
                        } else {
                            Label(resolution.clarification ?? "I need a little more detail.",
                                  systemImage: "questionmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Quick Talk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: capture.transcript) { _, value in
                if !value.isEmpty { phrase = value }
            }
            .onDisappear { capture.stop() }
        }
    }

    private func review() {
        let parsed = VoiceCommandParser.parse(phrase, unit: unit, bodyweight: bodyweight)
        resolution = VoiceCommandResolver.resolve(parsed, currentExercise: currentExercise,
                                                  exercises: exercises, performers: performers,
                                                  activePerformer: activePerformer)
    }

    private func actionSummary(_ action: VoiceResolvedAction) -> String {
        switch action {
        case .logSet(let exercise, let weightKg, let reps, _, let warmup, let performer):
            let weight = weightKg.map { Format.weight($0, unit: unit) } ?? "bodyweight"
            return "\(warmup ? "Warm-up" : "Log") \(exercise.name): \(weight) × \(reps) for \(performer.name)"
        case .repeatLastSet(let exercise, let performer, let adjust):
            return "Repeat \(exercise.name) for \(performer.name)" + (adjust == nil ? "" : " with adjustment")
        case .adjustNext(let exercise, let deltaKg):
            return "Adjust the next \(exercise.name) set by \(Format.weight(deltaKg, unit: unit))"
        case .addExercise(let name): return "Add \(name)"
        case .switchExercise(let name): return "Switch to \(name)"
        case .setPerformer(let performer): return "Use \(performer.name) for the next set"
        case .addPartner(let name): return "Add partner \(name)"
        case .rest(let seconds): return seconds.map { "Rest \($0 / 60) minutes" } ?? "Start rest"
        case .skipRest: return "Skip rest"
        case .pause: return "Pause workout"
        case .resume: return "Resume workout"
        case .undo: return "Undo the last set"
        case .startWorkout(let name): return "Start \(name ?? "workout")"
        case .finishWorkout: return "Finish workout"
        }
    }
}
