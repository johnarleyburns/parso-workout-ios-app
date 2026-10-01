import SwiftUI
import SwiftData
import CadenceCore
import CadenceFeatures

extension SessionView {
    func quickTalkPressing(_ pending: SessionRenderModel.PendingSetDisplay,
                           exercise: Exercise?, pressing: Bool) {
        guard settings.voiceLoggingEnabled, let exercise else { return }
        if pressing {
            quickTalkTargetExercise = exercise.name
            quickTalkBodyweight = isBodyweight(exercise)
            quickTalkPending = pending
            quickTalkDelayTask?.cancel()
            quickTalkDelayTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                quickTalkCapture.start()
                quickTalkListening = true
            }
        } else {
            quickTalkDelayTask?.cancel()
            guard quickTalkListening else { return }
            quickTalkCapture.stop()
            quickTalkListening = false
            // SpeechAnalyzer finalizes its last result asynchronously. Give it
            // one main-actor turn before parsing, while retaining the visible
            // transcript if no final result arrives.
            DispatchQueue.main.async { finishQuickTalk() }
        }
    }

    func finishQuickTalk() {
        let phrase = quickTalkCapture.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, let exerciseName = quickTalkTargetExercise else { return }
        let parsed = VoiceCommandParser.parse(phrase, unit: settings.unit,
                                              bodyweight: quickTalkBodyweight)
        let resolution = VoiceEntityResolver().resolve(
            parsed, currentExercise: exerciseName,
            exercises: session.exercisesInOrder.map(\.name),
            performers: rosterEntries.map(\.name),
            activePerformer: quickTalkPending?.performerName)
        quickTalkTranscript = phrase
        quickTalkResolution = resolution
        var heard = HeardVoiceLog(entries: quickTalkHeardEntries)
        if let action = VoiceCommandExecutor().automaticAction(parsed: parsed, resolution: resolution) {
            let before = Set(session.orderedSets.map(\.id))
            applyVoiceAction(action)
            let after = session.orderedSets.first { !before.contains($0.id) }
            quickTalkUndoSetID = after?.id
            heard.append(HeardVoiceEntry(transcript: phrase, confidence: parsed.confidence,
                                         appliedAutomatically: true))
            quickTalkChipText = after.map { String(localized: "Logged \(Format.weight($0.weight, unit: settings.unit)) × \($0.reps)") }
                ?? String(localized: "Set logged")
            quickTalkChipVisible = true
            quickTalkFollowUp = QuickTalkFollowUpWindow(startedAt: Date())
        } else {
            heard.append(HeardVoiceEntry(transcript: phrase, confidence: parsed.confidence,
                                         appliedAutomatically: false))
            quickTalkChipText = resolution.clarification ?? "I need a little more detail."
            quickTalkChipVisible = true
        }
        if let data = try? JSONEncoder().encode(heard.entries) {
            UserDefaults.standard.set(data, forKey: "quickTalk.heardEntries")
        }
        quickTalkCapture.clear()
    }

    func undoQuickTalk() {
        guard let id = quickTalkUndoSetID,
              let set = session.orderedSets.first(where: { $0.id == id }) else { return }
        try? WorkoutRepository.deleteSet(set, in: context)
        try? context.save()
        quickTalkUndoSetID = nil
        quickTalkChipVisible = false
    }

    @ViewBuilder
    var quickTalkOverlay: some View {
        VStack(spacing: 8) {
            if quickTalkListening {
                Label("Listening — release to log", systemImage: "waveform")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .cadenceGlass(in: Capsule(), tint: CadenceTheme.accent, interactive: true)
                    .accessibilityIdentifier("quickTalk.listening")
            } else if quickTalkChipVisible {
                HStack(spacing: 10) {
                    Image(systemName: quickTalkUndoSetID == nil ? "questionmark.circle" : "checkmark.circle.fill")
                    Text(quickTalkChipText).lineLimit(2)
                    Spacer(minLength: 4)
                    if quickTalkUndoSetID != nil {
                        Button("Undo") { undoQuickTalk() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("quickTalk.undo")
                    } else {
                        Button("Review") { voiceLoggingPresented = true }
                            .buttonStyle(.bordered)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .cadenceGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: true)
                .accessibilityIdentifier("quickTalk.confirmChip")
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)
        .onChange(of: quickTalkFollowUp) { _, value in
            guard value != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + QuickTalkFollowUpWindow.duration) {
                if quickTalkFollowUp?.accepts(Date()) == false || quickTalkUndoSetID == nil {
                    quickTalkChipVisible = false
                }
            }
        }
    }
}
