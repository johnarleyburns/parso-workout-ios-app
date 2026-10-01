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
    private var modernEngine: (any QuickTalkTranscriptionEngine)?

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    func clear() {
        transcript = ""
        errorMessage = nil
    }

    func start() {
        errorMessage = nil
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = String(localized: "Speech recognition is unavailable right now.")
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let allowed = await requestPermissions()
            guard allowed else {
                errorMessage = String(localized: "Microphone and speech access are needed for voice logging.")
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
        if #available(iOS 26.0, *) {
            let engine = SpeechAnalyzerTranscriptionEngine()
            engine.onTranscript = { [weak self] value in self?.transcript = value }
            modernEngine = engine
            Task { [weak engine] in
                guard let engine else { return }
                try? await engine.prepare(format: format)
            }
        }
        cadenceInstallAudioTap(input, 1_024, format) { [weak self, weak request] buffer, _ in
            if let engine = self?.modernEngine {
                Task { @MainActor in engine.append(buffer) }
            } else {
                request?.append(buffer)
            }
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
            if modernEngine == nil {
                task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let result { transcript = result.bestTranscription.formattedString }
                        if error != nil { stop() }
                    }
                }
            }
        } catch {
            errorMessage = String(localized: "Could not start the microphone.")
            stop()
        }
    }

    func stop() {
        guard isRecording || request != nil || modernEngine != nil else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        modernEngine?.finish()
        modernEngine = nil
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
    let smarterVoiceUnderstanding: Bool
    let initialPhrase: String?
    let onAction: (VoiceResolvedAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var capture = VoiceCaptureController()
    @State private var phrase = ""
    @State private var resolution: VoiceResolutionResult?
    @State private var isUnderstanding = false
    @State private var usedModelUnderstanding = false

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
                            usedModelUnderstanding = false
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
                        Button(isUnderstanding ? "Understanding…" : "Review command") {
                            review()
                        }
                        .disabled(isUnderstanding)
                        .accessibilityIdentifier("voice.review")
                    }
                }

                if let resolution {
                    Section("Review") {
                        if usedModelUnderstanding {
                            Label("Understood with Apple Intelligence — review before applying.",
                                  systemImage: "sparkles")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
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
            .onAppear {
                if phrase.isEmpty, let initialPhrase { phrase = initialPhrase }
            }
            .onDisappear { capture.stop() }
        }
    }

    private func review() {
        let parsed = VoiceCommandParser.parse(phrase, unit: unit, bodyweight: bodyweight)
        guard parsed.command == nil, smarterVoiceUnderstanding else {
            usedModelUnderstanding = false
            resolution = resolve(parsed)
            return
        }

        isUnderstanding = true
        let context = VoiceModelContext(currentExercise: currentExercise,
                                        exercises: exercises, performers: performers)
        Task { @MainActor in
            #if canImport(FoundationModels)
            let interpreter: (any VoiceModelInterpreting)?
            if #available(iOS 26.0, *) {
                interpreter = FoundationModelsVoiceInterpreter()
            } else {
                interpreter = nil
            }
            let enhanced = await VoiceModelFallback.enhance(parsed, phrase: phrase,
                                                             context: context,
                                                             interpreter: interpreter)
            usedModelUnderstanding = enhanced.command != nil && parsed.command == nil
            resolution = resolve(enhanced)
            #else
            resolution = resolve(parsed)
            usedModelUnderstanding = false
            #endif
            isUnderstanding = false
        }
    }

    private func resolve(_ parsed: VoiceParseResult) -> VoiceResolutionResult {
        VoiceCommandResolver.resolve(parsed, currentExercise: currentExercise,
                                     exercises: exercises, performers: performers,
                                     activePerformer: activePerformer)
    }

    private func actionSummary(_ action: VoiceResolvedAction) -> String {
        switch action {
        case .logSet(let exercise, let weightKg, let reps, _, let warmup, let performer):
            let weight = weightKg.map { Format.weight($0, unit: unit) } ?? String(localized: "bodyweight")
            return warmup
                ? String(localized: "Warm-up \(exercise.name): \(weight) × \(reps) for \(performer.name)")
                : String(localized: "Log \(exercise.name): \(weight) × \(reps) for \(performer.name)")
        case .repeatLastSet(let exercise, let performer, let adjust):
            return adjust == nil
                ? String(localized: "Repeat \(exercise.name) for \(performer.name)")
                : String(localized: "Repeat \(exercise.name) for \(performer.name) with adjustment")
        case .adjustNext(let exercise, let deltaKg):
            return String(localized: "Adjust the next \(exercise.name) set by \(Format.weight(deltaKg, unit: unit))")
        case .addExercise(let name): return String(localized: "Add \(name)")
        case .switchExercise(let name): return String(localized: "Switch to \(name)")
        case .setPerformer(let performer): return String(localized: "Use \(performer.name) for the next set")
        case .addPartner(let name): return String(localized: "Add partner \(name)")
        case .rest(let seconds): return seconds.map { String(localized: "Rest \($0 / 60) minutes") } ?? String(localized: "Start rest")
        case .skipRest: return String(localized: "Skip rest")
        case .pause: return String(localized: "Pause workout")
        case .resume: return String(localized: "Resume workout")
        case .undo: return String(localized: "Undo the last set")
        case .startWorkout(let name): return name.map { String(localized: "Start \($0)") } ?? String(localized: "Start workout")
        case .finishWorkout: return String(localized: "Finish workout")
        }
    }
}
