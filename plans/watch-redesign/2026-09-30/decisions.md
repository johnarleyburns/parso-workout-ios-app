# Decisions — Cladiron watch redesign

Settled decisions are not re-litigated. Recorded 2026-09-30.

| # | Question | Decision |
|---|---|---|
| D-W1 | Apple-Workout-style pager while training (Controls ◂ Set Card ▸ Plan ▸ Heart)? | **Yes** (owner approved the recommendation) |
| D-W2 | Speech-to-text engine for Quick Talk on the watch | **B: record on the watch, transcribe on the iPhone; C (system dictation) when the phone isn't reachable.** A is impossible (evidence below) |
| D-W3 | Partner auto-rotation after each logged set | **On** when partners exist; the chip shows who's next |
| D-W4 | Crown default focus on the Set Card | **Weight** |
| D-W5 | Action Button (Ultra) | **Talk** while a workout runs; **Start today's plan** otherwise |

## D-W2 evidence (checked against the installed SDKs, Xcode with WatchOS26.5.sdk)

- `WatchOS26.5.sdk/System/Library/Frameworks` contains **no `Speech.framework`** (only `AVFAudio`, `SoundAnalysis`).
  No header or module in the watchOS SDK mentions `SpeechAnalyzer` or `SFSpeechRecognizer`.
- The iOS SDK's `Speech.framework` carries **39 `@available(watchOS, unavailable)`** annotations. Option A (on-watch
  recognition) is unavailable on watchOS 26.
- Recording on the watch is supported: `AVAudioRecorder` (`API_AVAILABLE(... watchos(4.0))`) and
  `AVAudioEngine.inputNode` (`watchos(4.0)`).
- Transport: `WCSession.sendMessageData(_:replyHandler:errorHandler:)` is available on watchOS.
- Phone transcription: the existing `SpeechAnalyzerTranscriptionEngine` (`Cadence/Cadence/Features/Train/
  SpeechAnalyzerCapture.swift`) is buffer-based (`prepare(format:)` / `append(_:)` / `finish()`), and the iOS 26
  SDK also has `SpeechAnalyzer(inputAudioFile:modules:...)` and `analyzeSequence(from: AVAudioFile)`. Either path
  feeds the existing `VoiceCommandParser`.
- `SoundAnalysis` exists on watchOS but classifies sounds; it does not transcribe speech. Not a substitute.

## Consequences for the design

- **B-clip first:** hold → record ≤10 s mono 16 kHz AAC → release → `sendMessageData` → the iPhone transcribes →
  it replies with the transcript; **the watch** parses, resolves and executes (`CadenceFeatures`), so D4 and the
  review rules run where the set is logged. While holding, V1 shows a waveform and "Listening"; the transcript
  appears after release (≈0.5–1.5 s, labelled "Transcribing on iPhone…", V7).
- **B-stream is a later upgrade:** sending ~0.5 s PCM chunks during the hold for live partial transcripts. Only
  worth it if device testing shows B-clip latency feels slow.
- **C fallback:** when `WCSession.isReachable` is false, the Talk affordances open the system dictation input (a
  `TextField` with dictation) and its text goes through the same parser and rules. The hold gesture becomes a tap
  with the label "Dictate"; V7 says "iPhone not nearby, using dictation".
- **Validate on device:** the phone app is woken in the background by the message and must finish transcription
  within its background window, with the `SpeechAnalyzer` assets already installed (from phone Quick Talk
  setup). WatchConnectivity message payloads are size-limited, so keep clips well under it at ≤10 s / ~24 kbps,
  and fall back to `transferFile` if a clip is larger. Measure end-to-end latency at the gym.
- **Privacy:** the clip is deleted on both devices right after transcription; `HeardVoiceLog` keeps text only.
  The mic-permission priming copy says speech goes to "your iPhone", not "your devices", for accuracy.
